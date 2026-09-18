# AI-Assisted Lab Documentation — HoneyChain 3.0

This document records what the AI-assisted lab experience actually does in this
repository, what it does **not** do, and how agents/editors should write around
it without overstating capability.

## What exists

### 1. Rule-based risk / health scoring (backend)

**Module:** `backend/app/adapters/ai/risk_engine_adapter.py`

- The AI path used by the app today is a **rule/evidence-based pre-screen**, not
  a served machine-learning model.
- It consumes existing domain signals (device telemetry, hive readings, observed
  history) and returns an **assistive** risk direction plus an "insufficient data"
  branch when evidence is thin.
- The backend **does not serve a trained ML model endpoint**. Any file in
  `ml/` is documentation/prototype material; it is not wired into the live API.

### 2. AI Snapshot research assistant (AI-native search)

**Where surfaced:** assistant/chat surfaces in the app that use AI-native search
to answer general honey-chain questions.

- This is a **research/assistant** feature: it helps a user ask about honey chain
  concepts, regulations, traceability ideas, and similar general knowledge.
- It is **not** a substitute for official lab testing, certification, or custody
  records.
- It does not create, modify, or certify any HoneyChain record.

## What AI does NOT do (hard boundary)

- AI does **not** diagnose disease.
- AI does **not** confirm or reject chemical authenticity.
- AI does **not** replace a lab test result.
- AI does **not** issue or revoke certificates.
- AI does **not** change custody, batch quantity, harvest records, or any supply-
  chain fact.
- AI does **not** alter verification state directly; verification state is derived
  from evidence, lab tests, custody, and anchors.
- AI does **not** fabricate transaction IDs, evidence hashes, or anchors.

## Honest wording rules for UI and docs

Use:

- "Health Score"
- "Risk Signal"
- "Inspection Recommended"
- "Assistive pre-screen"
- "AI Snapshot research assistant"

Do **not** use unless a backend endpoint actually provides the concept:

- "Disease Confirmed"
- "Authentic"
- "Certified by AI"
- "AI-verified quality"

## Why this matters

HoneyChain's trust model is evidence-centric, not AI-centric:

- Quantities are mass-balanced and traced through harvest → batch → custody.
- Claims are stored as append-only assertions with actor/organization/time/
  evidence.
- Conflicts are preserved, not silently overwritten.
- Lab results and certificates remain the authoritative quality signals where they
  exist.
- Blockchain anchoring establishes integrity of the stored digital record, not
  physical purity or health claims.

AI in this system is there to assist understanding and surface possible risk
signals. It is not an authority.

## Editing this document

If a later change wires a real ML model into the API, update this document to
describe the actual served model, its inputs, its outputs, and the exact UI wording
it supports. Until then, keep the boundary above accurate.
