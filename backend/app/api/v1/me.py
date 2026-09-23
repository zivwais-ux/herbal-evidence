from fastapi import APIRouter, Depends

from app.core.security import CurrentUser, get_current_user
from app.domain.schemas import ProfileOut

router = APIRouter(tags=["me"])


@router.get("/me", response_model=ProfileOut)
async def read_me(user: CurrentUser = Depends(get_current_user)) -> ProfileOut:
    return ProfileOut(id=user.id, role=user.role, display_name=user.display_name)
