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
    language: Optional[str] = Field(
        default=None,
        description="App-selected language code (en/hi/ta/bn/pa/ml/mr). When set, "
        "Ask My Bee replies in that language.",
    )

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


SUPPORTED_TTS_LANGUAGES = {
    "en": "english",
    "ta": "tamil",
    "hi": "hindi",
    "bn": "bengali",
    "pa": "punjabi",
    "ml": "malayalam",
    "mr": "marathi",
}

# Server-side voice selection per app language. The speech service (IndicF5)
# receives both, so the app does not need to know service-specific voice ids.
TTS_VOICE_BY_LANGUAGE = {
    "en": "en-IN-SwaraNeural",
    "ta": "ta-IN-Valluvar",
    "hi": "hi-IN-Madhur",
    "bn": "bn-IN-Dipannita",
    "pa": "pa-IN-Simran",
    "ml": "ml-IN-Sobhana",
    "mr": "mr-IN-Aarohi",
}


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)
    language: Optional[str] = Field(
        default=None,
        description="App language code (en/hi/ta/bn/pa/ml/mr). When set it drives "
        "server-side voice selection and per-language failure messaging.",
    )
    voice: Optional[str] = Field(
        default=None,
        description="Explicit voice id; overrides the language default.",
    )


class TTSResponse(BaseModel):
    audio_base64: str = ""
    media_type: str = "audio/wav"