"""Business logic for the request lifecycle.

Every function here runs with the service-role client, i.e. past RLS.
Ownership/role checks that RLS would otherwise provide are done explicitly
in each function (and again, redundantly, in the API layer's dependencies)
-- see D-011 / D-015 for why the backend is trusted to do this instead of
leaning on policies for the staff-only tables.
"""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import HTTPException, status
from supabase import Client

from app.core.security import CurrentUser
from app.domain.herb_matching import find_best_match
from app.domain.schemas import RequestCreate, ReviewDecision
from app.domain.status import RequestStatus, assert_valid_transition


def _get_request_or_404(client: Client, request_id: str) -> dict[str, Any]:
    resp = client.table("requests").select("*").eq("id", request_id).maybe_single().execute()
    if not resp.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")
    return resp.data


def _assert_can_view(request_row: dict[str, Any], user: CurrentUser) -> None:
    is_owner = request_row["user_id"] == user.id
    is_staff = user.role in ("researcher", "admin")
    if not (is_owner or is_staff):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your request")


def create_request(client: Client, user: CurrentUser, payload: RequestCreate) -> dict[str, Any]:
    herb_id = None
    herbs_resp = client.table("herbs").select("id, slug, name_he, name_en").eq("is_active", True).execute()
    match = find_best_match(payload.herb_name_raw, herbs_resp.data or [])
    if match:
        herb_id = match["id"]

    insert_resp = (
        client.table("requests")
        .insert(
            {
                "user_id": user.id,
                "herb_id": herb_id,
                "herb_name_raw": payload.herb_name_raw,
                "claim_text": payload.claim_text,
                "is_caregiver": payload.is_caregiver,
                "status": RequestStatus.DRAFT.value,
            }
        )
        .execute()
    )
    return insert_resp.data[0]


def list_requests(
    client: Client,
    user: CurrentUser,
    *,
    status_filter: RequestStatus | None = None,
    assigned_to_me: bool = False,
) -> list[dict[str, Any]]:
    query = client.table("requests").select("*").order("created_at", desc=True)

    if user.role == "user":
        query = query.eq("user_id", user.id)
    elif assigned_to_me:
        query = query.eq("assigned_researcher_id", user.id)

    if status_filter:
        query = query.eq("status", status_filter.value)

    return query.execute().data or []


def get_request(client: Client, user: CurrentUser, request_id: str) -> dict[str, Any]:
    row = _get_request_or_404(client, request_id)
    _assert_can_view(row, user)
    return row


def _transition(client: Client, request_id: str, from_status: RequestStatus, to_status: RequestStatus) -> dict[str, Any]:
    assert_valid_transition(from_status, to_status)
    resp = (
        client.table("requests")
        .update({"status": to_status.value})
        .eq("id", request_id)
        .eq("status", from_status.value)  # optimistic concurrency: no-op if it already moved
        .execute()
    )
    if not resp.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Request is no longer in status '{from_status}' (concurrent update?)",
        )
    return resp.data[0]


def submit_request(client: Client, user: CurrentUser, request_id: str) -> dict[str, Any]:
    row = _get_request_or_404(client, request_id)
    if row["user_id"] != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your request")

    current = RequestStatus(row["status"])
    updated = _transition(client, request_id, current, RequestStatus.SUBMITTED)

    # Enqueue the AI research job. Idempotent: re-submitting the same
    # request (which the state machine won't allow anyway once it has
    # moved on) would collide on this key rather than double-enqueue.
    client.table("research_jobs").insert(
        {
            "request_id": request_id,
            "job_type": "ai_research",
            "idempotency_key": f"ai_research:{request_id}",
            "payload": {"request_id": request_id},
        }
    ).execute()

    return updated


def withdraw_request(client: Client, user: CurrentUser, request_id: str) -> dict[str, Any]:
    row = _get_request_or_404(client, request_id)
    if row["user_id"] != user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your request")

    current = RequestStatus(row["status"])
    return _transition(client, request_id, current, RequestStatus.WITHDRAWN)


def assign_researcher(client: Client, request_id: str, researcher_id: str) -> dict[str, Any]:
    researcher_resp = (
        client.table("profiles").select("id, role").eq("id", researcher_id).maybe_single().execute()
    )
    if not researcher_resp.data or researcher_resp.data["role"] not in ("researcher", "admin"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="researcher_id is not a researcher/admin")

    _get_request_or_404(client, request_id)
    resp = (
        client.table("requests")
        .update({"assigned_researcher_id": researcher_id})
        .eq("id", request_id)
        .execute()
    )
    return resp.data[0]


def decide_request(client: Client, user: CurrentUser, request_id: str, decision: ReviewDecision) -> dict[str, Any]:
    row = _get_request_or_404(client, request_id)
    if user.role != "admin" and row.get("assigned_researcher_id") != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the assigned researcher (or an admin) can decide this request",
        )

    current = RequestStatus(row["status"])
    if current != RequestStatus.RESEARCHER_REVIEW:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Request must be in researcher_review, is '{current}'",
        )

    if decision.decision == "approved" and not decision.final_content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="final_content is required to approve")

    review_resp = (
        client.table("researcher_reviews")
        .insert(
            {
                "request_id": request_id,
                "researcher_id": user.id,
                "decision": decision.decision,
                "final_content": decision.final_content,
                "researcher_notes": decision.researcher_notes,
            }
        )
        .execute()
    )
    review = review_resp.data[0]

    if decision.decision == "rejected":
        return _transition(client, request_id, RequestStatus.RESEARCHER_REVIEW, RequestStatus.REJECTED)

    updated = _transition(client, request_id, RequestStatus.RESEARCHER_REVIEW, RequestStatus.APPROVED)

    client.table("published_results").insert(
        {
            "request_id": request_id,
            "researcher_review_id": review["id"],
            "body": decision.final_content,
            "published_by": user.id,
        }
    ).execute()

    return _transition(client, request_id, RequestStatus.APPROVED, RequestStatus.PUBLISHED)


def get_published_result(client: Client, user: CurrentUser, request_id: str) -> dict[str, Any]:
    row = get_request(client, user, request_id)  # 404s / 403s as appropriate
    if user.role == "user" and row["status"] != RequestStatus.PUBLISHED.value:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No published result yet")

    resp = (
        client.table("published_results").select("*").eq("request_id", request_id).maybe_single().execute()
    )
    if not resp.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No published result yet")
    return resp.data


def retry_failed_request(client: Client, user: CurrentUser, request_id: str) -> dict[str, Any]:
    """Re-queues an ai_failed request (owner or staff may trigger a retry)."""
    row = _get_request_or_404(client, request_id)
    _assert_can_view(row, user)

    current = RequestStatus(row["status"])
    updated = _transition(client, request_id, current, RequestStatus.AI_PROCESSING)

    client.table("research_jobs").insert(
        {
            "request_id": request_id,
            "job_type": "ai_research",
            "idempotency_key": f"ai_research:{request_id}:retry:{uuid.uuid4()}",
            "payload": {"request_id": request_id, "retry": True},
        }
    ).execute()

    return updated
