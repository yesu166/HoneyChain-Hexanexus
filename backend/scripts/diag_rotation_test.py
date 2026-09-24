"""Rotation + shared-quota diagnostic (masked, no keys ever printed).

1) Sends rapid requests on the PRIMARY key only until it starts returning 429
   (documents its free-tier limit, up to 25 attempts, breaks early once
   throttled).
2) Immediately sends ONE request through the 3-key pool. If the pool still
   succeeds while the primary is throttled, the keys carry separate quotas
   (consistent with separate projects). If the pool is also denied, the quota
   is shared.

This is a bounded, one-time diagnostic the operator requested — NOT used as an
evasion tactic by the running app.
"""
from __future__ import annotations

import asyncio
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

from app.adapters.ai.gemini import (  # noqa: E402
    GeminiProviderPool,
    GoogleGeminiProvider,
)
from app.core.config import get_settings  # noqa: E402

MAX_BURST = 25
THROTTLE_THRESHOLD = 2  # two consecutive 429s means we are inside the throttle


def _load_keys() -> dict[str, str]:
    env_path = os.path.join(PROJECT_ROOT, ".env")
    found: dict[str, str] = {}
    with open(env_path, encoding="utf-8") as fh:
        for line in fh:
            match = re.match(r"^(GEMINI_API_KEY(?:_[23])?)=\"([^\"]+)\"", line.strip())
            if match:
                found[match.group(1)] = match.group(2)
    return found


async def main() -> None:
    settings = get_settings()
    model = settings.gemini_model
    base_url = settings.google_ai_api_base
    keys = _load_keys()
    primary = keys.get("GEMINI_API_KEY", "")

    provider = GoogleGeminiProvider(
        api_key=primary, model=model, base_url=base_url, max_retries=0
    )
    content = [{"role": "user", "parts": [{"text": "Reply OK"}]}]
    ok = 0
    throttled = 0
    consecutive_429 = 0
    bursts_taken = 0
    for _ in range(MAX_BURST):
        turn = await provider.generate(system="Reply OK.", contents=content, tool_declarations=[])
        bursts_taken += 1
        if turn.kind == "rate_limit" or turn.kind == "quota":
            throttled += 1
            consecutive_429 += 1
            if consecutive_429 >= THROTTLE_THRESHOLD:
                break
        elif turn.text:
            ok += 1
            consecutive_429 = 0
        else:
            consecutive_429 = 0
    print(
        f"primary burst: attempts={bursts_taken} ok={ok} throttled={throttled} "
        f"(free-tier per-minute limit reached => rate_limit)"
    )

    pool = GeminiProviderPool(
        [
            GoogleGeminiProvider(api_key=keys.get(n, ""), model=model, base_url=base_url, max_retries=0)
            for n in ("GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3")
            if keys.get(n)
        ]
    )
    turn = await pool.generate(system="Reply OK.", contents=content, tool_declarations=[])
    if turn.text:
        print("pool right after primary throttle: SUCCESS (separate quotas / rotation works)")
    else:
        print(f"pool right after primary throttle: {turn.kind} (quota appears SHARED)")


if __name__ == "__main__":
    asyncio.run(main())