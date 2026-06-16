"""labib API — entry point.

Milestone 1 (the "walking skeleton"): prove the server runs, can reach the
database, and (optionally) can reach the configured AI provider.
"""
from contextlib import asynccontextmanager
import os

from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import models  # noqa: F401  (import so tables register on Base.metadata)
from .config import get_settings
from .db import Base, engine, get_db
from .routers import auth, documents, ingest, journeys
from .worker import start_worker, stop_worker


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Phase 0: create any missing tables on startup. (Alembic migrations land
    # once the schema stabilises / we move to managed Postgres.)
    Base.metadata.create_all(bind=engine)
    start_worker()  # background crunch worker
    yield
    stop_worker()


app = FastAPI(title="labib API", version="0.4.0", lifespan=lifespan)
app.include_router(auth.router)
app.include_router(journeys.router)
app.include_router(documents.router)
app.include_router(ingest.router)

# The built Flutter web app (if present) is served at /app, same origin as the API.
_WEBAPP_DIR = os.path.join(os.path.dirname(__file__), "webapp")
_HAS_WEBAPP = os.path.isdir(_WEBAPP_DIR)
if _HAS_WEBAPP:
    app.mount("/app", StaticFiles(directory=_WEBAPP_DIR, html=True), name="webapp")


@app.get("/")
def root():
    if _HAS_WEBAPP:
        return RedirectResponse("/app/")
    return {"name": "labib API", "status": "ok", "version": app.version}


@app.get("/health")
def health(db: Session = Depends(get_db)):
    """Liveness + database connectivity."""
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "ok"}


@app.get("/health/llm")
def health_llm():
    """Optional: confirm the configured AI provider/key actually works."""
    s = get_settings()
    if not s.llm_api_key:
        return {"status": "skipped", "reason": "no LLM_API_KEY set in .env"}
    try:
        from .llm import get_llm

        reply = get_llm(s).complete(
            [{"role": "user", "content": "Reply with the single word: pong"}],
            max_tokens=256,  # reasoning models burn tokens thinking; keep headroom
        )
    except Exception as e:  # surface the real error to help debugging
        raise HTTPException(status_code=502, detail=f"LLM call failed: {e}")
    return {
        "status": "ok",
        "provider": s.llm_provider,
        "model": s.llm_model,
        "reply": reply.strip(),
    }
