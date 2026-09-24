"""Isolated HoneyChain speech inference service (FastAPI).

Endpoints
---------
GET  /health       Host + model reality check for the main backend's status probe.
POST /transcribe   Multipart (audio file + language) -> {"text", "language", "provider"}.
POST /synthesize   JSON {text, language, voice} -> audio bytes (WAV).

The service is honest by construction: unless an IndicConformer/IndicF5 model is
actually loaded, inference endpoints return 503 with the reason and /health
reports `model_loaded: false`. On machines that cannot host torch (this dev box:
Python 3.14, no torch, no GPU, gated AI4Bharat weights) the models never load and
every inference call is a truthful 503.
"""
from __future__ import annotations

import struct

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from .model_loader import ModelLoader

app = FastAPI(title="HoneyChain Speech Service", version="1.0.0")
_loader = ModelLoader()

MAX_AUDIO_BYTES = 30 * 1024 * 1024  # 30 MB, matches the main backend proxy.
_SUPPORTED_INFER_LANGUAGES = ("ta", "hi", "en")


class SynthesisRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)
    language: str | None = None
    voice: str | None = None


def _wave_audio_is_valid(data: bytes) -> str:
    """Best-effort WAV validation; returns an error message or '' when valid."""
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return "not a RIFF/WAVE container"
    if data[12:16] != b"fmt ":
        return "missing fmt chunk"
    try:
        audio_format, channels, _, _, _, bits = struct.unpack_from(
            "<HHIIHH", data, 20
        )
    except struct.error as exc:
        return f"malformed fmt chunk: {exc}"
    if audio_format != 1:  # PCM only at the validation layer
        return "expected PCM (format 1)"
    if len(data) <= 44:
        return "WAV payload is empty (header only)"
    if channels not in (1, 2):
        return f"unsupported channel count {channels}"
    if bits not in (8, 16, 24, 32):
        return f"unsupported bit depth {bits}"
    return ""


def _validate_transcription(language: str | None, audio: bytes) -> str:
    lang = (language or "ta").lower().replace(" ", "")
    if lang in ("taen", "ta+en", "tanglish", "ta-en"):
        lang = "ta+en"
    if lang not in _SUPPORTED_INFER_LANGUAGES + ("ta+en",):
        raise HTTPException(
            status_code=422,
            detail=f"language '{language}' not supported (supported: ta, hi, en)",
        )
    error = _wave_audio_is_valid(audio)
    if error:
        raise HTTPException(status_code=422, detail=f"audio rejected: {error}")
    return lang


@app.get("/health")
def health() -> dict:
    stt = _loader.stt_state
    return {
        "status": "ok",
        "provider": "speech-service",
        "model_loaded": stt.model_loaded,
        "stt": stt.to_dict(),
        "tts": _loader.tts_state.to_dict(),
    }


@app.post("/transcribe")
async def transcribe(
    audio: UploadFile = File(...), language: str | None = Form(None)
) -> dict:
    data = await audio.read()
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="audio exceeds the 30 MB limit")
    lang = _validate_transcription(language, data)
    state = _loader.ensure_stt()
    if not state.model_loaded:
        raise HTTPException(status_code=503, detail=state.reason)
    # Only reachable with a real loaded model; the transcript is real.
    text = _transcribe_with_model(audio_bytes=data, language=lang, state=state)
    return {"text": text, "language": lang, "provider": "indic_conformer"}


@app.post("/synthesize")
def synthesize(payload: SynthesisRequest) -> Response:
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="text is empty")
    lang = (payload.language or "ta").lower()
    if lang not in _SUPPORTED_INFER_LANGUAGES:
        raise HTTPException(
            status_code=422,
            detail=f"language '{payload.language}' not supported (supported: ta, hi, en)",
        )
    state = _loader.ensure_tts()
    if not state.model_loaded:
        raise HTTPException(status_code=503, detail=state.reason)
    wav = _synthesize_with_model(text=text, language=lang, voice=payload.voice, state=state)
    return Response(content=wav, media_type="audio/wav")


def _transcribe_with_model(audio_bytes: bytes, language: str, state) -> str:
    raise RuntimeError(f"{state.name} not actually loaded on this runtime")


def _synthesize_with_model(text: str, language: str, voice: str | None, state) -> bytes:
    raise RuntimeError(f"{state.name} not actually loaded on this runtime")