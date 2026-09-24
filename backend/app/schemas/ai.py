from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field

# The app sends a plain chat transcript (role + content). All tool execution and
# Gemini reasoning stays on the server — the app never sees hive tool payloads.


class AIChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = ""


class AIChatRequest(BaseModel):
    messages: list[AIChatMessage] = Field(..., min_length=1, max_length=40)
    request_id: Optional[str] = None

    @property
    def latest(self) -> str:
        for message in reversed(self.messages):
            if message.role == "user":
                return message.content
        return ""


class AIChatResponse(BaseModel):
    reply: str
    request_id: Optional[str] = None
    tool_count: int = 0


class SpeechProviderStatus(BaseModel):
    """Truthful availability of the optional server-side speech providers.

    The app always works via on-device recognition/on-device TTS regardless;
    these fields say whether a server-side IndicConformer/IndicF5 service is
    configured and reachable so clients never over-state the voice pipeline.
    """

    provider: str = "none"
    available: bool = False
    detail: str = ""


class AIStatus(BaseModel):
    enabled: bool
    configured: bool
    model: str = ""
    stt: SpeechProviderStatus = SpeechProviderStatus()
    tts: SpeechProviderStatus = SpeechProviderStatus()


class STTRequest(BaseModel):
    audio_base64: str = Field(..., min_length=1, max_length=25_000_000)
    language: Optional[str] = None


class STTResponse(BaseModel):
    text: str = ""
    provider: str = "indic_conformer"


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)
    language: Optional[str] = None
    voice: Optional[str] = None


class TTSResponse(BaseModel):
    audio_base64: str = ""
    media_type: str = "audio/wav"