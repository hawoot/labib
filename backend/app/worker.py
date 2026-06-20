"""In-process background worker that runs queued crunch jobs.

Phase 0: a single daemon thread polls the IngestionJob table (the "DB-backed job
table polled by an in-process worker" from the blueprint). Assumes one process;
a real queue (Redis/arq) replaces this later with no API changes.
"""
from __future__ import annotations

import logging
import threading

from . import models
from .crunch import run_crunch
from .db import SessionLocal

log = logging.getLogger("labib.worker")

_stop = threading.Event()
_thread: threading.Thread | None = None


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


def start_worker() -> None:
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name="crunch-worker", daemon=True)
    _thread.start()


def stop_worker() -> None:
    _stop.set()
