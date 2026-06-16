"""Journeys: the core thing a user creates and feeds material into."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..deps import get_current_user
from ..schemas import JourneyCreate, JourneyOut

router = APIRouter(prefix="/journeys", tags=["journeys"])


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
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The user's own journeys plus anything in the shared library."""
    return (
        db.query(models.Journey)
        .filter(or_(models.Journey.owner_id == user.id, models.Journey.owner_id.is_(None)))
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
