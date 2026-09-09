# Known Limitations (explicit, honest)

## Runtime / infrastructural

1. **Backend does not write to hosted Supabase today.** Requires
   `SUPABASE_SERVICE_ROLE_KEY` (not provided). Local runs use
   `DemoSeededRepository` (in-memory). Schema is real and applied; writes are
   not.
2. **No real blockchain.** `local` ledger only; EVM/Fabric are boundaries.
   Nothing is misrepresented as anchored on a public network.
3. **Docker daemon off / no compose files** — no container packaging verified.
4. **`supabase` CLI absent** — migrations go through the Node runner instead.
5. **ML artifacts are demo artifacts** — the "model" is a rule-based risk
   engine; `ml/model.pkl` and metrics must not be cited as trained-model
   accuracy.

## Product / design gaps

6. **Photos are not uploaded** — only content hashes + descriptions are
   recorded. Real media storage is a TODO with the customer.
7. **QR/camera not exercised on hardware** — widget tests only.
8. **Offline app ↔ backend conflict resolution is fork-recording, not
   auto-merge** — both branches are preserved and surfaced; merging is an
   explicit operation.
9. **Rate limiter is in-memory** — fine for dev; use Redis for multi-instance
   production.
10. **Trust tiers reflect recorded evidence, not purity.** A `blockchain_anchored`
    lot can still be counterfeited at the physical-good level; the system
    proves provenance of *records*.

## Behavior boundaries (by design, not bugs)

11. A revoked certificate is invalid forever (no un-revoke).
12. Batch state machine rejects backwards transitions (corrections go through
    the `CORRECTION` custody event instead of rewriting).
13. `demo.tamper` endpoints exist only outside production.