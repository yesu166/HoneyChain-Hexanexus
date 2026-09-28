"""RemoteFabricAdapter — the Render-side half of the HoneyChain Fabric bridge.

Why this exists
---------------
`honeychain-api.onrender.com` is the only public HoneyChain API, but the real
Hyperledger Fabric network and the Org1 identity that signs for it live on one
EC2 host. Two properties are non-negotiable:

  1. The Fabric private key must never leave EC2.
  2. The portal must keep talking to a single production API, so there is
     exactly one write path and anchoring is deterministic.

This adapter satisfies both by forwarding *already-hashed* commitments to a
narrow internal service on EC2, which performs the real transaction using the
identity it holds. It implements the same `LedgerAdapter` interface as
`FabricBlockchainAdapter`, so `evidence_service` and `assertion_service` call it
with no changes at all.

What this adapter deliberately does NOT do
-----------------------------------------
It never falls back to the local development ledger. If EC2 is unreachable the
caller gets `FABRIC_UNAVAILABLE` / `FABRIC_TIMEOUT` and the product says the
anchor is pending or unavailable. Silently downgrading a real-chain write to an
in-process dict is the exact failure this whole bridge exists to prevent, so the
`LedgerNotConfigured` / `LedgerUnavailable` contract of the real adapter is
preserved verbatim.

Batch existence on the ledger (`_ensure_batch_on_ledger`) is intentionally NOT
mirrored here: the EC2 side calls the genuine `FabricBlockchainAdapter`, which
already performs the real `getBatch` probe and only then issues `createBatch`.
Duplicating that logic would risk two code paths disagreeing about ledger state.
"""
from __future__ import annotations

import json as _json
import urllib.error
import urllib.request
from typing import Any

from .gateway import LedgerAdapter, LedgerNotConfigured, LedgerUnavailable
from .state import TxState

# The three paths Caddy is allowed to proxy. Anything else on the bridge host
# returns 404 and is never forwarded, which is what keeps the general
# HoneyChain API (auth, users, hives, batches, passports) unreachable there.
BRIDGE_HEALTH_PATH = "/internal/fabric/health"
BRIDGE_ANCHOR_PATH = "/internal/fabric/anchor"
BRIDGE_QUERY_PATH = "/internal/fabric/query"


