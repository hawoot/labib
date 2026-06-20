"""Drilling: get a study session, submit answers, view progress."""
import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import drilling, models
from ..db import get_db
from ..deps import get_current_user
from ..schemas import (
    AssistIn,
    AssistOut,
    AttemptCreate,
    AttemptResultOut,
    ChatIn,
    ChatOut,
    ProgressItem,
    ProgressOut,
    RevealOut,
    SessionItem,
    SessionOut,
)
from .journeys import get_owned_journey

router = APIRouter(prefix="/journeys/{journey_id}", tags=["drilling"])


@router.get("/session", response_model=SessionOut)
def get_session(
    journey_id: str,
    limit: int = drilling.DEFAULT_SESSION_SIZE,
    intensity: str | None = None,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    journey = get_owned_journey(journey_id, user, db)
    items = drilling.build_session(
        db, user, journey, max(1, min(limit, 50)), intensity=intensity
    )
    return SessionOut(journey_id=journey_id, items=[SessionItem(**i) for i in items])


@router.post("/attempts", response_model=AttemptResultOut)
def submit_attempt(
    journey_id: str,
    payload: AttemptCreate,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    get_owned_journey(journey_id, user, db)
    if not payload.answer.strip() and not payload.image:
        raise HTTPException(status_code=422, detail="Provide an answer or a photo.")
    image = (
        (payload.image, payload.image_media_type) if payload.image else None
    )
    try:
        result = drilling.mark_attempt(
            db, user, journey_id, payload.question_id, payload.answer, image
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return AttemptResultOut(**result)


@router.post("/questions/{question_id}/chat", response_model=ChatOut)
def chat(
    journey_id: str,
    question_id: str,
    payload: ChatIn,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    get_owned_journey(journey_id, user, db)
    history: list[dict] = []
    for m in payload.messages:
        if m.image:
            content: object = [
                {"type": "text", "text": m.text},
                {"type": "image", "data": m.image, "media_type": m.image_media_type},
            ]
        else:
            content = m.text
        history.append({"role": m.role, "content": content})
    try:
        result = drilling.chat_turn(db, user, journey_id, question_id, history)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return ChatOut(**result)


@router.post("/questions/{question_id}/assist", response_model=AssistOut)
def assist(
    journey_id: str,
    question_id: str,
    payload: AssistIn,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    get_owned_journey(journey_id, user, db)
    try:
        text = drilling.assist(db, journey_id, question_id, payload.kind)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return AssistOut(text=text)


@router.post("/questions/{question_id}/reveal", response_model=RevealOut)
def reveal(
    journey_id: str,
    question_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    get_owned_journey(journey_id, user, db)
    try:
        result = drilling.reveal_answer(db, user, journey_id, question_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return RevealOut(**result)


@router.get("/progress", response_model=ProgressOut)
def get_progress(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    journey = get_owned_journey(journey_id, user, db)
    drilling.ensure_enrollment(db, user, journey)
    now = datetime.datetime.now(datetime.timezone.utc)

    def _due(dt: datetime.datetime) -> bool:
        # SQLite returns naive datetimes; treat stored times as UTC.
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt <= now

    states = (
        db.query(models.SkillState)
        .filter_by(user_id=user.id, journey_id=journey_id)
        .all()
    )
    names = {
        s.id: s.name
        for s in db.query(models.Skill).filter(
            models.Skill.id.in_([st.skill_id for st in states] or [""])
        )
    }
    items = [
        ProgressItem(
            skill_id=st.skill_id,
            name=names.get(st.skill_id, ""),
            mastery=round(st.mastery, 3),
            reps=st.reps,
            due=_due(st.due_at),
        )
        for st in states
    ]
    return ProgressOut(
        journey_id=journey_id,
        skill_count=len(items),
        mastered=sum(1 for i in items if i.mastery >= 0.8),
        due=sum(1 for i in items if i.due),
        items=items,
    )
