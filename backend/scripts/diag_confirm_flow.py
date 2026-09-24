"""Diagnose the turn-1 'technical problem' on the create-hive confirmation flow.

Replays exactly what ai_chat_service does:
  call 1: generate (model may call create_hive without confirmed)
  -> if tool call: run execute_ai_tool -> needs_confirmation
  call 2: generate with the functionResponse appended
Prints the provider's error/response so we can see why turn 1 failed.
"""
from __future__ import annotations

import asyncio
import os
import sys

from dotenv import load_dotenv

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE)))  # backend/
load_dotenv(os.path.join(os.path.dirname(HERE), ".env"))

from app.adapters.ai.gemini import build_gemini_provider  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.services.ai_tool_registry import TOOL_DECLARATIONS  # noqa: E402
from app.services.ai_chat_service import SYSTEM_PROMPT  # noqa: E402


async def main() -> None:
    settings = get_settings()
    provider = build_gemini_provider(settings)
    contents: list[dict] = [
        {
            "role": "user",
            "parts": [
                {
                    "text": "Create a new hive with code DIAG-12345 at my apiary.",
                }
            ],
        }
    ]
    for i in (1, 2):
        turn = await provider.generate(
            system=SYSTEM_PROMPT.strip(),  # type: ignore[arg-type]
            contents=contents,
            tool_declarations=TOOL_DECLARATIONS,
        )
        print(f"--- call {i}: error={turn.error!r} text={turn.text[:200]!r} tools={[t.name for t in turn.tool_calls]}")
        if turn.error:
            return
        if not turn.tool_calls:
            return
        for call in turn.tool_calls:
            result = {"status": "needs_confirmation", "confirmed": False,
                      "message": "confirm before recording"}
            part = {"functionCall": {"name": call.name, "args": call.args}}
            if call.id:
                part["functionCall"]["id"] = call.id
            if call.thought_signature:
                part["thoughtSignature"] = call.thought_signature
            contents.append({"role": "model", "parts": [part]})
            contents.append(
                {"role": "user", "parts": [{"functionResponse": {"name": call.name, "response": result}}]}
            )


if __name__ == "__main__":
    asyncio.run(main())