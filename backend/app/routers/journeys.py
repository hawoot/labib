"""Journeys: the core thing a user creates and feeds material into."""
import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..deps import get_current_user
from ..schemas import JourneyCreate, JourneyOut
from ..storage import get_storage

router = APIRouter(prefix="/journeys", tags=["journeys"])

# Per-journey child rows, deleted (in FK-safe order) on a hard delete.
_CHILD_MODELS = (
    models.Attempt,
    models.SkillState,
    models.Enrollment,
    models.Question,
    models.Skill,
    models.Unit,
    models.Chunk,
    models.IngestionJob,
    models.Document,
)


def _own(journey: models.Journey, user: models.User) -> models.Journey:
    """Require the journey to belong to this user (not the shared library)."""
    if journey.owner_id != user.id:
        raise HTTPException(
            status_code=403, detail="You can only modify your own journeys."
        )
    return journey


def get_owned_journey(
    journey_id: str, user: models.User, db: Session
) -> models.Journey:
    """Fetch a journey the user may access (their own, or the shared library)."""
    journey = db.get(models.Journey, journey_id)
    if journey is None or journey.owner_id not in (None, user.id):
        raise HTTPException(status_code=404, detail="Journey not found.")
    return journey


@router.post("", response_model=JourneyOut, status_code=201)
def create_journey(
    payload: JourneyCreate,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    journey = models.Journey(
        owner_id=user.id, title=payload.title, intent=payload.intent or ""
    )
    db.add(journey)
    db.commit()
    db.refresh(journey)
    return journey


@router.get("", response_model=list[JourneyOut])
def list_journeys(
    archived: bool = False,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The user's own journeys plus anything in the shared library.

    Archived journeys are hidden by default; pass ?archived=true to list them.
    """
    archive_filter = (
        models.Journey.archived_at.isnot(None)
        if archived
        else models.Journey.archived_at.is_(None)
    )
    return (
        db.query(models.Journey)
        .filter(or_(models.Journey.owner_id == user.id, models.Journey.owner_id.is_(None)))
        .filter(archive_filter)
        .order_by(models.Journey.created_at.desc())
        .all()
    )


@router.get("/{journey_id}", response_model=JourneyOut)
def get_journey(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return get_owned_journey(journey_id, user, db)


@router.post("/{journey_id}/archive", response_model=JourneyOut)
def archive_journey(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Hide a journey from the list but keep all its data (reversible)."""
    journey = _own(get_owned_journey(journey_id, user, db), user)
    journey.archived_at = datetime.datetime.now(datetime.timezone.utc)
    db.commit()
    db.refresh(journey)
    return journey


@router.post("/{journey_id}/unarchive", response_model=JourneyOut)
def unarchive_journey(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Bring an archived journey back into the list."""
    journey = _own(get_owned_journey(journey_id, user, db), user)
    journey.archived_at = None
    db.commit()
    db.refresh(journey)
    return journey


@router.delete("/{journey_id}", status_code=204)
def delete_journey(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Hard delete: permanently remove the journey and everything under it
    (documents, uploaded files, chunks, curriculum, questions, practice
    history). Not reversible."""
    journey = _own(get_owned_journey(journey_id, user, db), user)

    # Remove uploaded files from storage first (best-effort).
    for doc in db.query(models.Document).filter_by(journey_id=journey.id).all():
        if doc.storage_key:
            try:
                get_storage().delete(doc.storage_key)
            except Exception:
                pass  # missing file shouldn't block the delete

    for model in _CHILD_MODELS:
        db.query(model).filter_by(journey_id=journey.id).delete(
            synchronize_session=False
        )
    db.delete(journey)
    db.commit()
