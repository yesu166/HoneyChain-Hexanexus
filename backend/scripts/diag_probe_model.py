import asyncio
import os
import sys

from dotenv import load_dotenv

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE)))
load_dotenv(os.path.join(os.path.dirname(HERE), ".env"))

from app.adapters.ai.gemini import build_gemini_provider
from app.core.config import get_settings


async def main() -> None:
    settings = get_settings()
    provider = build_gemini_provider(settings)
    for i in range(2):
        turn = await provider.generate(
            system="You are Ask My Bee. Reply very briefly.",
            contents=[{"role": "user", "parts": [{"text": "Hi"}]}],
            tool_declarations=[],
        )
        print(f"[{i}] error={turn.error!r}")
        print(f"[{i}] text={turn.text[:200]!r}")
        print(f"[{i}] tools={[t.name for t in turn.tool_calls]}")


if __name__ == "__main__":
    asyncio.run(main())