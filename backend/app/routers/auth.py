"""Anonymous account bootstrap."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..schemas import AnonymousAuthOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/anonymous", response_model=AnonymousAuthOut)
def create_anonymous_user(db: Session = Depends(get_db)):
    """Create a fresh anonymous account. Store the returned user_id on the
    device and send it as the `X-User-Id` header on every other request."""
    user = models.User()
    db.add(user)
    db.commit()
    db.refresh(user)
    return AnonymousAuthOut(user_id=user.id)
