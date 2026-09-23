"""Service-role Supabase client for the backend.

This is the ONLY thing in the system that holds SUPABASE_SECRET_KEY.
It bypasses RLS entirely, which is intentional: per D-011, tables like
ai_drafts/researcher_reviews/research_jobs have no RLS policies for any
client role, so the backend is their sole access path, and it enforces its
own authorization (see app/core/security.py role guards) before touching
them.
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import get_settings


@lru_cache
def get_service_client() -> Client:
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_secret_key)
