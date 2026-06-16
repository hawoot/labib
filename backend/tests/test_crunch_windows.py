"""Regression test for the crunch's document coverage.

The bug: the structure pass only ever saw the first 24 chunks (~30 pages), so
anything later in a document (e.g. the Python/prefixes sections after C++, or
most of a book) was silently dropped. This test feeds a document that spans
three windows and asserts a skill is produced from EACH window — not just the
first.

Runs with a fake LLM and a throwaway SQLite DB, so no API key / Postgres needed:

    cd backend && python tests/test_crunch_windows.py
"""
import os
import re
import sys
import tempfile

# Point the app at a throwaway SQLite DB *before* importing anything that builds
# the engine at import time.
os.environ["DATABASE_URL"] = "sqlite:///" + tempfile.mkstemp(suffix=".db")[1]
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import crunch, models  # noqa: E402
from app.db import Base, SessionLocal, engine  # noqa: E402

# 50 paragraphs, each big enough to become its own ~1500-char chunk. Each starts
# with a unique CHUNK<n> marker so we can tell which window it landed in.
PARAS = [f"CHUNK{i} " + ("lorem ipsum " * 120) for i in range(50)]
DOC_TEXT = "\n\n".join(PARAS)


def _fake_complete_json(messages, **_kw):
    system = " ".join(m["content"] for m in messages if m["role"] == "system")
    user = " ".join(m["content"] for m in messages if m["role"] == "user")
    if "curriculum designer" in system:
        # Structure call: name a skill after this window's first chunk marker.
        marker = re.search(r"\[0\] (CHUNK\d+)", user).group(1)
        return {
            "units": [
                {
                    "title": f"Unit {marker}",
                    "skills": [
                        {"name": f"Skill {marker}", "description": "d",
                         "source_chunks": [0]}
                    ],
                }
            ]
        }
    return {"questions": []}  # question call: keep the test about structure only


def main() -> int:
    crunch.parse_document = lambda _doc: DOC_TEXT
    crunch.complete_json = _fake_complete_json

    Base.metadata.create_all(engine)
    db = SessionLocal()
    journey = models.Journey(title="t", intent="")
    db.add(journey)
    db.flush()
    db.add(models.Document(journey_id=journey.id, kind="text", title="d"))
    job = models.IngestionJob(journey_id=journey.id)
    db.add(job)
    db.commit()

    crunch.run_crunch(db, journey, job)

    skills = db.query(models.Skill).filter_by(journey_id=journey.id).all()
    starts = sorted(int(re.search(r"CHUNK(\d+)", s.name).group(1)) for s in skills)

    # 50 chunks / window of 24 -> 3 windows, starting at global chunks 0, 24, 48.
    assert starts == [0, 24, 48], f"expected windows 0/24/48, got {starts}"
    assert job.progress == 100 and job.phase == "done"
    print(f"PASS: every window produced a skill (window starts: {starts})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
