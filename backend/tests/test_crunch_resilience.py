"""The crunch must survive a flaky model: skip the window/skill that fails,
keep everything that worked, and only fail outright if nothing usable came out.

    cd backend && python tests/test_crunch_resilience.py
"""
import os
import re
import sys
import tempfile

os.environ["DATABASE_URL"] = "sqlite:///" + tempfile.mkstemp(suffix=".db")[1]
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import crunch, models  # noqa: E402
from app.db import Base, SessionLocal, engine  # noqa: E402

PARAS = [f"CHUNK{i} " + ("lorem ipsum " * 120) for i in range(50)]
DOC_TEXT = "\n\n".join(PARAS)


def _new_journey(db):
    j = models.Journey(title="t", intent="")
    db.add(j)
    db.flush()
    db.add(models.Document(journey_id=j.id, kind="text", title="d"))
    job = models.IngestionJob(journey_id=j.id)
    db.add(job)
    db.commit()
    return j, job


def main() -> int:
    crunch.parse_document = lambda _doc: DOC_TEXT
    Base.metadata.create_all(engine)
    db = SessionLocal()

    # --- 1) One structure window blows up; the others carry the crunch. ----
    def fake_one_window_fails(messages, **_):
        system = " ".join(m["content"] for m in messages if m["role"] == "system")
        user = " ".join(m["content"] for m in messages if m["role"] == "user")
        if "curriculum designer" in system:
            marker = re.search(r"\[0\] (CHUNK\d+)", user).group(1)
            if marker == "CHUNK24":
                raise RuntimeError("structuring blip")
            return {"units": [{"title": f"U {marker}", "skills": [
                {"name": f"S {marker}", "description": "d", "source_chunks": [0]}]}]}
        return {"questions": [{"mode": "on_the_go", "prompt": "p",
                               "answer": "a", "explanation": "e"}]}

    crunch.complete_json = fake_one_window_fails
    j, job = _new_journey(db)
    crunch.run_crunch(db, j, job)

    skills = db.query(models.Skill).filter_by(journey_id=j.id).all()
    starts = sorted(int(re.search(r"CHUNK(\d+)", s.name).group(1)) for s in skills)
    assert starts == [0, 48], f"failed window should be skipped, got {starts}"
    assert j.status == "ready" and job.phase == "done", (j.status, job.phase)
    qn = db.query(models.Question).filter_by(journey_id=j.id).count()
    assert qn > 0, "surviving skills should still get questions"

    # --- 2) Every question call fails -> crunch fails (no empty journey). ---
    def fake_no_questions(messages, **_):
        system = " ".join(m["content"] for m in messages if m["role"] == "system")
        if "curriculum designer" in system:
            user = " ".join(m["content"] for m in messages if m["role"] == "user")
            marker = re.search(r"\[0\] (CHUNK\d+)", user).group(1)
            return {"units": [{"title": "U", "skills": [
                {"name": f"S {marker}", "description": "d", "source_chunks": [0]}]}]}
        raise RuntimeError("question blip")

    crunch.complete_json = fake_no_questions
    j2, job2 = _new_journey(db)
    try:
        crunch.run_crunch(db, j2, job2)
        print("FAIL: expected crunch to raise when no questions could be made")
        return 1
    except ValueError:
        pass
    assert j2.status != "ready", "journey must not be marked ready with no questions"

    print("PASS: crunch skips failed windows/skills, and fails cleanly if nothing works")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
