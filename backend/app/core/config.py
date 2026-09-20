"""HoneyChain backend configuration.

Secrets come from environment variables only. No credentials are committed.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

# Load backend/.env (gitignored, real secrets live there) before reading env.
_BACKEND_DIR = Path(__file__).resolve().parents[2]
load_dotenv(_BACKEND_DIR / ".env")


def _split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


class Settings:
    """Runtime configuration read from the environment."""

    def __init__(self) -> None:
        self.api_env: str = os.getenv("API_ENV", "development")
        self.api_version: str = "1.0.0"

        # Supabase PostgreSQL (system of record).
        self.supabase_url: str = os.getenv("SUPABASE_URL", "")
        self.supabase_service_role_key: str = os.getenv(
            "SUPABASE_SERVICE_ROLE_KEY", ""
        )
        self.supabase_anon_key: str = os.getenv("SUPABASE_ANON_KEY", "")

        # Auth.
        self.jwt_secret: str = os.getenv("JWT_SECRET", "")
        self.jwt_algorithm: str = os.getenv("JWT_ALGORITHM", "HS256")
        self.access_token_expire_minutes: int = int(
            os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080")
        )

        # CORS.
        self.cors_origins: list[str] = _split_csv(os.getenv("CORS_ORIGINS", ""))

        # Blockchain + AI adapters.
        self.blockchain_adapter: str = os.getenv(
            "BLOCKCHAIN_ADAPTER", "fabric" if self.is_production else "local"
        )
        self.blockchain_rpc_url: str = os.getenv("BLOCKCHAIN_RPC_URL", "")
        self.blockchain_chain_id: str = os.getenv("BLOCKCHAIN_CHAIN_ID", "")
        self.blockchain_contract: str = os.getenv("BLOCKCHAIN_CONTRACT", "")
        self.blockchain_private_key: str = os.getenv("BLOCKCHAIN_PRIVATE_KEY", "")
        self.fabric_channel: str = os.getenv("FABRIC_CHANNEL", "")
        self.fabric_chaincode: str = os.getenv("FABRIC_CHAINCODE", "")
        self.fabric_gateway_url: str = os.getenv("FABRIC_GATEWAY_URL", "")
        self.ai_adapter: str = os.getenv("AI_ADAPTER", "risk_engine")

        # Public passport endpoint rate limit (requests per minute per IP).
        self.passport_rate_limit_per_minute: int = int(
            os.getenv("PASSPORT_RATE_LIMIT_PER_MINUTE", "60")
        )

    @property
    def is_production(self) -> bool:
        return self.api_env.lower() == "production"

    def require_jwt_secret(self) -> str:
        """Development falls back to a non-secret default so local runs work;
        production must supply a real secret or the service refuses to start."""
        if self.jwt_secret:
            return self.jwt_secret
        if self.is_production:
            raise RuntimeError(
                "JWT_SECRET must be set in production (refusing to start)."
            )
        return "honeychain-local-dev-secret-do-not-use-in-production"


@lru_cache
def get_settings() -> Settings:
    return Settings()