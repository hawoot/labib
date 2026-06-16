"""Code-login: a new account gets a code; that code reclaims the account.

    cd backend && python tests/test_auth_code.py
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
        created = c.post("/auth/anonymous").json()
        code = created["code"]
        assert "-" in code and len(code) == 9, code

        # The same code, typed sloppily (lowercase, spaces instead of dash),
        # still reclaims the same account.
        messy = code.lower().replace("-", "  ")
        r = c.post("/auth/login", json={"code": messy})
        assert r.status_code == 200, r.status_code
        assert r.json()["user_id"] == created["user_id"]

        # A code that doesn't exist is a clean 404, not a new account.
        assert c.post("/auth/login", json={"code": "ZZZZ-ZZZZ"}).status_code == 404

    print(f"PASS: code {code} round-trips, unknown codes 404")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
