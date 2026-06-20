"""Shared FastAPI dependencies."""
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from . import models
from .db import get_db


def get_current_user(
    x_user_id: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> models.User:
    """Anonymous auth (Phase 0): the client sends its user id as `X-User-Id`.

    Get one from POST /auth/anonymous. Real provider-backed auth comes later.
    """
    if not x_user_id:
        raise HTTPException(
            status_code=401,
            detail="Missing X-User-Id header. Call POST /auth/anonymous first.",
        )
    user = db.get(models.User, x_user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Unknown user id.")
    return user
