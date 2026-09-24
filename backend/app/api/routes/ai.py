from __future__ import annotations

import asyncio
import base64
import binascii
import time

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, status

from ...core.security import get_current_user
from ...schemas import ai as ai_schemas
from ...api.rate_limit import check_rate

router = APIRouter(prefix="/api/v1", tags=["ai"])

_STT_UNCONFIGURED = (
    "Server speech recognition is not configured (AI_STT_ENABLED / "
    "AI_STT_BASE_URL). The app falls back to on-device recognition — no "
    "transcript is claimed that did not actually run."
)
_TTS_UNCONFIGURED = (
    "Server text-to-speech is not configured (AI_TTS_ENABLED / AI_TTS_BASE_URL). "
    "The app falls back to on-device TTS or plain text — no audio is claimed "
    "that did not actually render."
)
_SPEECH_PROXY_TIMEOUT = 90.0
_HEALTH_TIMEOUT = 6.0
_HEALTH_CACHE_TTL_SECONDS = 15.0
_MAX_AUDIO_BYTES = 30 * 1024 * 1024  # 30 MB


def _audio_error(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=detail
    )


def _validated_audio_bytes(audio_base64: str) -> bytes:
    """Decode and sanity-check the submitted audio before proxying it onward.

    Rejects empty or oversized payloads and undecodable base64. Content is
    otherwise passed through as-is (the app records WAV/MP3/AAC depending on
    the device); the receiving speech service does the format-level parsing.
    """
    if not audio_base64 or not audio_base64.strip():
        raise _audio_error("audio_base64 is empty")
    try:
        audio = base64.b64decode(audio_base64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise _audio_error("audio_base64 is not valid base64") from exc
    if not audio:
        raise _audio_error("audio payload is empty after decoding")
    if len(audio) > _MAX_AUDIO_BYTES:
        raise _audio_error("audio payload exceeds the 30 MB limit")
    return audio


async def probe_speech_health(base_url: str, provider: str) -> ai_schemas.SpeechProviderStatus:
    """Real lightweight health probe against the speech service /health.

    Availability is never inferred from configuration alone: the service is
    only reported available after it actually answers. The probe result is
    cached briefly so the status screen does not hammer the service.
    """
    unreachable = ai_schemas.SpeechProviderStatus(
        provider=provider,
        available=False,
        detail="service unreachable",
    )
    base = base_url.rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=_HEALTH_TIMEOUT) as client:
            response = await client.get(f"{base}/health")
    except httpx.HTTPError as exc:
        unreachable.detail = f"service unreachable: {exc}"
        return unreachable
    if response.status_code >= 400:
        unreachable.detail = f"service unhealthy (HTTP {response.status_code})"
        return unreachable
    try:
        data = response.json()
    except ValueError:
        data = {}
    if data.get("status") not in (None, "ok", "healthy"):
        return ai_schemas.SpeechProviderStatus(
            provider=provider,
            available=False,
            detail=f"service reports status '{data.get('status')}'",
        )
    if data.get("model_loaded") is False:
        return ai_schemas.SpeechProviderStatus(
            provider=provider,
            available=False,
            detail="service reachable but model not loaded",
        )
    return ai_schemas.SpeechProviderStatus(
        provider=provider,
        available=True,
        detail="service healthy and model loaded",
    )


async def _speech_status(
    app_state: Request.state,
    settings: object,
    kind: str,
) -> ai_schemas.SpeechProviderStatus:
    """Configured/disabled gate (synchronous reasoning) plus real /health probe.

    Availability is never inferred from configuration alone; the probe result
    is cached briefly so the status screen does not hammer the service.
    """
    if kind == "stt":
        enabled = bool(getattr(settings, "ai_stt_enabled", False))
        base = (getattr(settings, "ai_stt_base_url", "") or "").strip()
        provider = "indic_conformer"
    else:
        enabled = bool(getattr(settings, "ai_tts_enabled", False))
        base = (getattr(settings, "ai_tts_base_url", "") or "").strip()
        provider = "indic_f5"
    if not enabled:
        return ai_schemas.SpeechProviderStatus(
            provider="none", available=False, detail="disabled by configuration"
        )
    if not base:
        return ai_schemas.SpeechProviderStatus(
            provider=provider,
            available=False,
            detail=f"{provider} enabled but no base URL set",
        )

    cache = getattr(app_state, "speech_health_cache", None)
    if cache is None:
        cache = {}
        app_state.speech_health_cache = cache
    now = time.monotonic()
    cache_key = f"{kind}:{base}"
    cached = cache.get(cache_key)
    if cached and (now - cached[0]) < _HEALTH_CACHE_TTL_SECONDS:
        return cached[1]
    result = await probe_speech_health(base, provider)
    cache[cache_key] = (now, result)
    return result


