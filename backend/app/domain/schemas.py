"""Pydantic request/response models for the /api/v1 surface."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

from app.domain.status import RequestStatus


class ProfileOut(BaseModel):
    id: str
    role: str
    display_name: str | None


class HerbOut(BaseModel):
    id: str
    slug: str
    name_he: str
    name_en: str | None


class RequestCreate(BaseModel):
    herb_name_raw: str = Field(min_length=1, max_length=200)
    claim_text: str = Field(min_length=1, max_length=4000)
    is_caregiver: bool = False


class RequestOut(BaseModel):
    id: str
    user_id: str
    herb_id: str | None
    herb_name_raw: str
    claim_text: str
    is_caregiver: bool
    status: RequestStatus
    assigned_researcher_id: str | None
    submitted_at: datetime | None
    created_at: datetime
    updated_at: datetime


class AssignRequest(BaseModel):
    researcher_id: str


class ReviewDecision(BaseModel):
    decision: str = Field(pattern="^(approved|rejected)$")
    final_content: dict[str, Any] | None = None
    researcher_notes: str | None = Field(default=None, max_length=4000)


class PublishedResultOut(BaseModel):
    request_id: str
    body: dict[str, Any]
    published_at: datetime
