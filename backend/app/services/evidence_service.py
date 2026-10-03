"""Harvest Evidence Bundle (HEB): tamper-evidence for a harvest or batch.

A bundle collects images, GPS coordinates, timestamps, the operator and free
notes. It builds:

  1. a canonical hash for every evidence object (photos are referenced by
     content hash, never stored/uploaded here),
  2. a Merkle tree over those hashes,
  3. a root hash anchored via the BlockchainGateway,
  4. per-evidence Merkle proofs so a single object can be verified against the
     anchored root later.

Truth rules: we never claim a proof is valid without recomputing it, and we
never claim an anchor exists on a ledger we cannot reach — the returned anchor
state reflects the gateway's honest transaction state.
"""
from __future__ import annotations

import json
import uuid
from typing import Any

from ..adapters.blockchain.gateway import BlockchainGateway
from ..core.crypto import canonical_json, hash_payload
from ..db.supabase import Repository, new_id
from .merkle import MerkleTree

EVIDENCE_KINDS = (
    "photo", "gps", "timestamp", "operator_note", "lab_sheet", "other",
    "telemetry_reference",
)


class BundleNotFound(ValueError):
    pass


class HarvestEvidenceService:
    def __init__(self, repo: Repository | None, gateway: BlockchainGateway) -> None:
        self._repo = repo
        self._gateway = gateway

    # ---------------------------------------------------------------- build
    def create_bundle(
        self,
        *,
        entity_type: str,
        entity_ref: str,
        evidence: list[dict[str, Any]],
        operator: str = "",
        device_id: str = "",
        anchor: bool = True,
        include_telemetry: bool = False,
        telemetry_limit: int = 50,
        telemetry_hive_id: str = "",
    ) -> dict[str, Any]:
        """Package [evidence] into a bundle and (optionally) anchor its root.

        include_telemetry appends a "telemetry_reference" leaf that commits to
        the pre-harvest telemetry of the hive as *references* (event_id,
        sequence, payload_hash, timestamp, hive_id) — never raw payload copies —
        so the anchored Merkle root binds the readings that preceded the
        harvest."""
        if entity_type not in ("harvest", "batch", "assertion"):
            raise ValueError("entity_type must be 'harvest', 'batch' or 'assertion'")
        if entity_ref and not evidence:
            raise ValueError("evidence list must not be empty")
        for item in evidence:
            if item.get("kind") not in EVIDENCE_KINDS:
                raise ValueError(f"unknown evidence kind: {item.get('kind')}")

        evidence = list(evidence)
        if include_telemetry:
            evidence.append(self._telemetry_reference_evidence(
                entity_type, entity_ref, telemetry_hive_id, telemetry_limit
            ))

        # 1. normalize each evidence object + content hash
        normalized: list[dict[str, Any]] = []
        for item in evidence:
            payload = {
                "kind": item.get("kind", "other"),
                "value": item.get("value", ""),
                "captured_at": item.get("captured_at", ""),
                "latitude": item.get("latitude"),
                "longitude": item.get("longitude"),
                "content_hash": item.get("content_hash", ""),
            }
            normalized.append(
                {
                    "evidence_id": new_id(),
                    "payload": payload,
                    "hash": hash_payload(payload),
                }
            )

        # 2. Merkle tree over the hashed objects
        tree = MerkleTree([e["hash"] for e in normalized])
        root = tree.root

        bundle_id = uuid.uuid4().hex[:12]
        bundle: dict[str, Any] = {
            "bundle_id": bundle_id,
            "entity_type": entity_type,
            "entity_ref": entity_ref,
            "operator": operator,
            "device_id": device_id,
            "created_at": None,
            "evidence": normalized,
            "leaf_count": tree.leaf_count,
            "root_hash": root,
            "anchor": {},
        }
        from datetime import datetime, timezone

        bundle["created_at"] = datetime.now(timezone.utc).isoformat()

        if anchor:
            # The deployed chaincode's anchorMerkleRoot calls
            # getStateOrThrow(ctx, "BATCH:{batchId}") before it writes, so an
            # anchor can only be committed against a batch that already exists
            # on the ledger.
            #
            # entity_type="batch" passes the batch id directly. A harvest used to
            # send an empty string, which produced batchId="" -> the chaincode
            # threw NOT_FOUND: BATCH: -> Fabric refused endorsement with
            # "502 ... 10 ABORTED: failed to endorse transaction" -> the gateway
            # marked the tx UNKNOWN -> the bundle came back HTTP 200 with
            # anchor.state != CONFIRMED, which is exactly the "Saved — blockchain
            # anchor pending" message the app showed.
            #
            # A harvest id is itself a uuid (the Supabase harvest row id), which
            # is the shape _ensure_batch_on_ledger recognises: it probes getBatch,
            # and only on NOT_FOUND issues createBatch before the anchor. So
            # anchoring the harvest's own id makes the Merkle root commit to a
            # real ledger container instead of failing endorsement. Non-uuid refs
            # (e.g. an assertion ref) stay as-is and remain honestly UNKNOWN.
            anchor_target = entity_ref if entity_type in ("batch", "harvest") else ""
            result = self._gateway.submit_anchor(
                batch_id=anchor_target,
                evidence_root=root,
                anchor_type=f"{entity_type}_evidence_bundle",
                organization_ref=operator,
            )
            bundle["anchor"] = result
            if self._repo is not None and entity_type == "batch" and result:
                anchored = result.get("state") == "CONFIRMED"
                self._repo.add_anchor(
                    {
                        "batch_id": entity_ref,
                        "data_hash": root,
                        "tx_hash": result.get("tx_hash", ""),
                        "network": result.get("network", ""),
                        "chain_status": "anchored" if anchored else "pending",
                        "anchored_at": result.get("created_at"),
                    }
                )

        if self._repo is not None:
            self._repo.add_evidence_bundle(bundle)
        return bundle

    def _telemetry_reference_evidence(
        self, entity_type: str, entity_ref: str, hive_id: str, limit: int
    ) -> dict[str, Any]:
        """Build a telemetry_reference evidence item: references + commitment.

        Only reference fields are committed (never the raw payload values), so
        the Merkle leaf stays compact while binding which readings preceded the
        harvest. Any amendment of a reference flips the leaf hash.
        """
        if self._repo is None:
            raise ValueError("telemetry references require a repository")
        if not hive_id:
            if entity_type == "harvest":
                harvest = self._repo.get_harvest(entity_ref) if hasattr(self._repo, "get_harvest") else None
                hive_id = (harvest or {}).get("hive_id", "")
            else:
                batch = self._repo.get_batch(entity_ref) if hasattr(self._repo, "get_batch") else None
                hive_id = (batch or {}).get("hive_id", "")
        if not hive_id:
            raise ValueError("could not resolve hive for telemetry references")

        rows = self._repo.telemetry_events_for_hive(hive_id, limit=limit)
        if not rows:
            raise ValueError(f"no telemetry found for hive {hive_id}")

        references = [
            {
                "event_id": r["event_id"],
                "device_id": r["device_id"],
                "sequence": r["sequence"],
                "timestamp": r["timestamp"],
                "payload_hash": r["payload_hash"],
                "hive_id": r.get("hive_id", hive_id),
            }
            for r in rows
        ]
        commitment = hash_payload({"references": references})
        from datetime import datetime, timezone

        return {
            "kind": "telemetry_reference",
            "value": json.dumps(
                {
                    "hive_id": hive_id,
                    "count": len(references),
                    "commitment": commitment,
                    "references": references,
                },
                sort_keys=True,
            ),
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "latitude": None,
            "longitude": None,
            "content_hash": "",
        }

    # ---------------------------------------------------------------- verify
    def _leaf_for(self, e: dict[str, Any]) -> str:
        """Recompute a leaf from the stored payload, not the claimed hash.

        This is what makes tamper evidence real: if anyone changed the payload,
        the recomputed leaf no longer matches the anchored root."""
        if "payload" in e and e.get("payload") is not None:
            return hash_payload(e["payload"])
        return e.get("hash", "")

    def verify_bundle(self, bundle_id: str) -> dict[str, Any]:
        """Recompute the Merkle root from the stored payloads and confirm the
        anchor status.

        Returns evidence-level tamper results plus the honest anchor state.
        """
        bundle = self._find_bundle(bundle_id)
        if bundle is None:
            raise BundleNotFound(bundle_id)

        tree = MerkleTree([self._leaf_for(e) for e in bundle["evidence"]])
        recomputed_root = tree.root
        tampered = recomputed_root != bundle.get("root_hash")

        anchor = bundle.get("anchor") or {}
        anchor_state = (
            anchor.get("state")
            if isinstance(anchor, dict) and anchor.get("state")
            else self._gateway.verify_anchor(bundle.get("root_hash", ""))
        )

        # For a real (e.g. Fabric) ledger we can live-verify the bundle's own
        # commitment: the chaincode compares this exact recomputed root against
        # the batch's current merkleRoot. Never trust the stored anchor copy
        # alone on a live network.
        anchor_live = None
        if self._gateway.ledger_name == "fabric" and bundle.get("entity_ref"):
            try:
                anchor_live = self._gateway.verify_anchor(
                    bundle["entity_ref"], recomputed_root
                )
            except Exception:
                anchor_live = None
            if anchor_live is not None:
                anchor_state = "CONFIRMED" if anchor_live else "NOT_VERIFIED"

        return {
            "bundle_id": bundle_id,
            "entity_type": bundle.get("entity_type"),
            "entity_ref": bundle.get("entity_ref"),
            "root_hash": bundle.get("root_hash"),
            "recomputed_root": recomputed_root,
            "evidence_intact": not tampered,
            "anchor_state": anchor_state,
            "anchored": anchor_state == "CONFIRMED",
            "anchor_live": anchor_live,
            "evidence_count": len(bundle.get("evidence", [])),
        }

    def evidence_proof(self, bundle_id: str, evidence_id: str) -> dict[str, Any]:
        """Return the Merkle proof for a single evidence object."""
        bundle = self._find_bundle(bundle_id)
        if bundle is None:
            raise BundleNotFound(bundle_id)
        evidence = [e for e in bundle["evidence"] if e["evidence_id"] == evidence_id]
        if not evidence:
            raise ValueError(f"no evidence {evidence_id} in bundle {bundle_id}")
        idx = next(
            i for i, e in enumerate(bundle["evidence"]) if e["evidence_id"] == evidence_id
        )
        tree = MerkleTree([e["hash"] for e in bundle["evidence"]])
        return {
            "bundle_id": bundle_id,
            "evidence_id": evidence_id,
            "leaf_hash": evidence[0]["hash"],
            "root_hash": bundle["root_hash"],
            "proof": [
                {"hash": h, "side": side} for h, side in tree.proof_for(idx)
            ],
        }

    def verify_evidence_proof(
        self, *, leaf_hash: str, proof: list[dict[str, Any]], root_hash: str
    ) -> dict[str, Any]:
        """Verify a single leaf against an anchored root through its proof."""
        tree = MerkleTree([leaf_hash])
        ok = tree.verify_proof(
            leaf_hash,
            [(p["hash"], p["side"]) for p in proof],
            root_hash,
        )
        return {
            "root_hash": root_hash,
            "leaf_hash": leaf_hash,
            "proof_valid": ok,
            "root_verified": self._gateway.verify_anchor(root_hash),
        }

    # ----------------------------------------------------------------- read
    def get_bundle(self, bundle_id: str) -> dict[str, Any] | None:
        return self._find_bundle(bundle_id)

    def _find_bundle(self, bundle_id: str) -> dict[str, Any] | None:
        if self._repo is None:
            return None
        bundle = self._repo.get_evidence_bundle(bundle_id)
        if bundle is None:
            # demo/reseeding - empty
            return None
        return bundle


def build_evidence_service(repo, gateway) -> HarvestEvidenceService:
    return HarvestEvidenceService(repo, gateway)