@router.get("/ai/status", response_model=ai_schemas.AIStatus)
async def ai_status(
    request: Request, user=Depends(get_current_user)
) -> ai_schemas.AIStatus:
    """Tells the app whether Ask My Bee can be used. Never reveals secrets."""
    ai_service = request.app.state.ai_service
    settings = request.app.state.settings
    stt, tts = await asyncio.gather(
        _speech_status(request.app.state, settings, "stt"),
        _speech_status(request.app.state, settings, "tts"),
    )
    return ai_schemas.AIStatus(
        enabled=ai_service.configured,
        configured=bool(settings.gemini_api_key),
        model=settings.gemini_model,
        stt=stt,
        tts=tts,
    )


@router.post("/ai/chat", response_model=ai_schemas.AIChatResponse)
async def ai_chat(
    payload: ai_schemas.AIChatRequest,
    request: Request,
    user=Depends(get_current_user),
) -> ai_schemas.AIChatResponse:
    if not payload.latest.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="empty user message",
        )
    settings = request.app.state.settings
    if not check_rate(
        f"ai:{user.user_id}", limit_per_minute=settings.ai_rate_limit_per_minute
    ):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Ask My Bee rate limit reached — wait a minute and retry.",
        )
    return await request.app.state.ai_service.chat(
        user=user,
        messages=payload.messages,
        request_id=payload.request_id,
    )


@router.post("/ai/speech-to-text", response_model=ai_schemas.STTResponse)
async def ai_speech_to_text(
    payload: ai_schemas.STTRequest,
    request: Request,
    user=Depends(get_current_user),
) -> ai_schemas.STTResponse:
    """Server-side transcription (AI4Bharat IndicConformer behind a speech
    service). Returns 503 truthfully when the service is not configured or not
    reachable — the client then uses on-device recognition instead."""
    settings = request.app.state.settings
    if not (settings.ai_stt_enabled and settings.ai_stt_base_url):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_STT_UNCONFIGURED,
        )
    if not check_rate(
        f"ai-stt:{user.user_id}", limit_per_minute=settings.ai_rate_limit_per_minute
    ):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Speech rate limit reached — wait a minute and retry.",
        )
    audio = _validated_audio_bytes(payload.audio_base64)
    try:
        async with httpx.AsyncClient(timeout=_SPEECH_PROXY_TIMEOUT) as client:
            response = await client.post(
                f"{settings.ai_stt_base_url.rstrip('/')}/transcribe",
                files={
                    "audio": ("audio.wav", audio, "audio/wav"),
                    "language": (None, payload.language),
                },
            )
            response.raise_for_status()
            data = response.json()
    except Exception as exc:  # noqa: BLE001 — surfaced as an honest 503
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Speech recognition service unreachable: {exc}",
        ) from exc
    return ai_schemas.STTResponse(
        text=str(data.get("text", "")),
        provider=str(data.get("provider", "indic_conformer")),
    )


@router.post("/ai/text-to-speech", response_model=ai_schemas.TTSResponse)
async def ai_text_to_speech(
    payload: ai_schemas.TTSRequest,
    request: Request,
    user=Depends(get_current_user),
) -> ai_schemas.TTSResponse:
    """Server-side voice rendering (AI4Bharat IndicF5 behind a speech service).
    Returns 503 truthfully when the service is not configured or unreachable —
    the client then falls back to on-device TTS without pretending otherwise."""
    settings = request.app.state.settings
    if not (settings.ai_tts_enabled and settings.ai_tts_base_url):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_TTS_UNCONFIGURED,
        )
    if not check_rate(
        f"ai-tts:{user.user_id}", limit_per_minute=settings.ai_rate_limit_per_minute
    ):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Speech rate limit reached — wait a minute and retry.",
        )
    try:
        async with httpx.AsyncClient(timeout=_SPEECH_PROXY_TIMEOUT) as client:
            response = await client.post(
                f"{settings.ai_tts_base_url.rstrip('/')}/synthesize",
                json={
                    "text": payload.text,
                    "language": payload.language,
                    "voice": payload.voice,
                },
            )
            response.raise_for_status()
            audio = response.content
            media_type = response.headers.get("content-type", "audio/wav")
    except Exception as exc:  # noqa: BLE001 — surfaced as an honest 503
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Text-to-speech service unreachable: {exc}",
        ) from exc
    return ai_schemas.TTSResponse(
        audio_base64=base64.b64encode(audio).decode("ascii"),
        media_type=media_type,
    )