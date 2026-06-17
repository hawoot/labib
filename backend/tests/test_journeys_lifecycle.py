"""Journey archive (reversible) + hard delete (gone), and debug inspection.

    cd backend && python tests/test_journeys_lifecycle.py
"""
import os
import sys
import tempfile

os.environ["DATABASE_URL"] = "sqlite:///" + tempfile.mkstemp(suffix=".db")[1]
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


def main() -> int:
    with TestClient(app) as c:
        h = {"X-User-Id": c.post("/auth/anonymous").json()["user_id"]}
        jid = c.post("/journeys", headers=h, json={"title": "T", "intent": ""}).json()["id"]

        # Archive hides it from the default list but keeps it under ?archived.
        c.post(f"/journeys/{jid}/archive", headers=h)
        assert c.get("/journeys", headers=h).json() == []
        assert len(c.get("/journeys?archived=true", headers=h).json()) == 1

        # Unarchive brings it back (reversible).
        c.post(f"/journeys/{jid}/unarchive", headers=h)
        assert len(c.get("/journeys", headers=h).json()) == 1

        # Hard delete is permanent.
        c.post(f"/journeys/{jid}/documents/text", headers=h,
               json={"title": "d", "text": "hello world"})
        assert c.delete(f"/journeys/{jid}", headers=h).status_code == 204
        assert c.get(f"/journeys/{jid}", headers=h).status_code == 404

        # Debug surface: stats + searchable tables.
        assert c.get("/debug/stats").json()["counts"]["journeys"] == 0
        users = c.get("/debug/tables/users", params={"q": h["X-User-Id"][:6]}).json()
        assert users["total"] >= 1
        assert c.get("/debug/tables/nope").status_code == 404

    print("PASS: archive reversible, delete permanent, debug reachable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
