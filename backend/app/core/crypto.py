"""Cryptographic primitives for HoneyChain.

Provides canonical JSON serialization, SHA-256 hashing, a hash-chain helper,
and ECDSA P-256 sign/verify using the `cryptography` library.

Truth notes:
- Signatures attest *"this registered key signed this event"*. They do not
  prove a physical sensor was honest. That distinction is documented in the
  project docs.
- Keys are held in memory/local credential storage; they are never logged and
  never serialized into any API response.
"""
from __future__ import annotations

import base64
import hashlib
import json
from enum import Enum
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


class SigningAlgo(str, Enum):
    """Supported signing algorithms.

    P-256 is the preferred signature scheme where platform support is
    practical (secp256r1 / NIST P-256).
    """
    ECDSA_P256 = "ECDSA_P256"


# ---------------------------------------------------------------------------
# Canonical serialization
# ---------------------------------------------------------------------------

def _normalize_number(value: Any) -> str:
    """Render any int/float (non-bool) in a canonical textual form so that
    5 and 5.0 hash identically. True/False are handled separately."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    # float: drop a trailing '.0' so 5.0 == 5, but keep precision elsewhere
    text = format(value, ".15g")
    if text.endswith(".0"):
        return text[:-2]
    return text


def canonical_json(value: Any) -> str:
    """Return a canonical JSON string for [value].

    Rules (recursive):
      - dict keys sorted lexicographically
      - null dict values omitted
      - numbers normalized so int(5) and float(5.0) hash identically
      - booleans kept distinct from numbers
      - list order preserved (order is meaningful)
      - datetimes rendered as ISO-8601 UTC strings
    """
    return json.dumps(
        _canonicalize(value),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )


def _canonicalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: _canonicalize(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [_canonicalize(v) for v in value]
    if isinstance(value, tuple):
        return [_canonicalize(v) for v in value]
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        # normalize to a string token so 5 and 5.0 collide; still JSON-quoted
        return _normalize_number(value)
    if hasattr(value, "isoformat"):  # datetime / date
        try:
            return value.isoformat()
        except Exception:
            return str(value)
    return value


# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_string(text: str) -> str:
    return sha256_bytes(text.encode("utf-8"))


def hash_payload(payload: Any) -> str:
    """canonical_json(payload) -> sha256 hex."""
    return hash_string(canonical_json(payload))


def hash_hex_bytes(hex_str: str) -> str:
    try:
        return sha256_bytes(bytes.fromhex(hex_str))
    except ValueError:
        return hash_string(hex_str)


def combine_hashes(left: str, right: str) -> str:
    """sha256 of the concat of two hex hashes (sorted-pair convention)."""
    first, second = sorted((left.lower(), right.lower()))
    return sha256_bytes((first + second).encode("ascii"))


# ---------------------------------------------------------------------------
# Signing keys
# ---------------------------------------------------------------------------

def generate_signing_key() -> ec.EllipticCurvePrivateKey:
    """Generate an ECDSA P-256 private key for device/actor attribution."""
    return ec.generate_private_key(ec.SECP256R1())


def serialize_private_key_pem(key: ec.EllipticCurvePrivateKey) -> str:
    return key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")


def serialize_public_key_pem(key: ec.EllipticCurvePublicKey) -> str:
    return key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")


def load_private_key_pem(pem: str) -> ec.EllipticCurvePrivateKey:
    return serialization.load_pem_private_key(
        pem.encode("utf-8"), password=None
    )


def public_key_hex(key: ec.EllipticCurvePublicKey) -> str:
    """Stable short identifier for a public key (fingerprint)."""
    return sha256_bytes(key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ))[:40]


def sign_payload(payload: Any, private_key: ec.EllipticCurvePrivateKey) -> str:
    """Sign the canonical payload with ECDSA P-256.

    DER-encoded ECDSA signature (r||s within ASN.1). Returns base64.
    """
    canonical = canonical_json(payload).encode("utf-8")
    der = private_key.sign(canonical, ec.ECDSA(hashes.SHA256()))
    return base64.b64encode(der).decode("ascii")


def verify_signature(
    payload: Any,
    signature_b64: str,
    public_key: ec.EllipticCurvePublicKey,
) -> bool:
    """Return True if [signature_b64] is a valid ECDSA P-256 sig over the
    canonical payload."""
    try:
        der = base64.b64decode(signature_b64.encode("ascii"))
        canonical = canonical_json(payload).encode("utf-8")
        public_key.verify(der, canonical, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError, TypeError):
        return False


def verify_signature_der(
    payload: Any,
    der: bytes,
    public_key: ec.EllipticCurvePublicKey,
) -> bool:
    try:
        canonical = canonical_json(payload).encode("utf-8")
        public_key.verify(der, canonical, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError, TypeError):
        return False
