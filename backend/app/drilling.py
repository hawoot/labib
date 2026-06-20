"""The drilling engine: enrol, pick a session, mark answers, update mastery.

Deliberately simple and knob-free for now (the adaptive knobs are parked in
planning/feature-queue). Defaults: a balanced mode mix and a lightweight
SM-2-style spaced-repetition schedule.
"""
from __future__ import annotations

import datetime
import logging
import random

from sqlalchemy import or_
from sqlalchemy.orm import Session

from . import models
from .llm import complete_json

logger = logging.getLogger(__name__)

# Default mode mix (a future knob). Weights for choosing which question to show.
MODE_WEIGHTS = {"on_the_go": 0.4, "short_drill": 0.4, "deep_dive": 0.2}

# Intensity (chosen in the "Let's go" launcher) maps to which question modes are
# allowed. "On the go" keeps it light and quick — nothing that needs paper;
# "Deep dive" leans into harder problem-solving. Unknown/None = the full mix.
INTENSITY_MODES = {
    "on_the_go": {"on_the_go"},
    "short_drill": {"short_drill"},
    "deep_dive": {"deep_dive"},
}
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


def _pick_question(
    db: Session, skill_id: str, version: int, allowed_modes: set[str] | None = None
) -> models.Question | None:
    questions = (
        db.query(models.Question)
        .filter_by(skill_id=skill_id, curriculum_version=version)
        .all()
    )
    if not questions:
        return None
    # If an intensity was chosen, prefer questions in its allowed modes — but
    # fall back to the full set rather than show nothing for that skill.
    if allowed_modes:
        in_mode = [q for q in questions if q.mode in allowed_modes]
        if in_mode:
            questions = in_mode
    # Weight by the default mode mix, falling back to a uniform pick.
    weights = [MODE_WEIGHTS.get(q.mode, 0.1) for q in questions]
    return random.choices(questions, weights=weights, k=1)[0]


def build_session(
    db: Session,
    user: models.User,
    journey: models.Journey,
    limit: int,
    intensity: str | None = None,
) -> list[dict]:
    """Return up to `limit` questions to drill now: due skills first, then by lowest mastery.

    `intensity` ("on_the_go" / "deep_dive") narrows which question modes are
    eligible; None keeps the default balanced mix.
    """
    allowed_modes = INTENSITY_MODES.get(intensity or "")
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
        q = _pick_question(
            db, st.skill_id, journey.curriculum_version, allowed_modes
        )
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


def _grade_answer(
    skill: models.Skill | None,
    question: models.Question,
    answer: str,
    image: tuple[str, str] | None = None,
) -> tuple[bool, float, bool, str]:
    """Grade an answer with the LLM.

    `image`, when given, is (base64_data, media_type) — e.g. a photo of the
    student's worked-out solution — and is sent to the model alongside the text.

    Returns (graded, score, correct, feedback). If the LLM is unavailable or
    returns junk, we DON'T fail the request — we return graded=False so the
    caller records the attempt and shows the reference answer instead of losing
    the student's work. The study loop must survive a flaky model.
    """
    text = (
        f"SKILL: {skill.name if skill else ''}\n"
        f"QUESTION: {question.prompt}\n"
        f"REFERENCE ANSWER: {question.answer or '(none provided)'}\n"
        f"STUDENT ANSWER: {answer or '(see attached photo)'}\n\n"
        'Grade it. Produce JSON {"score": number 0..1, '
        '"correct": boolean, "feedback": "1-2 sentences, encouraging, '
        'correcting any mistakes"}.'
    )
    user_content: object = text
    if image is not None:
        user_content = [
            {"type": "text", "text": text},
            {"type": "image", "data": image[0], "media_type": image[1]},
        ]
    try:
        grade = complete_json(
            [
                {
                    "role": "system",
                    "content": "You are a supportive tutor grading a student's answer. "
                    "Output STRICT JSON only.",
                },
                {"role": "user", "content": user_content},
            ],
            max_tokens=2000,
        )
    except Exception as e:  # LLM down, rate-limited, or non-JSON after retries
        logger.warning("auto-grade unavailable for question %s: %s", question.id, e)
        return (
            False,
            0.0,
            False,
            "Your answer was saved, but automatic grading is unavailable right "
            "now. Compare it with the reference answer below.",
        )

    score = max(0.0, min(1.0, float(grade.get("score", 0) or 0)))
    correct = bool(grade.get("correct", score >= CORRECT_THRESHOLD))
    feedback = str(grade.get("feedback", "")).strip() or (
        "Looks right." if correct else "Not quite — see the reference answer."
    )
    return (True, score, correct, feedback)


