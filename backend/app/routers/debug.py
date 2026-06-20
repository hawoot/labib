"""Read-only inspection endpoints for debugging the live runtime.

A window into the running instance: row counts, table contents (with search),
a deep dump of a single journey, and the effective config. Everything is
read-only.

Gating: set DEBUG_KEY in the environment and pass it as the `X-Debug-Key`
header. If DEBUG_KEY is unset the endpoints are open — convenient on a private
box, but set the key before exposing the API publicly.
"""
from __future__ import annotations

import datetime

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy import String, Text, inspect as sa_inspect, or_
from sqlalchemy.orm import Session

from .. import models
from ..config import get_settings
from ..db import get_db

router = APIRouter(prefix="/debug", tags=["debug"])

# Whitelist of inspectable tables (name -> ORM model).
_TABLES: dict[str, type] = {
    "users": models.User,
    "journeys": models.Journey,
    "documents": models.Document,
    "chunks": models.Chunk,
    "units": models.Unit,
    "skills": models.Skill,
    "questions": models.Question,
    "ingestion_jobs": models.IngestionJob,
    "enrollments": models.Enrollment,
    "skill_states": models.SkillState,
    "attempts": models.Attempt,
}


def require_debug_key(x_debug_key: str | None = Header(default=None)) -> None:
    configured = get_settings().debug_key
    if configured and x_debug_key != configured:
        raise HTTPException(status_code=401, detail="Bad or missing X-Debug-Key.")


def _row_to_dict(row) -> dict:
    out: dict = {}
    for col in sa_inspect(row).mapper.column_attrs:
        value = getattr(row, col.key)
        if isinstance(value, datetime.datetime):
            value = value.isoformat()
        out[col.key] = value
    return out


@router.get("/stats", dependencies=[Depends(require_debug_key)])
def stats(db: Session = Depends(get_db)):
    """Row counts per table + the effective (non-secret) config."""
    s = get_settings()
    return {
        "counts": {name: db.query(model).count() for name, model in _TABLES.items()},
        "config": {
            "app_env": s.app_env,
            "llm_provider": s.llm_provider,
            "llm_model": s.llm_model,
            "llm_base_url": s.llm_base_url,
            "database": s.sqlalchemy_url.split("://", 1)[0],
            "debug_key_set": bool(s.debug_key),
        },
        "server_time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


@router.get("/tables/{table}", dependencies=[Depends(require_debug_key)])
def table_rows(
    table: str,
    q: str | None = Query(default=None, description="substring match over text columns"),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """Browse/search a table. `q` matches as a substring across all of the
    table's text columns (case-insensitive)."""
    model = _TABLES.get(table)
    if model is None:
        raise HTTPException(
            status_code=404, detail=f"Unknown table. Known: {sorted(_TABLES)}"
        )
    query = db.query(model)
    if q:
        text_cols = [
            c for c in model.__table__.columns if isinstance(c.type, (String, Text))
        ]
        if text_cols:
            query = query.filter(or_(*[c.ilike(f"%{q}%") for c in text_cols]))
    total = query.count()
    rows = query.limit(limit).offset(offset).all()
    return {
        "table": table,
        "total": total,
        "limit": limit,
        "offset": offset,
        "rows": [_row_to_dict(r) for r in rows],
    }


@router.get("/journey/{journey_id}", dependencies=[Depends(require_debug_key)])
def journey_dump(journey_id: str, db: Session = Depends(get_db)):
    """Everything tied to one journey, in one payload — for tracing a crunch."""
    journey = db.get(models.Journey, journey_id)
    if journey is None:
        raise HTTPException(status_code=404, detail="No such journey.")

    def child(model) -> list[dict]:
        return [
            _row_to_dict(r)
            for r in db.query(model).filter_by(journey_id=journey_id).all()
        ]

    return {
        "journey": _row_to_dict(journey),
        "documents": child(models.Document),
        "chunks": child(models.Chunk),
        "units": child(models.Unit),
        "skills": child(models.Skill),
        "questions": child(models.Question),
        "ingestion_jobs": child(models.IngestionJob),
    }
