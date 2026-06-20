"""Pydantic request/response shapes (the API contract)."""
from __future__ import annotations

import datetime

from pydantic import BaseModel, ConfigDict, Field


class AnonymousAuthOut(BaseModel):
    user_id: str
    code: str


class LoginIn(BaseModel):
    code: str


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
    archived_at: datetime.datetime | None = None
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


# --- Drilling ---
class SessionItem(BaseModel):
    question_id: str
    skill_id: str
    skill_name: str
    mode: str
    prompt: str


class SessionOut(BaseModel):
    journey_id: str
    items: list[SessionItem]


class AttemptCreate(BaseModel):
    question_id: str
    # Either a typed/spoken answer, an image (base64), or both.
    answer: str = ""
    image: str | None = None  # base64-encoded image bytes
    image_media_type: str = "image/jpeg"


class AttemptResultOut(BaseModel):
    graded: bool = True
    score: float
    correct: bool
    feedback: str
    answer: str | None
    explanation: str | None
    mastery: float | None


class ChatMessage(BaseModel):
    role: str  # 'user' | 'assistant'
    text: str = ""
    image: str | None = None  # base64-encoded image bytes
    image_media_type: str = "image/jpeg"


class ChatIn(BaseModel):
    messages: list[ChatMessage]


class ChatOut(BaseModel):
    reply: str
    solved: bool
    score: float


class AssistIn(BaseModel):
    # 'hint'   -> how to approach THIS problem, without giving the answer
    # 'basics' -> step back and explain the prerequisite basics
    kind: str = "hint"


class AssistOut(BaseModel):
    text: str


class RevealOut(BaseModel):
    answer: str | None
    explanation: str | None


class ProgressItem(BaseModel):
    skill_id: str
    name: str
    mastery: float
    reps: int
    due: bool


class ProgressOut(BaseModel):
    journey_id: str
    skill_count: int
    mastered: int
    due: int
    items: list[ProgressItem]