def mark_attempt(
    db: Session,
    user: models.User,
    journey_id: str,
    question_id: str,
    answer: str,
    image: tuple[str, str] | None = None,
) -> dict:
    """Grade an answer, record the attempt, and (only if graded) update schedule."""
    question = db.get(models.Question, question_id)
    if question is None or question.journey_id != journey_id:
        raise ValueError("Question not found in this journey.")
    skill = db.get(models.Skill, question.skill_id)

    graded, score, correct, feedback = _grade_answer(skill, question, answer, image)

    db.add(
        models.Attempt(
            user_id=user.id,
            journey_id=journey_id,
            skill_id=question.skill_id,
            question_id=question_id,
            user_answer=answer or "(photo answer)",
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
    # Don't move mastery/schedule on an ungraded attempt — a transient LLM
    # failure shouldn't corrupt the spaced-repetition state.
    if state is not None and graded:
        _update_schedule(state, score, correct)
    db.commit()

    return {
        "graded": graded,
        "score": score,
        "correct": correct,
        "feedback": feedback,
        "answer": question.answer,
        "explanation": question.explanation,
        "mastery": round(state.mastery, 3) if state else None,
    }


def _last_user_text(history: list[dict]) -> str:
    """Pull the most recent student message's text out of the chat history,
    whether its content is a plain string or a list of parts (text + image)."""
    for msg in reversed(history):
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for part in content:
                if part.get("type") == "text" and part.get("text"):
                    return part["text"]
            return "(photo)"
    return "(chat)"


def chat_turn(
    db: Session,
    user: models.User,
    journey_id: str,
    question_id: str,
    history: list[dict],
) -> dict:
    """One turn of the per-question tutor chat. `history` is the conversation so
    far (LLM-format messages, content may include image parts). We prepend the
    question context as a system prompt and ask the model to reply AND judge
    whether the student has now answered correctly. On 'solved' we record the
    attempt and move the spaced-repetition schedule, once.

    Returns {reply, solved, score}. Survives a flaky model (returns a soft reply
    rather than erroring, so the chat never dead-ends)."""
    question = db.get(models.Question, question_id)
    if question is None or question.journey_id != journey_id:
        raise ValueError("Question not found in this journey.")
    skill = db.get(models.Skill, question.skill_id)

    system = (
        "You are labib, a warm, concise tutor helping a student with ONE question. "
        "Converse naturally — give hints, ask Socratic questions, explain when "
        "asked, and react to photos of their work. Keep replies short (1-4 "
        "sentences). Never dump the full solution unless they explicitly give up.\n\n"
        f"SKILL: {skill.name if skill else ''}\n"
        f"QUESTION: {question.prompt}\n"
        f"REFERENCE ANSWER: {question.answer or '(none provided)'}\n\n"
        'Always reply as STRICT JSON: {"reply": string, "solved": boolean, '
        '"score": number 0..1}. Set solved=true with score≈1 once the student '
        "has demonstrated the correct answer themselves. If they give up and you "
        "reveal the full answer, set solved=true and score=0. Otherwise solved=false."
    )
    messages = [{"role": "system", "content": system}, *history]
    try:
        data = complete_json(messages, max_tokens=1200)
        reply = str(data.get("reply", "")).strip() or "Tell me what you’re thinking."
        solved = bool(data.get("solved", False))
        score = max(0.0, min(1.0, float(data.get("score", 0) or 0)))
    except Exception as e:  # noqa: BLE001 - chat must survive a flaky model
        logger.warning("chat unavailable for %s: %s", question_id, e)
        return {
            "reply": "I’m having trouble responding right now — try again in a moment.",
            "solved": False,
            "score": 0.0,
        }

    if solved:
        db.add(
            models.Attempt(
                user_id=user.id,
                journey_id=journey_id,
                skill_id=question.skill_id,
                question_id=question_id,
                user_answer=_last_user_text(history),
                score=score,
                correct=score >= CORRECT_THRESHOLD,
                feedback=reply,
            )
        )
        state = (
            db.query(models.SkillState)
            .filter_by(user_id=user.id, skill_id=question.skill_id)
            .first()
        )
        if state is not None:
            _update_schedule(state, score, score >= CORRECT_THRESHOLD)
        db.commit()

    return {"reply": reply, "solved": solved, "score": score}


def assist(
    db: Session, journey_id: str, question_id: str, kind: str
) -> str:
    """In-question help. 'hint' nudges how to approach this problem without
    giving the answer; 'basics' steps back to the prerequisite ideas. Returns
    plain guidance text (falls back gracefully if the LLM is unavailable)."""
    from .llm import get_llm

    question = db.get(models.Question, question_id)
    if question is None or question.journey_id != journey_id:
        raise ValueError("Question not found in this journey.")
    skill = db.get(models.Skill, question.skill_id)

    if kind == "basics":
        ask = (
            "The student feels they're missing the fundamentals. Step back and "
            "explain, in a few short sentences, the prerequisite ideas they need "
            "to understand BEFORE this question. Do NOT solve the question."
        )
    else:
        ask = (
            "The student has the basics but doesn't know how to approach THIS "
            "problem. Give a short nudge on how to start and which method to use. "
            "Do NOT give the final answer."
        )
    try:
        return get_llm().complete(
            [
                {"role": "system", "content": "You are a concise, encouraging tutor."},
                {
                    "role": "user",
                    "content": (
                        f"SKILL: {skill.name if skill else ''}\n"
                        f"QUESTION: {question.prompt}\n\n{ask}"
                    ),
                },
            ],
            max_tokens=400,
        ).strip() or "Try breaking the problem into smaller steps."
    except Exception as e:  # noqa: BLE001 - help is best-effort
        logger.warning("assist unavailable for %s: %s", question_id, e)
        return "Help isn't available right now — try breaking it into smaller steps."


def reveal_answer(
    db: Session, user: models.User, journey_id: str, question_id: str
) -> dict:
    """Give up on a question: record it as 'not done' (a miss that moves the
    schedule) and return the reference answer + explanation."""
    question = db.get(models.Question, question_id)
    if question is None or question.journey_id != journey_id:
        raise ValueError("Question not found in this journey.")

    db.add(
        models.Attempt(
            user_id=user.id,
            journey_id=journey_id,
            skill_id=question.skill_id,
            question_id=question_id,
            user_answer="(revealed — not done)",
            score=0.0,
            correct=False,
            feedback="You asked to see the answer.",
        )
    )
    state = (
        db.query(models.SkillState)
        .filter_by(user_id=user.id, skill_id=question.skill_id)
        .first()
    )
    if state is not None:
        _update_schedule(state, 0.0, False)
    db.commit()
    return {"answer": question.answer, "explanation": question.explanation}


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
