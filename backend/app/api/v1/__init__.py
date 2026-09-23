from fastapi import APIRouter

from app.api.v1.herbs import router as herbs_router
from app.api.v1.me import router as me_router
from app.api.v1.requests import router as requests_router

router = APIRouter(prefix="/api/v1")
router.include_router(me_router)
router.include_router(herbs_router)
router.include_router(requests_router)
