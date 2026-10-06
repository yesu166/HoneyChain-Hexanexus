# HoneyChain — Cryptography

## Canonical serialization

The same logical payload must always produce the same hash. Before hashing, a
payload is **canonicalized** (recursively):

- object keys are sorted lexicographically
- `null` values are omitted
- numbers are normalized so that `5`, `5.0` and `5.00` hash identically
  (floats without fractional value collapse to the integer form), while
  booleans stay distinct from numbers
- timestamps are emitted as ISO-8601 UTC strings
- arrays keep their element order (order is meaningful)

Canonicalization means hashing arbitrary JSON string ordering is never done.

## Hash / signature primitives

- **Hash:** SHA-256 (hex-encoded).
- **Payload hash:** `sha256(canonical_json(payload))`.
- **Signing:** ECDSA over P-256 (NIST P-256 / secp256r1) using a device /
  actor private key. Signature is DER-encoded and verified against the public
  key. Where platform key storage is unavailable, keys are held in the local
  credential store (never logged).
- The signature attests *"this registered device/actor signed this event"*.
  It does **not** prove a physical sensor was honest. This distinction is
  documented in `docs/KNOWN_LIMITATIONS.md`.

## Hash chain (offline event ledger)

Events may reference `previous_event_hash`. If an event changes, its hash
changes and every subsequent chain reference becomes invalid — providing a
tamper-evident local history. Verification tooling recomputes each event's hash
and walks the chain.

## Merkle tree

Evidence bundles are committed with a Merkle tree, not a single flat hash.

- **Leaves:** canonical hash of each evidence object (hive record, inspection,
  Hive Intelligence Record, harvest, GPS evidence, photo, field verification,
  lab certificate, processing record, packaging, custody event).
- **Internal nodes:** `sha256(left || right)` (sorted-pair hashing).
- **Root hash:** the tree root; this is what gets anchored to the trust layer.

The Merkle structure (leaf hashes and proofs) is stored off-chain; only the
root and suffixed identifiers go to the trust anchor. Proof generation is
supported so a single evidence object can be verified against the root.

## Tamper-evidence, not purity

Blockchain/Merkle anchoring detects that recorded evidence **no longer matches
the anchored commitment** (MISMATCH). It does **not** detect physical
adulteration of honey — laboratory certification establishes quality claims.
This distinction is surfaced in the verification engine and passport language.
