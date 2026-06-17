"""Anonymous account bootstrap + code login.

There are no passwords. A new account comes with a short, unguessable **code**;
typing that code on any other browser/device reclaims the same account. The
device stores the returned `user_id` and sends it as `X-User-Id` on every other
request.
"""
import re

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..schemas import AnonymousAuthOut, LoginIn

router = APIRouter(prefix="/auth", tags=["auth"])


def _normalize(code: str) -> str:
    """Accept what the user types (spaces, lowercase, missing dash) and map it
    to the canonical XXXX-XXXX form we store."""
    s = re.sub(r"[^0-9A-Za-z]", "", code).upper()
    return f"{s[:4]}-{s[4:8]}" if len(s) >= 8 else s


@router.post("/anonymous", response_model=AnonymousAuthOut)
def create_anonymous_user(db: Session = Depends(get_db)):
    """Create a fresh anonymous account. Returns the `user_id` to store on the
    device and the human-friendly `code` to show the user so they can get back
    in elsewhere."""
    user = models.User()
    db.add(user)
    db.commit()
    db.refresh(user)
    return AnonymousAuthOut(user_id=user.id, code=user.code)


@router.post("/login", response_model=AnonymousAuthOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    """Reclaim an existing account from its code."""
    user = db.query(models.User).filter_by(code=_normalize(body.code)).first()
    if user is None:
        raise HTTPException(status_code=404, detail="No account with that code.")
    return AnonymousAuthOut(user_id=user.id, code=user.code)
