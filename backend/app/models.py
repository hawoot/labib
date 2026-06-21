"""Database models.

Milestone 2 covers the start of the CONTENT domain:
  User     - anonymous account (device-bootstrapped); owns private content.
  Journey  - the core thing a user creates (was "Program"/"Learning"). Holds an
             `intent` describing HOW to crunch/run it. owner_id NULL = shared.
  Document - material added to a Journey: pasted text, an uploaded file, or a URL.

Later milestones add Chunk, Unit, Skill, Question, IngestionJob and the personal
engine tables (Enrollment, SkillState, Attempt, ...).
"""
from __future__ import annotations

import datetime
import hashlib
import re
import secrets
import uuid

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


# Human-friendly login code: the only thing a user needs to reclaim their
# account on another browser/device. No password — just an unguessable code.
# Alphabet drops easily-confused characters (0/O, 1/I/L) so it's easy to read
# off a screen and retype.
_CODE_CHARS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def _login_code() -> str:
    raw = "".join(secrets.choice(_CODE_CHARS) for _ in range(8))
    return f"{raw[:4]}-{raw[4:]}"


def content_key(name: str) -> str:
    """Stable hash of a skill's *meaning* (normalized name).

    Used to match skills across re-crunches so progress can carry over later.
    Phase 0 uses the normalized name only; an embedding signature can be mixed
    in later without changing callers.
    """
    norm = re.sub(r"\s+", " ", name.strip().lower())
    return hashlib.sha256(norm.encode()).hexdigest()


def _now_col() -> Mapped[datetime.datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    # The code the user types to log in on another device. Unique, no password.
    code: Mapped[str] = mapped_column(
        String(16), unique=True, index=True, default=_login_code
    )
    created_at: Mapped[datetime.datetime] = _now_col()

    journeys: Mapped[list["Journey"]] = relationship(back_populates="owner")


class Journey(Base):
    __tablename__ = "journeys"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    # NULL = part of the shared library; set = private to that user.
    owner_id: Mapped[str | None] = mapped_column(
        String(32), ForeignKey("users.id"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    # Free text: how to crunch/run this ("Socratic novel", "A-level exam prep"...).
    intent: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(32), default="new")
    curriculum_version: Mapped[int] = mapped_column(Integer, default=1)
    # Soft delete: set = hidden from the normal list but data kept (reversible).
    archived_at: Mapped[datetime.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime.datetime] = _now_col()

    owner: Mapped["User | None"] = relationship(back_populates="journeys")
    documents: Mapped[list["Document"]] = relationship(
        back_populates="journey", cascade="all, delete-orphan"
    )


class Document(Base):
    __tablename__ = "documents"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    owner_id: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)

    kind: Mapped[str] = mapped_column(String(16))  # file | text | url
    title: Mapped[str] = mapped_column(String(300))
    mime: Mapped[str | None] = mapped_column(String(100), nullable=True)

    # For kind=file: pointer into object storage. For text/url: inline content.
    storage_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_ref: Mapped[str | None] = mapped_column(Text, nullable=True)

    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    status: Mapped[str] = mapped_column(String(16), default="uploaded")
    created_at: Mapped[datetime.datetime] = _now_col()

    journey: Mapped["Journey"] = relationship(back_populates="documents")


# --------------------------------------------------------------------------- #
#  Crunch outputs: Chunk -> (Unit tree / Skill) -> Question
#  Generated rows are stamped with the Journey's curriculum_version so a
#  re-crunch can supersede them (version bump) without hard-deleting history.
# --------------------------------------------------------------------------- #
class Chunk(Base):
    __tablename__ = "chunks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    document_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("documents.id"), index=True
    )
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    ordinal: Mapped[int] = mapped_column(Integer)  # order within the document
    text: Mapped[str] = mapped_column(Text)
    location: Mapped[str | None] = mapped_column(String(64), nullable=True)  # e.g. "p.12"
    created_at: Mapped[datetime.datetime] = _now_col()


