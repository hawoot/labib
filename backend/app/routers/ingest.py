"""Trigger the crunch and poll its progress; browse the resulting curriculum."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..deps import get_current_user
from ..schemas import CurriculumOut, IngestionJobOut, QuestionOut, SkillOut
from .journeys import get_owned_journey

router = APIRouter(prefix="/journeys/{journey_id}", tags=["ingest"])


@router.post("/ingest", response_model=IngestionJobOut, status_code=202)
def start_ingest(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Queue a crunch for this journey. The background worker picks it up."""
    journey = get_owned_journey(journey_id, user, db)
    if not journey.documents:
        raise HTTPException(status_code=400, detail="Add a document before crunching.")
    active = (
        db.query(models.IngestionJob)
        .filter(
            models.IngestionJob.journey_id == journey_id,
            models.IngestionJob.status.in_(("queued", "running")),
        )
        .first()
    )
    if active:
        return active  # already crunching; don't double-queue
    job = models.IngestionJob(journey_id=journey_id)
    db.add(job)
    journey.status = "crunching"
    db.commit()
    db.refresh(job)
    return job


@router.get("/ingest", response_model=IngestionJobOut)
def latest_ingest(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Poll the most recent crunch job (status / phase / progress)."""
    get_owned_journey(journey_id, user, db)
    job = (
        db.query(models.IngestionJob)
        .filter_by(journey_id=journey_id)
        .order_by(models.IngestionJob.created_at.desc())
        .first()
    )
    if job is None:
        raise HTTPException(status_code=404, detail="No crunch has been run yet.")
    return job


@router.get("/curriculum", response_model=CurriculumOut)
def get_curriculum(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The active (current-version) skills and their question banks."""
    journey = get_owned_journey(journey_id, user, db)
    v = journey.curriculum_version
    skills = (
        db.query(models.Skill)
        .filter_by(journey_id=journey_id, curriculum_version=v)
        .order_by(models.Skill.ordinal)
        .all()
    )
    out: list[SkillOut] = []
    q_total = 0
    for s in skills:
        qs = (
            db.query(models.Question)
            .filter_by(skill_id=s.id, curriculum_version=v)
            .all()
        )
        q_total += len(qs)
        out.append(
            SkillOut(
                id=s.id,
                unit_id=s.unit_id,
                name=s.name,
                description=s.description,
                questions=[QuestionOut.model_validate(q) for q in qs],
            )
        )
    return CurriculumOut(
        journey_id=journey_id,
        curriculum_version=v,
        skill_count=len(skills),
        question_count=q_total,
        skills=out,
    )
