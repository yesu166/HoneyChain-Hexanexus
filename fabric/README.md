# Hyperledger Fabric — local deployment definition

This directory contains a **real**, standard-format Hyperledger Fabric
network definition for locally provisioning the `honeychain` channel and the
`tracer` chaincode.

> **STATUS — NOT EXECUTED in this environment.**
> The Docker daemon is not running here, so *nothing below has been run*.
> These files are the deployment *definition*: ready to stand up once a Docker
> daemon is available. The backend's `FabricBlockchainAdapter` will keep
> returning `FABRIC_NOT_CONFIGURED` / `FABRIC_UNAVAILABLE` until the network
> is actually reachable.

## What is included

- `docker-compose.yaml` — orderer (`orderer.example.com`), one peer
  (`peer0.org1.example.com`), and a CLI container.
- `crypto-config.yaml` — MSP/identities definition for `cryptogen`.
- `configtx.yaml` — genesis + `honeychain` channel profile.
- `chaincode/tracer/` — Node.js chaincode (fabric-contract-api) that persists
  anchor hashes and explicit business events, and exposes `VerifyAnchor`.
- `scripts/` — provisioning scripts (start network via the fabric-tools
  image; package/approve/commit the chaincode).

## Honest requirements before running

1. Docker daemon running (it is **not** in this environment — B4).
2. The official `hyperledger/fabric-tools:2.5`, `-peer`, `-orderer` images
   pulled. Binaries are **not** vendored; `cryptogen`, `configtxgen`,
   `peer`, `osnadmin` are run from the fabric-tools container.
3. These scripts are a **definition, not an executed run** — validate them on
   a real daemon and adjust for your host paths before relying on them.

## How to deploy (when the daemon is up)

```bash
cd fabric
/bin/bash scripts/start-network.sh     # MSP + genesis, up orderer+peer, create/join honeychain
/bin/bash scripts/deploy-chaincode.sh  # package/install/approve/commit tracer
```

Then point the backend at it:

```bash
BLOCKCHAIN_ADAPTER=fabric
FABRIC_CHANNEL=honeychain
FABRIC_CHAINCODE=tracer
# + connection profile + MSP identity configured in EVM/Fabric gateway wiring
```

## How NOT to use this

- Do NOT claim a Fabric transaction exists before `VerifyAnchor` succeeds
  against a live peer. The adapter raises `FABRIC_NOT_CONFIGURED` until a real
  network answers.
- Do NOT commit MSP material (generated secrets) to the repository.