class Unit(Base):
    __tablename__ = "units"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    parent_id: Mapped[str | None] = mapped_column(
        String(32), ForeignKey("units.id"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(300))
    ordinal: Mapped[int] = mapped_column(Integer, default=0)
    source: Mapped[str] = mapped_column(String(16), default="generated")  # generated|manual
    curriculum_version: Mapped[int] = mapped_column(Integer, default=1, index=True)
    created_at: Mapped[datetime.datetime] = _now_col()


class Skill(Base):
    __tablename__ = "skills"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    unit_id: Mapped[str | None] = mapped_column(
        String(32), ForeignKey("units.id"), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(300))
    description: Mapped[str] = mapped_column(Text, default="")
    content_key: Mapped[str] = mapped_column(String(64), index=True)
    provenance: Mapped[list] = mapped_column(JSON, default=list)  # source chunk ids
    ordinal: Mapped[int] = mapped_column(Integer, default=0)
    curriculum_version: Mapped[int] = mapped_column(Integer, default=1, index=True)
    created_at: Mapped[datetime.datetime] = _now_col()


class Question(Base):
    __tablename__ = "questions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    skill_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("skills.id"), index=True
    )
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    # on_the_go | short_drill | problem | discuss
    mode: Mapped[str] = mapped_column(String(16), index=True)
    prompt: Mapped[str] = mapped_column(Text)
    answer: Mapped[str | None] = mapped_column(Text, nullable=True)
    explanation: Mapped[str | None] = mapped_column(Text, nullable=True)
    provenance: Mapped[list] = mapped_column(JSON, default=list)
    curriculum_version: Mapped[int] = mapped_column(Integer, default=1, index=True)
    created_at: Mapped[datetime.datetime] = _now_col()


class IngestionJob(Base):
    __tablename__ = "ingestion_jobs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    status: Mapped[str] = mapped_column(String(16), default="queued", index=True)  # queued|running|done|failed
    phase: Mapped[str] = mapped_column(String(20), default="queued")
    progress: Mapped[int] = mapped_column(Integer, default=0)  # 0..100
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    tokens_used: Mapped[int] = mapped_column(Integer, default=0)
    curriculum_version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime.datetime] = _now_col()
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


# --------------------------------------------------------------------------- #
#  PERSONAL domain: a user's practice state (the drilling engine).
# --------------------------------------------------------------------------- #
class Enrollment(Base):
    __tablename__ = "enrollments"
    __table_args__ = (UniqueConstraint("user_id", "journey_id"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    created_at: Mapped[datetime.datetime] = _now_col()


class SkillState(Base):
    """One per (user, skill): mastery + spaced-repetition schedule."""

    __tablename__ = "skill_states"
    __table_args__ = (UniqueConstraint("user_id", "skill_id"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    journey_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("journeys.id"), index=True
    )
    skill_id: Mapped[str] = mapped_column(String(32), ForeignKey("skills.id"), index=True)

    mastery: Mapped[float] = mapped_column(Float, default=0.0)  # 0..1 (EMA)
    reps: Mapped[int] = mapped_column(Integer, default=0)
    interval_days: Mapped[float] = mapped_column(Float, default=0.0)
    due_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), index=True
    )
    last_reviewed: Mapped[datetime.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class Attempt(Base):
    __tablename__ = "attempts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    journey_id: Mapped[str] = mapped_column(String(32), ForeignKey("journeys.id"))
    skill_id: Mapped[str] = mapped_column(String(32), ForeignKey("skills.id"), index=True)
    question_id: Mapped[str] = mapped_column(String(32), ForeignKey("questions.id"))

    user_answer: Mapped[str] = mapped_column(Text)
    score: Mapped[float] = mapped_column(Float, default=0.0)  # 0..1
    correct: Mapped[bool] = mapped_column(Boolean, default=False)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime.datetime] = _now_col()


class DeviceToken(Base):
    """A phone that has opted in to push notifications.

    `token` is the FCM registration token the app obtains from Firebase — the
    "delivery address" for one install. It's unique: the same token can only
    belong to one user, so if a device is re-used by another account we move it
    (the upsert in the register endpoint). Push is sent by looking up all of a
    user's tokens and asking FCM to deliver to each.
    """

    __tablename__ = "device_tokens"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    token: Mapped[str] = mapped_column(Text, unique=True, index=True)
    platform: Mapped[str] = mapped_column(String(16), default="android")  # android|ios|web
    created_at: Mapped[datetime.datetime] = _now_col()
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
