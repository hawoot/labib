"""In-process background worker that runs queued crunch jobs.

Phase 0: a single daemon thread polls the IngestionJob table (the "DB-backed job
table polled by an in-process worker" from the blueprint). Assumes one process;
a real queue (Redis/arq) replaces this later with no API changes.
"""
from __future__ import annotations

import datetime
import logging
import threading

from . import models, push
from .crunch import run_crunch
from .db import SessionLocal

log = logging.getLogger("labib.worker")

_stop = threading.Event()
_thread: threading.Thread | None = None
_reminder_thread: threading.Thread | None = None

# How late a reminder may fire if a tick is delayed (server busy). The per-day
# dedupe (last_sent_on) means this window can never cause a repeat.
_REMINDER_GRACE_MIN = 5


def reset_orphans() -> None:
    """Any job left 'running' at startup was orphaned by a restart → requeue."""
    db = SessionLocal()
    try:
        db.query(models.IngestionJob).filter_by(status="running").update(
            {"status": "queued", "phase": "queued"}
        )
        db.commit()
    finally:
        db.close()


def _claim_next() -> str | None:
    db = SessionLocal()
    try:
        job = (
            db.query(models.IngestionJob)
            .filter_by(status="queued")
            .order_by(models.IngestionJob.created_at)
            .first()
        )
        if job is None:
            return None
        job.status = "running"
        db.commit()
        return job.id
    finally:
        db.close()


def _process(job_id: str) -> None:
    db = SessionLocal()
    try:
        job = db.get(models.IngestionJob, job_id)
        journey = db.get(models.Journey, job.journey_id)
        run_crunch(db, journey, job)
        job.status = "done"
        db.commit()
    except Exception as e:  # noqa: BLE001
        db.rollback()
        job = db.get(models.IngestionJob, job_id)
        if job is not None:
            job.status = "failed"
            job.error = str(e)[:2000]
            db.commit()
        log.exception("crunch job %s failed", job_id)
    finally:
        db.close()


def _loop() -> None:
    reset_orphans()
    while not _stop.is_set():
        job_id = _claim_next()
        if job_id:
            _process(job_id)
        else:
            _stop.wait(2)


# --------------------------------------------------------------------------- #
#  Reminder scheduler: fire each user's recurring practice reminders at their
#  local time, via push. One pass per ~30s; dedupe per local day.
# --------------------------------------------------------------------------- #
def _send_due_reminders() -> None:
    if not push.is_configured():
        return  # no Firebase creds -> nothing to send; skip quietly
    db = SessionLocal()
    try:
        now_utc = datetime.datetime.utcnow()
        schedules = (
            db.query(models.NotificationSchedule).filter_by(enabled=True).all()
        )
        for s in schedules:
            local = now_utc + datetime.timedelta(minutes=s.utc_offset_minutes)
            local_date = local.date().isoformat()
            if s.last_sent_on == local_date:
                continue  # already fired today
            days = s.days or []
            if len(days) != 7 or not days[local.weekday()]:
                continue  # not scheduled for today
            local_minutes = local.hour * 60 + local.minute
            if not (s.minutes <= local_minutes <= s.minutes + _REMINDER_GRACE_MIN):
                continue  # not its time (within the grace window)

            tokens = [
                t.token
                for t in db.query(models.DeviceToken)
                .filter_by(user_id=s.user_id)
                .all()
            ]
            if tokens:
                try:
                    push.send_to_tokens(
                        tokens,
                        title="labib",
                        body="Time for a quick practice 👋",
                        data={"kind": "reminder"},
                    )
                except Exception:  # noqa: BLE001 - never let one user break the loop
                    log.exception("reminder send failed for user %s", s.user_id)
            s.last_sent_on = local_date
            db.commit()
    except Exception:  # noqa: BLE001
        db.rollback()
        log.exception("reminder tick failed")
    finally:
        db.close()


def _reminder_loop() -> None:
    while not _stop.is_set():
        _send_due_reminders()
        _stop.wait(30)


def start_worker() -> None:
    global _thread, _reminder_thread
    _stop.clear()
    if not (_thread and _thread.is_alive()):
        _thread = threading.Thread(target=_loop, name="crunch-worker", daemon=True)
        _thread.start()
    if not (_reminder_thread and _reminder_thread.is_alive()):
        _reminder_thread = threading.Thread(
            target=_reminder_loop, name="reminder-scheduler", daemon=True
        )
        _reminder_thread.start()


def stop_worker() -> None:
    _stop.set()
