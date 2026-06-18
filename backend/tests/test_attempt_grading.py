"""Regression test for the chronic "attempt failed / not JSON" error.

The bug: submitting an answer grades it with an LLM call that must return JSON.
When the model hiccuped (rate limit, timeout, prose instead of JSON), the whole
request failed — the student's answer was lost and the study loop broke.

The fix: grading degrades gracefully. A failed grade still records the attempt
(graded=False), returns the reference answer, and leaves the spaced-repetition
schedule untouched. A successful grade behaves as before and moves mastery.

    cd backend && python tests/test_attempt_grading.py
"""
import os
import sys
import tempfile

os.environ["DATABASE_URL"] = "sqlite:///" + tempfile.mkstemp(suffix=".db")[1]
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from app import drilling, models  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402


def _seed(db, journey_id):
    """A skill + question + per-user schedule state for that journey."""
    skill = models.Skill(
        journey_id=journey_id, name="Adding", description="", content_key="k"
    )
    db.add(skill)
    db.flush()
    q = models.Question(
        skill_id=skill.id, journey_id=journey_id, mode="short_drill",
        prompt="2+2?", answer="4", explanation="basic",
    )
    db.add(q)
    db.commit()
    return skill.id, q.id


def main() -> int:
    with TestClient(app) as c:
        uid = c.post("/auth/anonymous").json()["user_id"]
        h = {"X-User-Id": uid}
        jid = c.post("/journeys", headers=h, json={"title": "M", "intent": ""}).json()["id"]

        db = SessionLocal()
        skill_id, qid = _seed(db, jid)
        # Make sure a SkillState exists (so we can prove the schedule is/ isn't moved).
        c.get(f"/journeys/{jid}/progress", headers=h)

        # 1) LLM fails -> request still succeeds, attempt saved, schedule untouched.
        drilling.complete_json = lambda *a, **k: (_ for _ in ()).throw(
            RuntimeError("model exploded")
        )
        r = c.post(f"/journeys/{jid}/attempts", headers=h,
                   json={"question_id": qid, "answer": "4"})
        assert r.status_code == 200, f"expected 200, got {r.status_code}: {r.text}"
        body = r.json()
        assert body["graded"] is False, body
        assert body["answer"] == "4", body  # reference answer still surfaced
        n = db.query(models.Attempt).filter_by(user_id=uid, question_id=qid).count()
        assert n == 1, f"attempt should be recorded even when ungraded, got {n}"
        st = db.query(models.SkillState).filter_by(user_id=uid, skill_id=skill_id).first()
        assert st is not None and st.reps == 0 and st.mastery == 0.0, \
            "ungraded attempt must not move the schedule"

        # 2) LLM works -> graded, mastery moves.
        drilling.complete_json = lambda *a, **k: {
            "score": 1.0, "correct": True, "feedback": "Nice."
        }
        r = c.post(f"/journeys/{jid}/attempts", headers=h,
                   json={"question_id": qid, "answer": "4"})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["graded"] is True and body["correct"] is True, body
        db.expire_all()
        st = db.query(models.SkillState).filter_by(user_id=uid, skill_id=skill_id).first()
        assert st.reps == 1 and st.mastery > 0.0, "graded attempt must move the schedule"

    print("PASS: ungraded attempt is saved without breaking; graded attempt scores")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
