from fastapi import APIRouter, Depends, Query, Request
from supabase import Client

from app.api.deps import get_client
from app.core.rate_limit import limiter
from app.core.security import CurrentUser, get_current_user, require_admin, require_staff
from app.domain.schemas import (
    AssignRequest,
    PublishedResultOut,
    RequestCreate,
    RequestOut,
    ReviewDecision,
)
from app.domain.status import RequestStatus
from app.services import requests_service

router = APIRouter(prefix="/requests", tags=["requests"])


@router.post("", response_model=RequestOut, status_code=201)
@limiter.limit("10/minute")
async def create_request(
    request: Request,
    payload: RequestCreate,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.create_request(client, user, payload)


@router.get("", response_model=list[RequestOut])
async def list_my_requests(
    status_filter: RequestStatus | None = Query(default=None, alias="status"),
    assigned_to_me: bool = Query(default=False),
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> list[RequestOut]:
    return requests_service.list_requests(
        client, user, status_filter=status_filter, assigned_to_me=assigned_to_me
    )


@router.get("/{request_id}", response_model=RequestOut)
async def get_request(
    request_id: str,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.get_request(client, user, request_id)


@router.post("/{request_id}/submit", response_model=RequestOut)
async def submit_request(
    request_id: str,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.submit_request(client, user, request_id)


@router.post("/{request_id}/withdraw", response_model=RequestOut)
async def withdraw_request(
    request_id: str,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.withdraw_request(client, user, request_id)


@router.post("/{request_id}/retry", response_model=RequestOut)
async def retry_request(
    request_id: str,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.retry_failed_request(client, user, request_id)


@router.post("/{request_id}/assign", response_model=RequestOut, dependencies=[Depends(require_admin)])
async def assign_request(
    request_id: str,
    payload: AssignRequest,
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.assign_researcher(client, request_id, payload.researcher_id)


@router.post("/{request_id}/decision", response_model=RequestOut, dependencies=[Depends(require_staff)])
async def decide_request(
    request_id: str,
    payload: ReviewDecision,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> RequestOut:
    return requests_service.decide_request(client, user, request_id, payload)


@router.get("/{request_id}/result", response_model=PublishedResultOut)
async def get_result(
    request_id: str,
    user: CurrentUser = Depends(get_current_user),
    client: Client = Depends(get_client),
) -> PublishedResultOut:
    return requests_service.get_published_result(client, user, request_id)
