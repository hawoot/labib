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
import uuid

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


def _now_col() -> Mapped[datetime.datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
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
