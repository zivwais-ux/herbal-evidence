"""Shared slowapi Limiter instance.

Lives outside main.py so route modules can import it for per-route
@limiter.limit(...) overrides without a circular import on app.main.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])
