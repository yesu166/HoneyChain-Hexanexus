# Honey Yatra QR & Honey Passport

**Scope:** the exact QR contract, how scanning resolves to records, and the honest online
verification path. Companion: `PROVENANCE_MODEL.md` (trust tiers + anchors).

## 1. Honey Yatra QR contract (canonical)

All consumer-facing Honey Yatra QR payloads are produced by `lib/services/trace_qr_service.dart`:

| Scheme | Example | Meaning |
|---|---|---|
| `honeychain://trace/<productCode>` | `honeychain://trace/HC-P-001` | traced product (canonical) |
| `honeychain://jar/<jarId>` | `honeychain://jar/JAR-OO-0042` | packed jar (legacy, compatible) |

Rules:

- `TraceQrService.parse()` accepts **only** a `honeychain://` prefix with a known `trace`/`jar`
  path — anything else is rejected (`ScanResolutionUnknown` with a reason).
- **The payload is NOT cryptographically signed.** Honey Yatra QR is a plain readable identifier; the
  guidance that the record is anchored is backed by the ledger, but the QR itself makes no
  signature claim. This is stated in the app and the docs (see `FINAL_TRUTH_REPORT.md`).
- Real QR generation (mobile) uses `qr_flutter` (`QrImageView`), found in
  `HoneyPassportScreen._PassportQr`.

## 2. Scan → resolution

The scanner handles three shapes:

1. `jar` → `HoneyJar` → its source `Batch` → passport rendered at jar level.
2. `trace` → `ProductBatch` → parent `Batch` → passport at product level.
3. A bare batch code typed by hand resolves to the `Batch` directly.

Recognition uses the store's **local records first** (offline-first). If a code is not found
locally, the resolution is `ScanResolutionUnknown` with an honest reason — the app does not
invent a passport.

## 3. Honey Passport (the single canonical view)

`lib/screens/honey_passport_screen.dart` renders, in order:

1. **Trust tier card** — `TrustService`-derived tier (self-declared →
   organization-verified → lab-verified → blockchain-anchored) with honest captions
   ("no independent proof yet" / "proof is partial").
2. **Online verification panel** *(added in this pass)* — calls the public backend endpoint
   `GET /api/v1/passport/{subject_code}`:
   - `verified` → shows the returned trust tier + anchor block (chain status, tx hash) — only
     shown when the server actually returned a real passport.
   - `not found` / `rate limited` / `unreachable` / `error` → honest message with retry.
   - **No `API_BASE_URL` compiled in** → "Online verification not available in this build" —
     **never a fake verification**.
   - Impl: `lib/services/passport_verification_service.dart` (+ `verifyPassport` in the store).
   - The panel verifies the **batch** code of the subject shown.
3. **Evidence / caveats panel** — every trust claim and every caveat, no decorative
   certificates.
4. **Journey timeline** — harvest, custody, lab, anchor events.
5. **The QR** the consumer can scan.

## 4. Backend passport (server side)

`backend/app/api/routes/passport.py` exposes the **public, no-auth** endpoint
`GET /api/v1/passport/{subject_code}` (rate-limited per IP). `PassportService.resolve()`
returns only PII-free fields (no phones, emails, KYC) and includes the `anchor`
(data/tx hash, `chain_status`) and a fixed caveat about tamper-evidence vs. purity.
Schema: `backend/app/schemas/passport.py`.

## 5. Honesty contract

- A "verified" result requires a real HTTP 200 from the backend for that exact code.
- `PassportAnchorStatus.anchored/pending/none` map 1:1 to the server field `chain_status`
  (`anchored` / `pending` / anything else).
- The app never fabricates a tx id, block or anchor; without a backend it says so.