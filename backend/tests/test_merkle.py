from __future__ import annotations

from app.services.merkle import MerkleTree


def test_empty_tree_deterministic_root():
    t1 = MerkleTree([])
    t2 = MerkleTree([])
    assert t1.root == t2.root
    assert len(t1.root) == 64


def test_single_leaf():
    t = MerkleTree([{"id": "A", "v": 1}])
    assert t.root == t.leaves()[0]


def test_root_changes_with_any_leaf():
    t1 = MerkleTree([{"id": "A", "v": 1}, {"id": "B", "v": 2}])
    t2 = MerkleTree([{"id": "A", "v": 1}, {"id": "B", "v": 99}])
    assert t1.root != t2.root


def test_proof_verifies_and_rejects():
    leaves = [{"id": "A", "v": 1}, {"id": "B", "v": 2}, {"id": "C", "v": 3}]
    t = MerkleTree(leaves)
    proof = t.proof_for(1)
    assert t.verify_proof(leaves[1], proof, t.root)
    assert not t.verify_proof({"id": "B", "v": 99}, proof, t.root)
    assert not t.verify_proof(leaves[1], proof, "0" * 64)


def test_proof_for_every_leaf():
    leaves = [{"id": f"N{i}", "v": i} for i in range(7)]
    t = MerkleTree(leaves)
    for i in range(len(leaves)):
        assert t.verify_proof(leaves[i], t.proof_for(i), t.root)


def test_merkle_payload_shape():
    leaves = [{"id": "A"}, {"id": "B"}]
    t = MerkleTree(leaves)
    payload = t.merkle_payload()
    assert payload["leaf_count"] == 2
    assert payload["root_hash"] == t.root
    assert payload["anchor_type"] == "evidence_bundle"