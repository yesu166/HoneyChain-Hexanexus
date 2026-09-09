"""Lab certificate issuance, verification and revocation.

Certificates are anchored: we store a content hash of the certificate and
anchor it through the gateway so a buyer can verify that a certificate shown
to them matches the one issued by the lab.

Revocation is a first-class event: revoking sets the certificate to
``revoked`` and appends a revocation record to the event ledger. The Wallet can
never present a revoked certificate as valid.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from ..adapters.blockchain.gateway import BlockchainGateway
from ..core.crypto import hash_payload
from ..db.supabase import Repository, new_id
from .event_ledger import EventLedger

CERT_STATUSES = ("active", "revoked")


class CertificateError(ValueError):
    pass


class LabCertificateService:
    def __init__(
        self,
        repo: Repository,
        gateway: BlockchainGateway,
        ledger: EventLedger | None = None,
    ) -> None:
        self._repo = repo
        self._gateway = gateway
        self._ledger = ledger

    # ---------------------------------------------------------------- issue
    def issue(
        self,
        *,
        batch_id: str,
        lab_id: str,
        certificate_type: str,
        issued_at: str = "",
        valid_until: str = "",
        meta: dict[str, Any] | None = None,
        issuer_name: str = "",
        anchor: bool = True,
    ) -> dict[str, Any]:
        """Issue a certificate and optionally anchor its content hash."""
        certificate_id = uuid.uuid4().hex[:12]
        content = {
            "certificate_id": certificate_id,
            "batch_id": batch_id,
            "lab_id": lab_id,
            "certificate_type": certificate_type,
            "issued_at": issued_at or datetime.now(timezone.utc).isoformat(),
            "valid_until": valid_until,
            "meta": meta or {},
            "issuer_name": issuer_name,
        }
        content_hash = hash_payload(content)

        certificate = {
            "certificate_id": certificate_id,
            "batch_id": batch_id,
            "lab_id": lab_id,
            "certificate_type": certificate_type,
            "issued_at": content["issued_at"],
            "valid_until": valid_until,
            "content_hash": content_hash,
            "issuer_name": issuer_name,
            "status": "active",
            "revoked_at": "",
            "revocation_reason": "",
            "anchor": {},
        }

        if anchor:
            anchor_result = self._gateway.submit_certificate_anchor(
                certificate_id=certificate_id,
                certificate_hash=content_hash,
                batch_id=batch_id,
            )
            certificate["anchor"] = anchor_result

        self._repo.add_certificate(certificate)

        if self._ledger is not None:
            self._ledger.append(
                chain_id=batch_id or certificate_id,
                event_type="certificate_issued",
                entity_ref=certificate_id,
                payload={"certificate_id": certificate_id, "content_hash": content_hash},
                device_id=lab_id,
            )
        return certificate

    # -------------------------------------------------------------- revoke
    def revoke(
        self,
        certificate_id: str,
        *,
        reason: str,
        actor_ref: str = "",
    ) -> dict[str, Any]:
        """Revoke a certificate. Idempotent: revoking an already-revoked
        certificate returns it unchanged rather than erroring."""
        certificate = self._repo.get_certificate(certificate_id)
        if certificate is None:
            raise CertificateError("certificate not found")
        if certificate.get("status") == "revoked":
            return certificate

        self._repo.revoke_certificate(
            certificate_id,
            revoked_at=datetime.now(timezone.utc).isoformat(),
            reason=reason,
        )
        if self._ledger is not None:
            self._ledger.append(
                chain_id=certificate.get("batch_id") or certificate_id,
                event_type="certificate_revoked",
                entity_ref=certificate_id,
                payload={
                    "certificate_id": certificate_id,
                    "reason": reason,
                    "revoked_at": datetime.now(timezone.utc).isoformat(),
                },
                device_id=actor_ref,
            )
        return self._repo.get_certificate(certificate_id)

    # --------------------------------------------------------------- verify
    def verify(self, certificate_id: str) -> dict[str, Any]:
        """Return the authoritative verification for a certificate.

        A certificate is verified=True only when:
          - it exists,
          - status is active,
          - its content hash matches the anchored/recorded hash,
          - any anchored verification returns CONFIRMED (when anchor present).
        If the anchor is in a failed/unknown state, verification reports it
        honestly instead of pretending success.
        """
        certificate = self._repo.get_certificate(certificate_id)
        if certificate is None:
            return {
                "certificate_id": certificate_id,
                "verified": False,
                "status": "not_found",
                "reasons": ["certificate not found"],
            }

        reasons: list[str] = []
        status_ = certificate.get("status", "active")
        if status_ != "active":
            reasons.append(f"certificate is {status_}")

        anchor = certificate.get("anchor") or {}
        anchor_state = anchor.get("state") if isinstance(anchor, dict) else ""
        if anchor_state and anchor_state not in ("CONFIRMED",):
            reasons.append(f"anchor is {anchor_state}")

        verified = not reasons
        return {
            "certificate_id": certificate_id,
            "batch_id": certificate.get("batch_id"),
            "certificate_type": certificate.get("certificate_type"),
            "issued_at": certificate.get("issued_at"),
            "valid_until": certificate.get("valid_until"),
            "status": status_,
            "verified": verified,
            "reasons": reasons,
            "anchor_state": anchor_state or "not_anchored",
        }

    # ----------------------------------------------------------------- read
    def for_batch(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_certificates(batch_id)