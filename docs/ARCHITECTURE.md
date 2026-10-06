# HoneyChain — Architecture

> This document is the authoritative live description of the implemented
> architecture. It is updated whenever the implementation changes.

## Core principle

> We don't just trace the jar. We trace the evidence that produced it.

Secondary principle: **invisible complexity, visible simplicity.**

HoneyChain is an **offline-first evidence and provenance system** that uses
cryptographic integrity and blockchain anchoring to make the honey journey
verifiable. The blockchain is the **trust anchor**; the database is the
**canonical data store**; the offline ledger is the **field resilience layer**;
the evidence bundle is the **provenance foundation**; the Merkle tree is the
**cryptographic integrity structure**; signatures establish **actor
attribution**; the lab certificate establishes **quality certification**; batch
lineage establishes **transformation history**; and the Honey Passport is the
**consumer trust interface**.

## Conceptual layers

```
                        HONEYCHAIN CORE
                              |
             +----------------+----------------+
             |                |                |
         IDENTITY          EVIDENCE          POLICY
             |                |                |
             +----------------+----------------+
                              |
                       PROVENANCE GRAPH
                              |
                    CRYPTOGRAPHIC TRUST
             +----------------+----------------+
             |                |                |
            HASH            MERKLE         SIGNATURE
             |                |                |
             +----------------+----------------+
                              |
                     BLOCKCHAIN GATEWAY
                       /               \
                EVM Adapter       Fabric Adapter
                       \               /
                        TRUST LAYER
                              |
                       HONEY PASSPORT
                              |
                         CONSUMER
```

## Application architecture (actors)

Beekeeper App · Field Officer App · FPO/Cooperative Portal · Collection Center
Portal · Laboratory Portal · Processor Portal · Logistics Portal · Retailer
Portal · Regulator Portal · Admin Portal · Consumer Verification.

## Repository structure

```
lib/            Flutter application (offline-first, model/service/screen split)
backend/        FastAPI backend (repository abstraction, services, adapters)
  app/api/routes  HTTP endpoints (auth, hives, harvests, batches, custody, labs,
                  passport, sync, evidence, certificates, lineage, blockchain, tamper, health)
  app/services     domain services (hive, harvest, batch, custody, lab, passport, sync,
                  evidence, lineage, lab_certificate, event_ledger, merkle)
  app/adapters     blockchain (gateway + state + local/evm/fabric) + AI (risk engine)
  app/db           SupabaseRepository / InMemoryRepository / DemoSeededRepository
  app/core         config, security, rbac (permission matrix), crypto, logging
  tests/           pytest (157 green, 3 LIVE_RUNTIME skipped; 3 LIVE_RUNTIME pass against real EC2 Fabric via tunnel)
fabric-gateway-service/  Node.js Fabric Gateway HTTP service (deployed on EC2, systemd, port 9446, live-connected)
fabric/          Chaincode source (tracer/), test-network configs
supabase/       Versioned, idempotent SQL migrations + RLS + seed + apply script
test/           Flutter tests (64 green)
ml/             Optional rule-based risk model artifacts + training script
docs/           This control center + evidence/
```

## Blockchain gateway & adapter taxonomy

The application calls exactly one boundary — `BlockchainGateway`
(`backend/app/adapters/blockchain/gateway.py`). It dispatches to one
`LedgerAdapter` chosen by configuration and tracks each anchor as a
transaction with an explicit state machine
(`PENDING/SUBMITTED/CONFIRMED/FAILED/RETRYING/UNKNOWN`):

- **LocalLedgerAdapter** — in-process dev/testing ledger. Labeled `local` in
  every response; never presented as a real chain.
- **EVMBlockchainAdapter** — EVM (e.g. Polygon Amoy) once RPC + wallet +
  contract are configured. Until then it returns `BLOCKCHAIN_NOT_CONFIGURED`.
- **FabricBlockchainAdapter** — Hyperledger Fabric via the Node.js Fabric
  Gateway service (`fabric-gateway-service/`). The adapter makes HTTP calls
  to the Node.js service which uses the `@hyperledger/fabric-gateway` SDK
  to connect to the real Fabric peer. **Live-proven (2026-09-10)**: the node
  service runs on EC2 (`honeychain-fabric-gateway` systemd unit, port 9446),
  and real anchors were committed and read back through the Python adapter
  (`mychannel`/`honeychain` v2.0 seq 6). Chaincode function mapping mirrors the
  deployed contract: `anchorMerkleRoot`, `getAnchor`, `submitEvent`,
  `createBatch`, etc. Reports:
  - `FABRIC_CONNECTED` — real query succeeded against live Fabric
  - `FABRIC_NOT_CONFIGURED` — no gateway URL configured
  - `FABRIC_UNAVAILABLE` — gateway service unreachable
  - `FABRIC_AUTH_FAILED` — identity/TLS error
  - `FABRIC_TIMEOUT` — gateway service timed out
  - `FABRIC_MISCONFIGURED` — gateway service reports missing env vars

The gateway never fabricates confirmations: `CONFIRMED` requires the adapter
to confirm. See [BLOCKCHAIN.md](./BLOCKCHAIN.md).

## Honest classification

Every feature is internally classified as **REAL / PARTIAL / MOCK /
PLACEHOLDER / BROKEN / UNUSED / DUPLICATED / UNSAFE**. See
[`FEATURE_STATUS.md`](./FEATURE_STATUS.md). Demonstration/simulation
functionality is clearly separated from production functionality and is never
misrepresented as live.

## Deployment modes

Supported deployment modes (configuration driven, not hardcoded into modules):

- **MODE 1** — Standalone local/demo
  (`API_ENV=development`, in-memory repository, `BLOCKCHAIN_ADAPTER=local`).
- **MODE 2** — Supabase-backed (`SUPABASE_SERVICE_ROLE_KEY` set → service-role
  repository + applied migrations).
- **MODE 3** — Supabase + public blockchain anchoring
  (`BLOCKCHAIN_ADAPTER=evm` + RPC/wallet/contract).
- **MODE 4** — Multi-organization consortium (`BLOCKCHAIN_ADAPTER=fabric` +
  channel/chaincode + connection profile).
- **MODE 5** — Future alternate blockchain (add a new `LedgerAdapter`).

Exactly one of these is active at runtime; mode selection can never silently
fall back to a "real" ledger when one is not configured.
