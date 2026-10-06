# Portal E2E traceability

> **Deployment boundary:** the portal and the verified EC2 Fabric network are currently separate environments. Do not infer that the deployed portal is writing to Fabric until the production API path has been connected and re-tested.

How a record proves it is the *same* object across the Flutter beekeeper app,
the HoneyChain API and this portal, and how to reproduce that proof.

The identity that travels end to end is the **backend `batch_code`**. It is
created once, by the API, and is the only identifier the portal will accept for
a passport lookup. Nothing is ever generated client-side.

## Identity chain

| Step | Actor | Identifier produced | Where it comes from |
| --- | --- | --- | --- |
| 1. Create batch | Flutter beekeeper app | `batch_code` | `POST /api/v1/batches` response |
| 2. Record harvest | Flutter app | harvest row, linked to `batch_code` | `POST /api/v1/harvests` |
| 3. Read batches | Portal | `batch_code` | `GET /api/v1/batches` |
| 4. Encode QR | Portal | `/verify/{batch_code}` | `passportVerifyUrl()` in `src/lib/hc/passport.ts` |
| 5. Scan QR | Consumer phone | the same `batch_code`, parsed from the path | `extractCode()` in `passport-page.tsx` |
| 6. Resolve | Public API | passport payload | `GET /api/v1/passport/{batch_code}` |

A QR is a carrier for an identifier, never a container for a data dump. The
payload contains no quantity, no lab result and no event list, so a QR cannot
drift from the database. This is enforced by a test:

```
test("the QR payload is a public verification URL, not a data dump")
```

## Reproducing the proof

1. Sign in to the Flutter app as a beekeeper and create a batch. Record the
   returned `batch_code`.
2. In the portal, sign in as the same organization and open **My hives**. The
   batch appears in the list with that exact `batch_code`.
3. Open the batch. The timeline, laboratory state and custody history are the
   ones the API returned for that `batch_code`.
4. Open the passport for that code and scan its QR with a second device. The
   scanned code must equal the `batch_code` from step 1.
5. Confirm the public passport resolves **without any login**:
   `GET /api/v1/passport/{batch_code}` returns 200.

## What the portal will not claim

The portal reports exactly what the API returned. In particular:

- A lot with `trust_tier: lab_verified` is described as **laboratory-tested**.
  That is a claim about a lab result, not a chain guarantee.
- An anchor is described as confirmed only when the API returns both an
  anchored status and a transaction id. A status of `anchored` with an empty
  `tx_hash` is reported as pending, not as a confirmation.
- On a deployment whose ledger adapter is the in-process development ledger,
  the portal states that anchors are not written to a distributed network. The
  deployed API currently reports `adapter: local` from
  `GET /api/v1/blockchain/health`.

The backend's own passport caveat is the reference wording, and it is shown to
consumers on the passport itself:

> Trust tiers reflect recorded evidence only. Blockchain anchoring provides
> tamper-evidence, not proof of purity. No health or nutrition claims are
> certified.

## Roles needed for the full walkthrough

| Step | Role | Endpoint |
| --- | --- | --- |
| Create batch and harvest | `beekeeper` | `POST /api/v1/batches`, `POST /api/v1/harvests` |
| Read batch, custody, timeline | `fpo` or `processor` | `GET /api/v1/batches` |
| Laboratory result and certificate | `lab` | `POST /api/v1/batches/{id}/lab-tests` |
| Public passport | none | `GET /api/v1/passport/{code}` |

A beekeeper credential is required for step 1 and 2. See
`docs/PORTAL_ROLE_DEPENDENCY_MATRIX.md` for the full permission map.

## Current status

| Item | Status |
| --- | --- |
| Portal reads real batches, hives, harvests, lab tests from the API | verified |
| Public passport resolves a real `batch_code` with no login | verified |
| QR payload is a canonical public URL | verified by test |
| Real Fabric anchor visible in the portal | **not verified** |
| Flutter-created record opened in the portal | **not run** |

The Fabric backend path is verified on the EC2 deployment, but the current portal is pointed at the Render deployment, whose API reports the development `local` ledger. The remaining production proof is to connect the deployed API to the authenticated Fabric gateway and then execute the complete portal/API → Fabric → passport path.
