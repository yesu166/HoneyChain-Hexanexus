"""Internal Fabric service — the EC2 half of the HoneyChain bridge.

This router is NOT part of the public HoneyChain API. It is mounted only on the
EC2 host that holds the Hyperledger Fabric network and the Org1 signing identity,
and it is reachable exclusively through the narrow Caddy allowlist
(`/internal/fabric/health`, `/internal/fabric/anchor`, `/internal/fabric/query`).
Every other path on that host returns 404, so the general API surface — auth,
users, hives, batches, passports — is never reachable through the bridge host.

Security
--------
Authentication uses a shared service secret in an `Authorization: Bearer` header
compared with `hmac.compare_digest`, which keeps the comparison time
independent of how many leading characters match. The expected value comes from
the environment and is never echoed in a response, a log line, or an error
message. If the secret is unset the endpoints refuse every request rather than
defaulting to something guessable.

This router does no business logic of its own: it resolves the genuine
`FabricBlockchainAdapter` and delegates, so real transactions, batch-existence
probes, and endorsement all happen with the identity that lives on this host.
"""
from __future__ import annotations

import hmac
import os
from typing import Any, Literal

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ...adapters.blockchain.gateway import (
    LedgerNotConfigured,
    LedgerUnavailable,
    build_blockchain_gateway,
)
from ...adapters.blockchain.state import TxState

router = APIRouter(prefix="/internal/fabric", tags=["internal-fabric"])

# Mirror of the only three paths Caddy is permitted to proxy. Anything else on
# this host is a 404, which is what prevents the bridge from becoming a second
# public write path into the HoneyChain API.
_ALLOWED_OPS = ("verify_anchor", "transaction_status")


def _configured_secret() -> str:
    """Read the service secret from the environment (never from a request)."""
    return (os.getenv("FABRIC_BRIDGE_TOKEN") or "").strip()


def _require_service_auth(authorization: str | None) -> None:
    """Authenticate the caller with a constant-time bearer-token comparison."""
    expected = _configured_secret()
    if not expected:
        # Refusing everything is the safe failure: an unset secret must never
        # turn into an open endpoint.
        raise HTTPException(
            status_code=503, detail="Internal fabric bridge is not configured"
        )

    scheme, _, provided = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not provided:
        raise HTTPException(status_code=401, detail="Missing service credential")

    # compare_digest keeps the comparison constant-time regardless of how many
    # leading characters an attacker guesses correctly.
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="Invalid service credential")


def _fabric_adapter():
    """Resolve the real Fabric adapter, refusing any non-Fabric configuration.

    Guards against a misconfigured deployment silently serving a bridge backed
    by the local development ledger — the exact fake-chain failure this bridge
    is meant to eliminate.
    """
    gateway = build_blockchain_gateway()
    adapter = gateway._adapter  # noqa: SLF001 - intentional single boundary
    if adapter.ledger_name != "fabric":
        raise HTTPException(
            status_code=503,
            detail="Fabric adapter is not active on this host",
        )
    return adapter


def _error_payload(exc: Exception) -> dict[str, Any]:
    """Render an honest FABRIC_* state for a failed bridge call."""
    text = str(exc)
    if isinstance(exc, LedgerNotConfigured):
        status = "FABRIC_NOT_CONFIGURED"
    elif "FABRIC_TIMEOUT" in text:
        status = "FABRIC_TIMEOUT"
    elif "FABRIC_AUTH_FAILED" in text:
        status = "FABRIC_AUTH_FAILED"
    else:
        status = "FABRIC_UNAVAILABLE"
    return {"status": status, "error": text}


class AnchorRequest(BaseModel):
    payload: dict[str, Any] = Field(default_factory=dict)
    tx_ref: str
    # "anchor" -> anchorMerkleRoot (evidence commitment);
    # "event"  -> submitEvent (domain provenance event, EC2 maps the domain
    #             type to the chaincode's EVENT_TYPES whitelist).
    # Any other value is rejected by pydantic with a 422, so the bridge cannot
    # be used to invoke an arbitrary chaincode function.
    kind: Literal["anchor", "event"] = "anchor"


class QueryRequest(BaseModel):
    op: str
    ref: str
    expected_root: str = ""


@router.get("/health")
def fabric_health(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    """Report the real ledger state from this host's Fabric adapter."""
    _require_service_auth(authorization)
    adapter = _fabric_adapter()
    try:
        return adapter.health_check()
    except (LedgerUnavailable, LedgerNotConfigured) as exc:
        # A health probe is informational: report the failure as data rather
        # than raising, so the caller sees the real status string.
        return {"adapter": "fabric", **_error_payload(exc)}


@router.post("/anchor")
def fabric_anchor(
    body: AnchorRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    """Run a real Fabric transaction and return the real transaction id."""
    _require_service_auth(authorization)
    adapter = _fabric_adapter()
    try:
        if body.kind == "event":
            # Domain provenance event -> chaincode submitEvent. The event-type
            # -> EVENT_TYPES mapping lives in FabricBlockchainAdapter.submit_event
            # so the same mapping applies whichever side submits it.
            result = adapter.submit_event(body.payload, body.tx_ref)
        else:
            result = adapter.submit_anchor(body.payload, body.tx_ref)
    except (LedgerUnavailable, LedgerNotConfigured) as exc:
        raise HTTPException(status_code=503, detail=_error_payload(exc)) from None
    return {
        "tx_hash": result.get("tx_hash", ""),
        "network": result.get("network", "fabric"),
        "state": result.get("state", TxState.CONFIRMED),
        "block_number": result.get("block_number", ""),
        "result": result.get("fabric_result"),
    }


@router.post("/query")
def fabric_query(
    body: QueryRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    """Verify an anchor or read a transaction status from the real ledger."""
    _require_service_auth(authorization)
    if body.op not in _ALLOWED_OPS:
        raise HTTPException(status_code=404, detail="Unknown operation")

    adapter = _fabric_adapter()
    try:
        if body.op == "verify_anchor":
            verified = adapter.verify_anchor(body.ref, body.expected_root)
            return {"verified": bool(verified)}
        status = adapter.get_transaction_status(body.ref)
        return {
            "state": status.get("state", TxState.UNKNOWN),
            "block_number": status.get("block_number", ""),
            "network": status.get("network", "fabric"),
        }
    except (LedgerUnavailable, LedgerNotConfigured) as exc:
        raise HTTPException(status_code=503, detail=_error_payload(exc)) from None
