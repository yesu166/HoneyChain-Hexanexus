from __future__ import annotations

from app.core.crypto import (
    canonical_json,
    combine_hashes,
    generate_signing_key,
    hash_payload,
    hash_string,
    public_key_hex,
    serialize_private_key_pem,
    serialize_public_key_pem,
    sign_payload,
    verify_signature,
)


def test_canonical_order_insensitive():
    assert canonical_json({"b": 2, "a": 1}) == canonical_json({"a": 1, "b": 2})


def test_canonical_number_normalization():
    assert canonical_json({"q": 5}) == canonical_json({"q": 5.0})
    assert hash_payload({"q": 5}) == hash_payload({"q": 5.0})


def test_canonical_boolean_distinct_from_number():
    assert canonical_json({"v": True}) != canonical_json({"v": 1})


def test_canonical_null_omitted():
    assert canonical_json({"a": 1, "b": None}) == canonical_json({"a": 1})


def test_hash_is_sha256_hex():
    assert len(hash_string("x")) == 64
    import hashlib

    assert hash_string("x") == hashlib.sha256(b"x").hexdigest()


def test_combine_hashes_is_sort_stable():
    h1, h2 = "a" * 64, "b" * 64
    assert combine_hashes(h1, h2) == combine_hashes(h2, h1)


def test_sign_and_verify_roundtrip():
    key = generate_signing_key()
    pub = key.public_key()
    payload = {"entity_id": "E-1", "kind": "gps", "lat": 11.5}
    sig = sign_payload(payload, key)
    assert verify_signature(payload, sig, pub)


def test_signature_rejects_tampered_payload():
    key = generate_signing_key()
    sig = sign_payload({"entity_id": "E-1", "qty": 3.0}, key)
    assert not verify_signature({"entity_id": "E-1", "qty": 99.0}, sig, key.public_key())


def test_serialize_keys_roundtrip():
    key = generate_signing_key()
    pem = serialize_private_key_pem(key)
    from app.core.crypto import load_private_key_pem

    loaded = load_private_key_pem(pem)
    sig = sign_payload({"x": 1}, loaded)
    assert verify_signature({"x": 1}, sig, key.public_key())


def test_public_key_fingerprint_is_short_hex():
    key = generate_signing_key()
    pub = serialize_public_key_pem(key.public_key())
    assert "BEGIN PUBLIC KEY" in pub
    assert len(public_key_hex(key.public_key())) == 40