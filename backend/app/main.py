"""labib API — entry point.

Milestone 1 (the "walking skeleton"): prove the server runs, can reach the
database, and (optionally) can reach the configured AI provider.
"""
from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from .config import get_settings
from .db import get_db

app = FastAPI(title="labib API", version="0.1.0")


@app.get("/")
def root():
    return {"name": "labib API", "status": "ok", "version": app.version}


@app.get("/health")
def health(db: Session = Depends(get_db)):
    """Liveness + database connectivity."""
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "ok"}


@app.get("/health/llm")
def health_llm():
    """Optional: confirm the configured AI provider/key actually works."""
    s = get_settings()
    if not s.llm_api_key:
        return {"status": "skipped", "reason": "no LLM_API_KEY set in .env"}
    try:
        from .llm import get_llm

        reply = get_llm(s).complete(
            [{"role": "user", "content": "Reply with the single word: pong"}],
            max_tokens=10,
        )
    except Exception as e:  # surface the real error to help debugging
        raise HTTPException(status_code=502, detail=f"LLM call failed: {e}")
    return {
        "status": "ok",
        "provider": s.llm_provider,
        "model": s.llm_model,
        "reply": reply.strip(),
    }