class RemoteFabricAdapter(LedgerAdapter):
    """Talks to the Fabric-backed HoneyChain service on EC2 over HTTPS.

    The bridge URL is a public HTTPS endpoint, not a secret. The shared service
    secret authenticates the call and is read from the environment only — it is
    never logged, never returned in a response, and never placed in a `VITE_*`
    variable (those are inlined into the browser bundle).
    """

    # The chain really is Hyperledger Fabric; only the network hop differs from
    # the in-process FabricBlockchainAdapter, so the honest label is unchanged.
    ledger_name = "fabric"

    def __init__(
        self,
        *,
        bridge_url: str = "",
        service_token: str = "",
        timeout: int = 30,
        channel: str = "",
        chaincode: str = "",
    ) -> None:
        self._bridge_url = (bridge_url or "").rstrip("/")
        self._token = service_token or ""
        self._timeout = timeout
        # Carried for status reporting only. The authoritative values come back
        # from the bridge's own health response.
        self._channel = channel
        self._chaincode = chaincode

    @property
    def configured(self) -> bool:
        return bool(self._bridge_url and self._token)

    @property
    def fabric_status(self) -> str:
        if not self._bridge_url:
            return "FABRIC_NOT_CONFIGURED"
        if not self._token:
            # Refuse to run unauthenticated. A missing secret is a deployment
            # error, not a reason to talk to the bridge in the clear.
            return "FABRIC_NOT_CONFIGURED"
        return "CONFIGURED"

    # ------------------------------------------------------------------
    # Transport
    # ------------------------------------------------------------------

    def _request(
        self, method: str, path: str, body: dict[str, Any] | None = None, timeout: int | None = None
    ) -> dict[str, Any]:
        """POST/GET to the bridge, mapping every failure to an honest state.

        The token travels in an Authorization header over HTTPS. It is never
        written to a log line or included in an exception message — the raised
        errors reference the path only, so a secret cannot leak through a
        traceback or an error surfaced to the browser.
        """
        if not self._bridge_url:
            raise LedgerNotConfigured(
                "FABRIC_NOT_CONFIGURED: no FABRIC_BRIDGE_URL configured"
            )
        if not self._token:
            raise LedgerNotConfigured(
                "FABRIC_NOT_CONFIGURED: no FABRIC_BRIDGE_TOKEN configured"
            )

        url = f"{self._bridge_url}{path}"
        data = _json.dumps(body).encode("utf-8") if body is not None else None
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self._token}",
        }
        wait = self._timeout if timeout is None else timeout

        try:
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=wait) as resp:
                raw = resp.read().decode("utf-8")
                parsed = _json.loads(raw) if raw else {}
                if not isinstance(parsed, dict):
                    return {"result": parsed}
                return parsed
        except urllib.error.HTTPError as exc:
            body_text = ""
            try:
                body_text = exc.read().decode("utf-8")
            except Exception:
                pass
            # 401/403 means the bridge rejected our credential. That is an
            # authentication failure, not a transport failure, and it must not
            # be reported as "Fabric is down".
            if exc.code in (401, 403):
                raise LedgerUnavailable(
                    f"FABRIC_AUTH_FAILED: bridge at {path} rejected the service credential"
                ) from exc
            if exc.code == 404:
                raise LedgerUnavailable(
                    f"FABRIC_UNAVAILABLE: bridge path {path} is not exposed by the Fabric service"
                ) from exc
            raise LedgerUnavailable(
                f"FABRIC_HTTP_ERROR: {exc.code} from bridge at {path}"
            ) from exc
        except urllib.error.URLError as exc:
            reason = getattr(exc, "reason", exc)
            if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
                raise LedgerUnavailable(
                    f"FABRIC_TIMEOUT: Fabric bridge at {path} timed out after {wait}s"
                ) from None
            raise LedgerUnavailable(
                f"FABRIC_UNAVAILABLE: cannot reach Fabric bridge at {path} - {reason}"
            ) from exc
        except TimeoutError:
            raise LedgerUnavailable(
                f"FABRIC_TIMEOUT: Fabric bridge at {path} timed out after {wait}s"
            ) from None
        except LedgerNotConfigured:
            raise
        except Exception as exc:  # pragma: no cover - defensive
            raise LedgerUnavailable(
                f"FABRIC_UNAVAILABLE: bridge call to {path} failed - {exc}"
            ) from exc

    def _raise_for_remote_error(self, payload: dict[str, Any]) -> None:
        """Turn an error body from the bridge into the matching exception.

        The bridge reports the same FABRIC_* vocabulary the in-process adapter
        uses, so the states stay identical whether the ledger hop is local or
        remote. A failure here is never downgraded to the local ledger.
        """
        status = str(payload.get("status") or "")
        error = str(payload.get("error") or "")

        if status == "misconfigured" or "FABRIC_MISCONFIGURED" in error:
            raise LedgerNotConfigured(f"FABRIC_MISCONFIGURED: {error}")
        if status in ("unavailable", "FABRIC_UNAVAILABLE"):
            raise LedgerUnavailable(f"FABRIC_UNAVAILABLE: {error}")
        if "FABRIC_TIMEOUT" in error:
            raise LedgerUnavailable(f"FABRIC_TIMEOUT: {error}")
        if "FABRIC_NOT_CONFIGURED" in error:
            raise LedgerNotConfigured(f"FABRIC_NOT_CONFIGURED: {error}")
        if "auth" in error.lower() or "UNAUTHENTICATED" in error:
            raise LedgerUnavailable(f"FABRIC_AUTH_FAILED: {error}")

    # ------------------------------------------------------------------
    # LedgerAdapter interface
    # ------------------------------------------------------------------

    def health_check(self) -> dict[str, Any]:
        """Report the real ledger state by asking the bridge.

        The bridge answers with whatever the genuine Fabric adapter reports on
        EC2 (channel, chaincode, version, sequence). When the bridge cannot be
        reached the result is an explicit unavailable state — never "local", and
        never a claim that the chain is healthy.
        """
        if not self.configured:
            return {
                "adapter": "fabric",
                "status": "FABRIC_NOT_CONFIGURED",
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": "Fabric bridge is not configured on this deployment",
            }

        try:
            resp = self._request("GET", BRIDGE_HEALTH_PATH, timeout=10)
        except LedgerNotConfigured as exc:
            return {
                "adapter": "fabric",
                "status": "misconfigured",
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": str(exc),
            }
        except LedgerUnavailable as exc:
            text = str(exc)
            status = "FABRIC_TIMEOUT" if "FABRIC_TIMEOUT" in text else "FABRIC_UNAVAILABLE"
            if "FABRIC_AUTH_FAILED" in text:
                status = "FABRIC_AUTH_FAILED"
            return {
                "adapter": "fabric",
                "status": status,
                "channel": self._channel,
                "chaincode": self._chaincode,
                "error": text,
            }

        # Pass the bridge's own fields through unchanged so the operator sees
        # the real chain, not a re-labelled copy of it.
        health = {
            "adapter": "fabric",
            "status": resp.get("status", "unknown"),
            "channel": resp.get("channel", self._channel),
            "chaincode": resp.get("chaincode", self._chaincode),
            "chaincode_version": resp.get("chaincode_version"),
            "chaincode_sequence": resp.get("chaincode_sequence"),
            "peer": resp.get("peer", ""),
            "msp_id": resp.get("msp_id", ""),
            "last_verified_at": resp.get("last_verified_at"),
            "error": resp.get("error"),
        }
        return health

    def submit_anchor(self, payload: dict[str, Any], tx_ref: str) -> dict[str, Any]:
        """Anchor a commitment by asking the bridge to run the real transaction.

        The payload carries hashes and references only. The Fabric signing
        identity stays on EC2, so the real `tx_id` returned here is produced by
        the Gateway SDK on the far side and relayed untouched.
        """
        resp = self._request(
            "POST",
            BRIDGE_ANCHOR_PATH,
            {"payload": payload, "tx_ref": tx_ref},
        )
        if resp.get("error"):
            self._raise_for_remote_error(resp)

        tx_hash = str(resp.get("tx_hash") or "")
        if not tx_hash:
            # The bridge answered but produced no transaction id. Reporting a
            # success without one would be the "Blockchain Verified" lie.
            raise LedgerUnavailable(
                "FABRIC_UNAVAILABLE: bridge returned no transaction id for the anchor"
            )

        return {
            "tx_hash": tx_hash,
            "network": resp.get("network") or f"fabric:{resp.get('channel', '')}",
            "state": TxState.CONFIRMED,
            "block_number": resp.get("block_number", ""),
            "fabric_result": resp.get("result"),
        }

    def submit_event(self, event: dict[str, Any], tx_ref: str) -> dict[str, Any]:
        """Write a real domain provenance event to Fabric via the bridge.

        Forwards the raw domain event with `kind: "event"` so the EC2 side runs
        the genuine `FabricBlockchainAdapter.submit_event`, which maps the domain
        type onto the chaincode's EVENT_TYPES whitelist and submits the real
        `submitEvent` transaction. This keeps a single mapping implementation
        instead of duplicating it on both hosts, and it never falls back to the
        base-class behaviour of merely anchoring the event's hash — an anchor is
        not an event, and reporting one as the other would be a lie.
        """
        resp = self._request(
            "POST",
            BRIDGE_ANCHOR_PATH,
            {"payload": event, "tx_ref": tx_ref, "kind": "event"},
        )
        if resp.get("error"):
            self._raise_for_remote_error(resp)

        tx_hash = str(resp.get("tx_hash") or "")
        if not tx_hash:
            raise LedgerUnavailable(
                "FABRIC_UNAVAILABLE: bridge returned no transaction id for the event"
            )

        return {
            "tx_hash": tx_hash,
            "network": resp.get("network") or f"fabric:{resp.get('channel', '')}",
            "state": TxState.CONFIRMED,
            "block_number": resp.get("block_number", ""),
            "fabric_result": resp.get("result"),
        }

    def verify_anchor(self, ref: str, expected_root: str = "") -> bool:
        """True only when the bridge can prove [ref] is anchored on Fabric.

        Delegates to the genuine adapter's proof, so an unverifiable claim
        cannot be manufactured on the Render side.
        """
        if not ref:
            return False
        resp = self._request(
            "POST",
            BRIDGE_QUERY_PATH,
            {
                "op": "verify_anchor",
                "ref": ref,
                "expected_root": expected_root,
            },
        )
        if resp.get("error"):
            self._raise_for_remote_error(resp)
        return resp.get("verified") is True

    def get_transaction_status(self, tx_hash: str) -> dict[str, Any]:
        """Relay a real transaction status lookup to the bridge."""
        resp = self._request(
            "POST",
            BRIDGE_QUERY_PATH,
            {"op": "transaction_status", "ref": tx_hash},
        )
        if resp.get("error"):
            self._raise_for_remote_error(resp)
        return {
            "state": resp.get("state", TxState.UNKNOWN),
            "block_number": resp.get("block_number", ""),
            "network": resp.get("network", "fabric"),
            "tx_hash": tx_hash,
            "error": resp.get("error"),
        }


__all__ = ["RemoteFabricAdapter", "BRIDGE_HEALTH_PATH", "BRIDGE_ANCHOR_PATH", "BRIDGE_QUERY_PATH"]
