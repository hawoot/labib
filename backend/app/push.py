"""Sending push notifications via Firebase Cloud Messaging (FCM).

This is the SEND side. The phone gets a delivery token from Firebase and hands
it to us (see routers/notifications.py); here we ask Google's FCM servers to
deliver a message to one or more of those tokens.

Sending requires *admin* credentials — a Firebase **service account** private
key — which is a secret (unlike the client `google-services.json` that ships in
the app). Provide it one of two ways via env / .env:

  * FIREBASE_CREDENTIALS_JSON  – the whole service-account JSON as a string, or
  * FIREBASE_CREDENTIALS_FILE  – a path to the .json file on disk.

If neither is set, push is treated as *not configured*: the endpoints stay up
and return a clear message instead of crashing, so the rest of the app is
unaffected in environments without credentials (e.g. CI, local dev).
"""
from __future__ import annotations

import json
import threading

from .config import get_settings

_lock = threading.Lock()
_app = None  # firebase_admin app, initialised lazily on first send
_init_error: str | None = None


class PushNotConfigured(RuntimeError):
    """Raised when a send is attempted without Firebase admin credentials."""


def _get_app():
    """Initialise (once) and return the firebase_admin app, or raise
    PushNotConfigured if no credentials are available."""
    global _app, _init_error
    if _app is not None:
        return _app
    with _lock:
        if _app is not None:
            return _app
        s = get_settings()
        if not (s.firebase_credentials_json or s.firebase_credentials_file):
            raise PushNotConfigured(
                "Push is not configured: set FIREBASE_CREDENTIALS_JSON (or "
                "FIREBASE_CREDENTIALS_FILE) to a Firebase service-account key."
            )
        try:
            import firebase_admin
            from firebase_admin import credentials

            if s.firebase_credentials_json:
                cred = credentials.Certificate(json.loads(s.firebase_credentials_json))
            else:
                cred = credentials.Certificate(s.firebase_credentials_file)
            _app = firebase_admin.initialize_app(cred)
            return _app
        except PushNotConfigured:
            raise
        except Exception as e:  # bad key / parse error — surface it clearly
            _init_error = str(e)
            raise PushNotConfigured(f"Firebase admin init failed: {e}") from e


def is_configured() -> bool:
    s = get_settings()
    return bool(s.firebase_credentials_json or s.firebase_credentials_file)


def send_to_tokens(
    tokens: list[str], title: str, body: str, data: dict | None = None
) -> dict:
    """Deliver one notification to many device tokens.

    Returns {sent, failed, invalid_tokens}. `invalid_tokens` are ones FCM
    rejected as unregistered/stale — the caller should delete these so we stop
    trying to reach uninstalled apps.
    """
    if not tokens:
        return {"sent": 0, "failed": 0, "invalid_tokens": []}

    app = _get_app()  # raises PushNotConfigured if creds missing
    from firebase_admin import messaging

    sent = 0
    failed = 0
    invalid: list[str] = []
    for token in tokens:
        msg = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            android=messaging.AndroidConfig(priority="high"),
        )
        try:
            messaging.send(msg, app=app)
            sent += 1
        except messaging.UnregisteredError:
            failed += 1
            invalid.append(token)
        except Exception:
            failed += 1
    return {"sent": sent, "failed": failed, "invalid_tokens": invalid}
