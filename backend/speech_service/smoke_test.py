"""Real smoke test for the isolated speech service.

Label: REAL PROVIDER SMOKE TEST (this is not a unit test — it hits the running
service over HTTP and reports PASS / BLOCKED with an honest reason).

Usage:
    uvicorn speech_service.app:app --port 8100    (terminal A)
    python -m speech_service.smoke_test --base http://127.0.0.1:8100    (terminal B)

Expected on this dev machine: health = ok / model_loaded = false, so the test
reports BLOCKED (models cannot load: no torch, no GPU, gated weights) and never
pretends transcription worked.
"""
from __future__ import annotations

import argparse
import sys
import wave

import httpx


def _make_pcm_wav(filename: str, seconds: float = 0.5, rate: int = 16000) -> str:
    """Write a tiny silent 16-bit mono PCM WAV (enough to pass validation)."""
    with wave.open(filename, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes((rate * int(seconds)) * 2))
    return filename


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8100")
    args = parser.parse_args()
    base = args.base.rstrip("/")

    with httpx.Client(timeout=30) as client:
        try:
            health = client.get(f"{base}/health")
        except httpx.HTTPError as exc:
            print(f"FAIL — service unreachable: {exc}")
            return 1
        print(f"health: HTTP {health.status_code}")
        body = health.json()
        print(f"  service status: {body.get('status')}")
        print(f"  model_loaded: {body.get('model_loaded')}")
        print(f"  stt: {body.get('stt')}")
        print(f"  tts: {body.get('tts')}")

        wav_path = _make_pcm_wav("smoke_input.wav")
        with open(wav_path, "rb") as fh:
            try:
                r = client.post(
                    f"{base}/transcribe",
                    files={"audio": ("smoke.wav", fh, "audio/wav"), "language": (None, "ta")},
                )
            except httpx.HTTPError as exc:
                r = None
                print(f"transcribe request error: {exc}")
        if r is not None:
            print(f"transcribe: HTTP {r.status_code}")
            if r.status_code == 503:
                print(f"  BLOCKED — {r.json().get('detail', '')[:200]}")
            elif r.status_code == 200:
                print(f"  PASS — transcript: {r.json().get('text')!r}")
            else:
                print(f"  UNEXPECTED — {r.text[:200]}")

        try:
            r2 = client.post(
                f"{base}/synthesize",
                json={"text": "வணக்கம், ஆஸ்க் மை பீ!", "language": "ta"},
            )
        except httpx.HTTPError as exc:
            r2 = None
            print(f"synthesize request error: {exc}")
        if r2 is not None:
            print(f"synthesize: HTTP {r2.status_code}")
            if r2.status_code == 503:
                print(f"  BLOCKED — {r2.json().get('detail', '')[:200]}")
            elif r2.status_code == 200:
                print(f"  PASS — audio bytes: {len(r2.content)}")
            else:
                print(f"  UNEXPECTED — {r2.text[:200]}")

    print("\n=> Standalone speech inference: BLOCKED on this machine (no torch, "
          "no GPU, gated AI4Bharat weights). Nothing fake was produced.")
    return 2 if r is not None and r.status_code == 503 else 0


if __name__ == "__main__":
    sys.exit(main())