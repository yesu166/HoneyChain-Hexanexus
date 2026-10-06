# Portal reference review

Audit of where every figure, status word and identifier on the portal comes
from, and which behaviours were corrected because they were not faithful to the
API.

Rule applied throughout: **HoneyChain is authoritative.** The portal renders
what the API returns, states when the API said nothing, and never substitutes a
plausible number, a friendlier status word, or sample data.

## Live counts, as returned by the API

From `GET /api/v1/platform/stats` on the deployed API:

| Field | Value |
| --- | --- |
| `registered_beekeepers` | 51 |
| `organizations` | 13 |
| `batches` | 24 |

| Figure | Value | Source |
| --- | --- | --- |
| Hives | 48 | `GET /api/v1/hives` |
| Harvests | 33 | `GET /api/v1/harvests` |
| Total honey | 441.25 kg | aggregate of the harvest records |
| Lab tests | 9 | `GET /api/v1/labs/tests` |
| Devices | 10 | `GET /api/v1/iot/devices` |

No KPI on the dashboard is a client-side constant. Where the API omits a
field, the portal renders **Not available** via `fmtNum()` rather than `0`, so
an absent figure can never be misread as a real measurement.

## Identity

`GET /api/v1/auth/me` is the single source of the operator's identity. The
`name` is rendered verbatim. The seeded administrator genuinely returns
`name: "Demo Admin"`, and that is a property of the database, not a label the
portal invented. There is no prettifying step, and a test guards against one
being reintroduced.

## Corrected behaviours

| Was | Now | Why it mattered |
| --- | --- | --- |
| A network fault rendered as "record not found" | Classified as network / timeout / http | 404 is the only status described as a missing record |
| A stored demo marker could out-rank a live JWT | Live token is examined first; demo state is session-scoped | A browser that once opened the demo returned as "Demo Admin" after a real login |
| 403 on organizations and beekeepers rendered as an empty table | Renders as a permission state | "No organizations were returned" misreported the platform |
| `chain_status: anchored` rendered as a green **Verified** badge | Anchor wording never uses verification language | The deployed API runs the in-process development ledger |
| A reachable local ledger read as healthy | Reads as a warning and names the limitation | An in-process map provides no tamper-evidence |
| Batch badge ran the ledger *connection* status through the per-anchor label | States the ledger the API is actually using | It printed "Anchor state unknown" on a healthy Fabric network |
| Passport header said "HoneyChain verified product" | Says "Laboratory-tested product" | Names what was actually verified |
| Two retries per request (transport plus query) | One controlled retry, in the transport | Up to three extra attempts, multiplied across every card on a dashboard |
| Offline screen asserted "You are still signed in" | Reads the real session | A failed sign-in reaches that screen with no token |
| Retry on the offline screen only re-probed health | Re-runs the `/auth/me` handshake | Connectivity returned but the workspace stayed stuck |
| A failed sign-in could leave the screen loading forever | Every attempt settles | The login call sat outside its own error handling |

## Ledger status

`GET /api/v1/blockchain/health` is public on the API, which lets both the
authenticated dashboard and the public consumer passport state the truth.

The deployed Render API returns:

```json
{ "adapter": "local", "status": "local", "channel": "", "chaincode": "" }
```

The portal therefore reports the development ledger and says plainly that
anchors are not written to a distributed network. When a real Fabric network
answers, the same screen shows the channel, chaincode, version, peer and MSP
the API returned, and omits any field the API did not send.

## Deployment gap

A real Hyperledger Fabric network is running on EC2 with chaincode `honeychain` v2.0 on channel `mychannel`, and the HC-3.0-main repository contains backend-side committed/read-back proof. It is **not yet the ledger used by the current deployed portal API**.

The portal must not be repointed at it yet:

- no HTTPS endpoint or reverse proxy in front of it
- `CORS_ORIGINS` is empty, so browser preflight fails
- its JWT signing secret differs from the deployed API's, so tokens would not
  validate across the two

Closing that needs a backend deployment change, which is out of scope for the
portal. Until then, the portal keeps pointing at the deployed API and labels
its ledger honestly.

## Residual gaps

- No full list of users exists in the API, so the "beekeepers" table shows
  platform membership rather than a user directory.
- The backend has no distributor or retailer role, so no such workspace was
  built. Nearest real workflows are custody transfer and read-only browsing.
- A beekeeper-credential end-to-end run, and a real Fabric anchor visible in
  the portal, are still outstanding. Tracked in
  `docs/PORTAL_E2E_TRACEABILITY.md`.
