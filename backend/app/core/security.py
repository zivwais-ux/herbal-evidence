"""JWT validation and role-based access guards.

D-004: the backend validates Supabase JWTs itself (iss/aud/exp) rather than
trusting RLS alone. New Supabase projects (this one included) sign JWTs
asymmetrically and publish a JWKS document; we verify against that. A
SUPABASE_JWT_SECRET can be set to fall back to legacy HS256 verification
for projects that haven't migrated, but JWKS is the default path.
"""

from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.core.config import Settings, get_settings
from app.core.supabase_client import get_service_client

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class CurrentUser:
    id: str
    role: str
    display_name: str | None


@lru_cache
def _jwk_client(jwks_url: str) -> PyJWKClient:
    return PyJWKClient(jwks_url, cache_keys=True)


def _decode_token(token: str, settings: Settings) -> dict:
    jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"

    try:
        signing_key = _jwk_client(jwks_url).get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256", "RS256"],
            issuer=settings.supabase_jwt_issuer,
            audience="authenticated",
        )
    except jwt.PyJWKClientError:
        # This project isn't on asymmetric signing (no JWKS published, or
        # unreachable). Fall back to the legacy HS256 shared secret if one
        # is configured; otherwise this is a hard failure.
        if not settings.supabase_jwt_secret:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token could not be verified (no JWKS and no SUPABASE_JWT_SECRET configured)",
            )
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            issuer=settings.supabase_jwt_issuer,
            audience="authenticated",
        )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings: Settings = Depends(get_settings),
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        claims = _decode_token(credentials.credentials, settings)
    except HTTPException:
        raise
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Invalid token: {exc}")

    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing sub claim")

    # The role/display_name live in our own profiles table, not the JWT
    # (the JWT only proves *who*; our DB says *what they're allowed to do*).
    client = get_service_client()
    resp = (
        client.table("profiles")
        .select("id, role, display_name")
        .eq("id", user_id)
        .maybe_single()
        .execute()
    )
    profile = resp.data
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No profile found for this user",
        )

    return CurrentUser(id=profile["id"], role=profile["role"], display_name=profile.get("display_name"))


def require_role(*allowed_roles: str):
    """Dependency factory: 403s unless the caller's role is one of allowed_roles."""

    async def _guard(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires role in {allowed_roles}, caller has '{user.role}'",
            )
        return user

    return _guard


# Convenience guards for the common cases.
require_staff = require_role("researcher", "admin")
require_admin = require_role("admin")
