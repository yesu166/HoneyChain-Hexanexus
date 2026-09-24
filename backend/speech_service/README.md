# Isolated HoneyChain Speech Inference Service (IndicConformer STT / IndicF5 TTS)

Standalone FastAPI service that hosts the optional **AI4Bharat** speech models.
The HoneyChain backend proxies to it:

- `POST /api/v1/ai/speech-to-text`  → `POST /transcribe` (multipart audio + language)
- `POST /api/v1/ai/text-to-speech`  → `POST /synthesize`  (JSON text + language)
- `GET  /health`                     fed into Ask My Bee's status probe (real
  health check — availability is never inferred from configuration alone)

## Run

```bash
pip install -r speech_service/requirements.txt
uvicorn speech_service.app:app --host 0.0.0.0 --port 8100
```

Then in `backend/.env`:

```
AI_STT_ENABLED=true
AI_STT_BASE_URL=http://127.0.0.1:8100
AI_TTS_ENABLED=true
AI_TTS_BASE_URL=http://127.0.0.1:8100
```

## Honesty guarantees

- Models load **lazily**, only on first inference, and only when the runtime can
  actually host them (`torch` present, CUDA recommended).
- Nothing is inferred when no model is loaded: `POST /transcribe` and
  `POST /synthesize` return **503** with the reason; `GET /health` reports
  `model_loaded: false`.
- Audio is validated server-side (RIFF/WAVE + PCM, non-empty, ≤ 30 MB) and
  language is restricted to `ta` / `hi` / `en` (plus the `ta+en` Tanglish hint).

### Status on this dev machine — BLOCKED (real, verified)

`GET /health` → `status: ok`, `model_loaded: false`. Loader reason: `no torch`
(this box runs Python 3.14, which has no torch wheel, no GPU, and the
IndicConformer weights are Hugging Face gated). The smoke test proves the
pipeline end-to-end and reports **BLOCKED** instead of fabricating output:

```bash
python -m speech_service.smoke_test --base http://127.0.0.1:8100
```

On a CUDA-capable host with torch + a Hugging Face token, load IndicConformer
(supported langs ta/hi/en) and IndicF5 inside `model_loader` (the two
`_transcribe_with_model`/`_synthesize_with_model` call-sites in `app.py`).