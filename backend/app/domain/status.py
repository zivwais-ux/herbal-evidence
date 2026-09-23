"""Request status state machine.

This mirrors `enforce_request_status_transition()` in
supabase/migrations/20260923060300_requests.sql exactly. The DB trigger is
the actual enforcement backstop (it fires no matter who/what issues the
UPDATE); this copy lets the API reject an invalid transition with a clean
422 instead of surfacing a raw Postgres exception, and lets other backend
code (e.g. the future Phase 3 job consumer) reason about the machine
without a DB round-trip. If you change one, change the other.
"""

from enum import StrEnum


class RequestStatus(StrEnum):
    DRAFT = "draft"
    SUBMITTED = "submitted"
    AI_PROCESSING = "ai_processing"
    AI_FAILED = "ai_failed"
    RESEARCHER_REVIEW = "researcher_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    PUBLISHED = "published"
    WITHDRAWN = "withdrawn"


ALLOWED_TRANSITIONS: dict[RequestStatus, frozenset[RequestStatus]] = {
    RequestStatus.DRAFT: frozenset({RequestStatus.SUBMITTED, RequestStatus.WITHDRAWN}),
    RequestStatus.SUBMITTED: frozenset({RequestStatus.AI_PROCESSING, RequestStatus.WITHDRAWN}),
    RequestStatus.AI_PROCESSING: frozenset({RequestStatus.RESEARCHER_REVIEW, RequestStatus.AI_FAILED}),
    RequestStatus.AI_FAILED: frozenset({RequestStatus.AI_PROCESSING, RequestStatus.RESEARCHER_REVIEW}),
    RequestStatus.RESEARCHER_REVIEW: frozenset({RequestStatus.APPROVED, RequestStatus.REJECTED}),
    RequestStatus.APPROVED: frozenset({RequestStatus.PUBLISHED}),
    RequestStatus.REJECTED: frozenset(),
    RequestStatus.PUBLISHED: frozenset(),
    RequestStatus.WITHDRAWN: frozenset(),
}


class InvalidTransitionError(ValueError):
    def __init__(self, from_status: RequestStatus, to_status: RequestStatus):
        self.from_status = from_status
        self.to_status = to_status
        super().__init__(f"invalid request status transition: {from_status} -> {to_status}")


def assert_valid_transition(from_status: RequestStatus, to_status: RequestStatus) -> None:
    if to_status not in ALLOWED_TRANSITIONS[from_status]:
        raise InvalidTransitionError(from_status, to_status)
