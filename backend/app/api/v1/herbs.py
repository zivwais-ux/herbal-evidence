from fastapi import APIRouter, Depends
from supabase import Client

from app.api.deps import get_client
from app.domain.schemas import HerbOut

router = APIRouter(tags=["herbs"])


@router.get("/herbs", response_model=list[HerbOut])
async def list_herbs(client: Client = Depends(get_client)) -> list[HerbOut]:
    # Public catalog (mirrors the `herbs_select_all` RLS policy for anon);
    # no auth required so the submission form can autocomplete pre-signup.
    resp = (
        client.table("herbs")
        .select("id, slug, name_he, name_en")
        .eq("is_active", True)
        .order("name_he")
        .execute()
    )
    return resp.data or []
