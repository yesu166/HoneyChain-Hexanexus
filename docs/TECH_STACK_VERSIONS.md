# Tech Stack & Versions (as verified this session)

| Layer | Tool | Version |
|---|---|---|
| Mobile | Flutter | 3.47.1 |
| Mobile | Dart | 3.13.1 |
| Backend | Python | 3.14.6 |
| Backend | pip | 26.1.2 |
| Backend | FastAPI | 0.141.1 |
| Backend | Pydantic | 2.13.5 |
| Backend | supabase-py | 2.31.0 |
| Backend | cryptography | 50.0.1 |
| Backend | PyJWT | working (HS256) |
| Migrations | Node.js | v24.19.0 |
| Migrations | npm | 11.17.0 |
| Migrations | `pg` driver | ^8.13.0 |
| Infra | Docker client | 29.7.2 (daemon not running) |
| Infra | Docker Compose | v5.4.0 (daemon not running) |
| Git | git | 2.55.0 |
| Supabase | project | ref `hhxwhopaazqjdlreqhkf` (reachable, migrations applied) |

## Not present (deliberately not claimed)

- `psql` — not installed (use Supabase SQL editor or the Node runner).
- `supabase` CLI — not installed (Node runner is the supported path).
- Chain SDKs (web3.go / fabric-gateway) — not installed; adapter boundaries
  only until a network exists.

## ML (honest note)

`ml/train.py` produced `ml/artifacts/{model.pkl, metrics.json, ...}` at some
point. These are demo artifacts. The running adapter (`risk_engine`) is a
rule-based classifier — it explicitly reports "insufficient data" rather than
inventing a reading.