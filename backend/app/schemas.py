"""Pydantic request/response shapes (the API contract)."""
from __future__ import annotations

import datetime

from pydantic import BaseModel, ConfigDict, Field


class AnonymousAuthOut(BaseModel):
    user_id: str


class JourneyCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    intent: str = ""


class JourneyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    owner_id: str | None
    title: str
    intent: str
    status: str
    curriculum_version: int
    created_at: datetime.datetime


class DocumentTextCreate(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    text: str = Field(min_length=1)


class DocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    journey_id: str
    kind: str
    title: str
    mime: str | None
    status: str
    created_at: datetime.datetime


class IngestionJobOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    journey_id: str
    status: str
    phase: str
    progress: int
    error: str | None
    curriculum_version: int
    created_at: datetime.datetime
    updated_at: datetime.datetime


class QuestionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    mode: str
    prompt: str
    answer: str | None
    explanation: str | None


class SkillOut(BaseModel):
    id: str
    unit_id: str | None
    name: str
    description: str
    questions: list[QuestionOut]


class CurriculumOut(BaseModel):
    journey_id: str
    curriculum_version: int
    skill_count: int
    question_count: int
    skills: list[SkillOut]
