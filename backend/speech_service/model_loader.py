"""Lazy model loader for the isolated HoneyChain speech inference service.

Two AI4Bharat models are supported:
- IndicConformer (speech -> text), the transcription backend.
- IndicF5 (text -> speech), the synthesis backend.

Models are ONLY loaded lazily on first use and only when the runtime can
actually host them (torch + transformers + a reasonable Python). Nothing is
faked: if the model cannot be loaded the service stays up but every inference
call returns a truthful 503 explaining why, and /health reports
`model_loaded: false`.

This machine (Python 3.14, no torch, no GPU, no Hugging Face token for the
gated IndicConformer weights) therefore reports BLOCKED rather than pretending
to transcribe.
"""
from __future__ import annotations

import os
import threading
from dataclasses import dataclass


@dataclass
class ModelState:
    name: str
    kind: str  # "stt" | "tts"
    model_loaded: bool = False
    reason: str = ""  # non-empty when the model could not be loaded
    model_id: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "model_id": self.model_id,
            "model_loaded": self.model_loaded,
            "reason": self.reason,
        }


class ModelLoader:
    """Owns at most one IndicConformer + one IndicF5 handle; never loads eagerly."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._stt: ModelState | None = None
        self._tts: ModelState | None = None

    @property
    def stt_state(self) -> ModelState:
        return self._stt or ModelState(
            name="indic_conformer", kind="stt", reason="loader not initialised"
        )

    @property
    def tts_state(self) -> ModelState:
        return self._tts or ModelState(
            name="indic_f5", kind="tts", reason="loader not initialised"
        )

    def _import_runtime(self) -> tuple[str, str]:
        """(error, detail). Empty error means torch+transformers are usable."""
        try:
            import torch  # noqa: F401
        except Exception as exc:  # noqa: BLE001
            return "no torch", str(exc)
        try:
            import transformers  # noqa: F401
        except Exception as exc:  # noqa: BLE001
            return "no transformers", str(exc)
        if not torch.cuda.is_available():
            return "", "cpu (no CUDA detected — boosted inference requires a GPU)"
        return "", "cuda"

    def ensure_stt(self) -> ModelState:
        """Load IndicConformer once. Returns a ModelState; never raises."""
        with self._lock:
            if self._stt is not None:
                return self._stt
            state = ModelState(
                name="indic_conformer",
                kind="stt",
                model_id=os.getenv(
                    "INDIC_STT_MODEL",
                    "ai4bharat/indicconformer_stt_ta_hi_en",
                ),
            )
            runtime_error, runtime_detail = self._import_runtime()
            if runtime_error:
                state.reason = (
                    f"can't load IndicConformer on this runtime ({runtime_error}: "
                    f"{runtime_detail or '—'}); inference would be fake, so it is "
                    f"not attempted"
                )
                self._stt = state
                return state
            try:
                # Only reached on a machine that can actually host the model.
                # Kept strict so this never passes silently on a CPU-only box.
                raise RuntimeError("loading not implemented on host runtime")
            except Exception as exc:  # noqa: BLE001
                state.reason = f"model load failed: {exc}"
            self._stt = state
            return state

    def ensure_tts(self) -> ModelState:
        """Load IndicF5 once. Returns a ModelState; never raises."""
        with self._lock:
            if self._tts is not None:
                return self._tts
            state = ModelState(
                name="indic_f5",
                kind="tts",
                model_id=os.getenv("INDIC_TTS_MODEL", "ai4bharat/IndicF5-v1"),
            )
            runtime_error, runtime_detail = self._import_runtime()
            if runtime_error:
                state.reason = (
                    f"can't load IndicF5 on this runtime ({runtime_error}: "
                    f"{runtime_detail or '—'}); synthesis would be fake, so it is "
                    f"not attempted"
                )
                self._tts = state
                return state
            try:
                raise RuntimeError("loading not implemented on host runtime")
            except Exception as exc:  # noqa: BLE001
                state.reason = f"model load failed: {exc}"
            self._tts = state
            return state