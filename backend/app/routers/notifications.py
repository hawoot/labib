"""Push-notification device registration and a manual test trigger.

Flow:
  1. The app obtains an FCM token from Firebase and POSTs it to
     /notifications/register-device. We store it against the current user.
  2. The engine (or the /test endpoint below) looks up a user's tokens and
     asks FCM to deliver a notification to each.

Tokens that FCM reports as stale/unregistered are deleted automatically so we
don't keep trying to reach apps that were uninstalled.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .. import models, push
from ..db import get_db
from ..deps import get_current_user

router = APIRouter(prefix="/notifications", tags=["notifications"])


class RegisterDeviceIn(BaseModel):
    token: str = Field(min_length=1)
    platform: str = "android"


@router.post("/register-device")
def register_device(
    body: RegisterDeviceIn,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Store (or move) this device's FCM token for the current user.

    Idempotent: the token is unique, so re-registering the same token just
    refreshes ownership/timestamp rather than creating duplicates.
    """
    existing = db.query(models.DeviceToken).filter_by(token=body.token).first()
    if existing is not None:
        existing.user_id = user.id
        existing.platform = body.platform
    else:
        db.add(
            models.DeviceToken(
                user_id=user.id, token=body.token, platform=body.platform
            )
        )
    db.commit()
    return {"status": "ok"}


@router.post("/unregister-device")
def unregister_device(
    body: RegisterDeviceIn,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Forget a device token (e.g. the user turned reminders off)."""
    db.query(models.DeviceToken).filter_by(
        token=body.token, user_id=user.id
    ).delete()
    db.commit()
    return {"status": "ok"}


@router.post("/test")
def send_test(
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Send a test push to every device registered for the current user.

    Handy for confirming the whole chain works end-to-end from the phone.
    """
    if not push.is_configured():
        raise HTTPException(
            status_code=503,
            detail="Push isn't configured on the server yet (no Firebase "
            "service-account key). Add FIREBASE_CREDENTIALS_JSON and restart.",
        )
    tokens = [
        t.token
        for t in db.query(models.DeviceToken).filter_by(user_id=user.id).all()
    ]
    if not tokens:
        raise HTTPException(
            status_code=404,
            detail="No devices registered for this account yet. Open the app on "
            "your phone (and allow notifications) first.",
        )
    result = push.send_to_tokens(
        tokens,
        title="labib",
        body="🎉 Push notifications are working. This is a test.",
        data={"kind": "test"},
    )
    # Drop tokens FCM rejected as stale so future sends stay clean.
    if result["invalid_tokens"]:
        db.query(models.DeviceToken).filter(
            models.DeviceToken.token.in_(result["invalid_tokens"])
        ).delete(synchronize_session=False)
        db.commit()
    return {"devices": len(tokens), **result}
