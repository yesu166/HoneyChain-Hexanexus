"""Probe every configured Gemini key against the configured model WITHOUT logs.

Reads keys straight from the local backend/.env (git-ignored), makes one
generateContent request per key, and prints ONLY a masked verdict per key:
whether it authenticated, reached the model, the HTTP status, and the classified
error category. The key value itself is never printed, exported or logged.

Usage:
    python scripts/diag_probe_keys.py
"""
from __future__ import annotations

import asyncio
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from app.adapters.ai.gemini import (  # noqa: E402
    CAT_AUTH,
    CAT_MODEL_NOT_FOUND,
    CAT_QUOTA,
    CAT_RATE_LIMIT,
    GeminiProviderPool,
    GoogleGeminiProvider,
)
from app.core.config import get_settings  # noqa: E402


def _load_env_keys(model: str, base_url: str) -> list[GoogleGeminiProvider]:
    """Parse only the GEMINI_API_KEY* entries from backend/.env (never prints)."""
    env_path = os.path.join(PROJECT_ROOT, ".env")
    found: dict[str, str] = {}
    with open(env_path, encoding="utf-8") as fh:
        for line in fh:
            match = re.match(r"^(GEMINI_API_KEY(?:_[23])?)=\"([^\"]+)\"", line.strip())
            if match:
                found[match.group(1)] = match.group(2)
    ordered = [
        found.get("GEMINI_API_KEY"),
        found.get("GEMINI_API_KEY_2"),
        found.get("GEMINI_API_KEY_3"),
    ]
    return [
        GoogleGeminiProvider(api_key=key, model=model, base_url=base_url, max_retries=0)
        for key in ordered
        if key
    ]


def _masked_line(var_name: str, turn) -> str:
    kind = turn.kind or "ok"
    if turn.text or turn.tool_calls:
        return f"{var_name}: VALID | model accessible | HTTP 200"
    if kind == CAT_AUTH:
        return f"{var_name}: INVALID/auth failed | HTTP {_status_from(turn)}"
    if kind == CAT_RATE_LIMIT:
        return (
            f"{var_name}: key authenticates | transient rate-limit (429) | model "
            "reachable but throttled"
        )
    if kind == CAT_QUOTA:
        return f"{var_name}: key authenticates | daily/project quota exceeded (429)"
    if kind in (CAT_MODEL_NOT_FOUND,):
        return f"{var_name}: key authenticates | model NOT FOUND (404) | check GEMINI_MODEL"
    return f"{var_name}: check (kind={kind}) | HTTP {_status_from(turn)}"


def _status_from(turn) -> str:
    match = re.search(r"Gemini API (\d+)", turn.error or "")
    return match.group(1) if match else "?"


async def main() -> None:
    settings = get_settings()
    model = settings.gemini_model
    base_url = settings.google_ai_api_base
    providers = _load_env_keys(model, base_url)
    pool = GeminiProviderPool(providers)
    print(f"model: {model}")
    print(f"configured keys: {len(providers)}")
    for index in range(len(providers)):
        var = ["GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3"][index]
        single = GeminiProviderPool([providers[index]])
        turn = await single.generate(
            system="Reply with OK.",
            contents=[{"role": "user", "parts": [{"text": "Reply OK"}]}],
            tool_declarations=[],
        )
        print(_masked_line(var, turn))


if __name__ == "__main__":
    asyncio.run(main())