from supabase import Client

from app.core.supabase_client import get_service_client


def get_client() -> Client:
    return get_service_client()
