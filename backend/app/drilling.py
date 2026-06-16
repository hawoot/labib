"""The drilling engine: enrol, pick a session, mark answers, update mastery.

Deliberately simple and knob-free for now (the adaptive knobs are parked in
planning/feature-queue). Defaults: a balanced mode mix and a lightweight
SM-2-style spaced-repetition schedule.
"""
from __future__ import annotations

import datetime
import random

from sqlalchemy import or_
from sqlalchemy.orm import Session

from . import models
from .llm import complete_json

# Default mode mix (a future knob). Weights for choosing which question to show.
MODE_WEIGHTS = {"on_the_go": 0.4, "short_drill": 0.4, "deep_dive": 0.2}
DEFAULT_SESSION_SIZE = 8
CORRECT_THRESHOLD = 0.6
MASTERY_ALPHA = 0.4


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def ensure_enrollment(db: Session, user: models.User, journey: models.Journey) -> None:
    """Make sure the user is enrolled and has a SkillState for every active skill."""
    if (
        db.query(models.Enrollment)
        .filter_by(user_id=user.id, journey_id=journey.id)
        .first()
        is None
    ):
        db.add(models.Enrollment(user_id=user.id, journey_id=journey.id))

    skills = (
        db.query(models.Skill)
        .filter_by(journey_id=journey.id, curriculum_version=journey.curriculum_version)
        .all()
    )
    existing = {
        s.skill_id
        for s in db.query(models.SkillState.skill_id)
        .filter_by(user_id=user.id, journey_id=journey.id)
        .all()
    }
    now = _now()
    for skill in skills:
        if skill.id not in existing:
            db.add(
                models.SkillState(
                    user_id=user.id,
                    journey_id=journey.id,
                    skill_id=skill.id,
                    due_at=now,  # new skills are due immediately
                )
            )
    db.commit()


def _pick_question(db: Session, skill_id: str, version: int) -> models.Question | None:
    questions = (
        db.query(models.Question)
        .filter_by(skill_id=skill_id, curriculum_version=version)
        .all()
    )
    if not questions:
        return None
    # Weight by the default mode mix, falling back to a uniform pick.
    weights = [MODE_WEIGHTS.get(q.mode, 0.1) for q in questions]
    return random.choices(questions, weights=weights, k=1)[0]


def build_session(
    db: Session, user: models.User, journey: models.Journey, limit: int
) -> list[dict]:
    """Return up to `limit` questions to drill now: due skills first, then by lowest mastery."""
    ensure_enrollment(db, user, journey)
    now = _now()
    states = (
        db.query(models.SkillState)
        .filter_by(user_id=user.id, journey_id=journey.id)
        .filter(or_(models.SkillState.due_at <= now, models.SkillState.reps == 0))
        .order_by(models.SkillState.due_at.asc(), models.SkillState.mastery.asc())
        .limit(limit)
        .all()
    )
    skill_by_id = {
        s.id: s
        for s in db.query(models.Skill).filter(
            models.Skill.id.in_([st.skill_id for st in states] or [""])
        )
    }
    session: list[dict] = []
    for st in states:
        q = _pick_question(db, st.skill_id, journey.curriculum_version)
        if q is None:
            continue
        skill = skill_by_id.get(st.skill_id)
        session.append(
            {
                "question_id": q.id,
                "skill_id": st.skill_id,
                "skill_name": skill.name if skill else "",
                "mode": q.mode,
                "prompt": q.prompt,
            }
        )
    return session


def mark_attempt(
    db: Session, user: models.User, journey_id: str, question_id: str, answer: str
) -> dict:
    """Grade an answer with the LLM, record the attempt, update mastery + schedule."""
    question = db.get(models.Question, question_id)
    if question is None or question.journey_id != journey_id:
        raise ValueError("Question not found in this journey.")
    skill = db.get(models.Skill, question.skill_id)

    grade = complete_json(
        [
            {
                "role": "system",
                "content": "You are a supportive tutor grading a student's answer. "
                "Output STRICT JSON only.",
            },
            {
                "role": "user",
                "content": (
                    f"SKILL: {skill.name if skill else ''}\n"
                    f"QUESTION: {question.prompt}\n"
                    f"REFERENCE ANSWER: {question.answer or '(none provided)'}\n"
                    f"STUDENT ANSWER: {answer}\n\n"
                    'Grade it. Produce JSON {"score": number 0..1, '
                    '"correct": boolean, "feedback": "1-2 sentences, encouraging, '
                    'correcting any mistakes"}.'
                ),
            },
        ],
        max_tokens=2000,
    )
    score = float(grade.get("score", 0) or 0)
    score = max(0.0, min(1.0, score))
    correct = bool(grade.get("correct", score >= CORRECT_THRESHOLD))
    feedback = str(grade.get("feedback", ""))

    db.add(
        models.Attempt(
            user_id=user.id,
            journey_id=journey_id,
            skill_id=question.skill_id,
            question_id=question_id,
            user_answer=answer,
            score=score,
            correct=correct,
            feedback=feedback,
        )
    )

    state = (
        db.query(models.SkillState)
        .filter_by(user_id=user.id, skill_id=question.skill_id)
        .first()
    )
    if state is not None:
        _update_schedule(state, score, correct)
    db.commit()

    return {
        "score": score,
        "correct": correct,
        "feedback": feedback,
        "answer": question.answer,
        "explanation": question.explanation,
        "mastery": round(state.mastery, 3) if state else None,
    }


def _update_schedule(state: models.SkillState, score: float, correct: bool) -> None:
    now = _now()
    state.mastery += MASTERY_ALPHA * (score - state.mastery)
    state.last_reviewed = now
    if correct:
        state.reps += 1
        state.interval_days = 1.0 if state.interval_days < 1 else min(60.0, state.interval_days * 2)
        state.due_at = now + datetime.timedelta(days=state.interval_days)
    else:
        state.reps = 0
        state.interval_days = 0.0
        state.due_at = now + datetime.timedelta(minutes=10)  # see it again soon
