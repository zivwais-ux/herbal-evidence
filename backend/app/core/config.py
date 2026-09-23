"""App configuration, read from environment variables (see .env.example)."""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: Literal["dev", "production"] = "dev"
    port: int = 8000

    supabase_url: str
    supabase_publishable_key: str
    supabase_secret_key: str
    # Issuer used to validate the `iss` claim, e.g. https://<ref>.supabase.co/auth/v1
    supabase_jwt_issuer: str
    # Legacy HS256 projects sign with a shared secret instead of JWKS.
    # Optional: only needed if this project hasn't been migrated to
    # asymmetric (JWKS) JWT signing. See app/core/security.py.
    supabase_jwt_secret: str | None = None

    frontend_origin: str
    cors_allowed_origins: str = ""

    ai_provider: Literal["openai", "none"] = "none"
    ai_model: str = ""
    ai_api_key: str = ""

    ncbi_api_key: str = ""

    log_level: str = "INFO"

    @property
    def cors_origins(self) -> list[str]:
        origins = [o.strip() for o in self.cors_allowed_origins.split(",") if o.strip()]
        return origins or [self.frontend_origin]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # populated from env/`.env`
