"""Merkle tree for evidence bundles.

Not a single flat hash: leaves are the canonical hashes of each evidence
object; internal nodes hash sorted child pairs; the root is what gets anchored.
Proof generation is supported so a single evidence object can be verified
against the anchored root.
"""
from __future__ import annotations

import math
from typing import Any

from ..core.crypto import combine_hashes, hash_payload


class MerkleTree:
    """Immutable Merkle tree over a list of leaf payloads.

    Leaves are hashed from the canonical payload. An empty tree has a
    deterministic empty root (sha256 of empty string).
    """

    def __init__(self, leaves: list[Any]) -> None:
        self._leaf_data: list[Any] = list(leaves)
        self._levels: list[list[str]] = []
        self._build()

    @property
    def leaf_count(self) -> int:
        return len(self._leaf_data)

    def _leaf_hashes(self) -> list[str]:
        return [hash_payload(leaf) for leaf in self._leaf_data]

    def _build(self) -> None:
        if not self._leaf_data:
            from ..core.crypto import hash_string

            self._levels = [[hash_string("")]]
            return
        current = self._leaf_hashes()
        self._levels = [current]
        while len(current) > 1:
            nxt: list[str] = []
            for i in range(0, len(current), 2):
                left = current[i]
                if i + 1 < len(current):
                    right = current[i + 1]
                else:
                    # duplicate the last node when count is odd
                    right = left
                nxt.append(combine_hashes(left, right))
            self._levels.append(nxt)
            current = nxt

    @property
    def root(self) -> str:
        return self._levels[-1][0]

    def leaf_hash(self, index: int) -> str:
        return self._levels[0][index]

    def leaves(self) -> list[str]:
        return list(self._levels[0])

    def proof_for(self, index: int) -> list[tuple[str, str]]:
        """Return a [(hash, side)] proof path for leaf [index].

        `side` is "left" when the sibling hash should be concatenated first,
        "right" otherwise (mirrors combine_hashes sorted-pair semantics).
        """
        if not (0 <= index < self.leaf_count):
            raise IndexError("leaf index out of range")
        proof: list[tuple[str, str]] = []
        idx = index
        for level in self._levels[:-1]:
            sibling_idx = idx ^ 1
            sibling = (
                level[sibling_idx]
                if sibling_idx < len(level)
                else level[idx]  # odd last node duplicates itself
            )
            proof.append((sibling, "right" if idx % 2 == 0 else "left"))
            idx //= 2
        return proof

    def verify_proof(
        self,
        leaf_payload: Any,
        proof: list[tuple[str, str]],
        root: str,
    ) -> bool:
        """Recompute the root from [leaf_payload] + [proof] and compare."""
        current = hash_payload(leaf_payload)
        for sibling, side in proof:
            if side == "right":
                current = combine_hashes(current, sibling)
            else:
                current = combine_hashes(sibling, current)
        return _eq(current, root)

    def merkle_payload(self, *, anchor_type: str = "evidence_bundle") -> dict[str, Any]:
        """Payload that gets anchored: identities + root, never raw PII."""
        return {
            "anchor_type": anchor_type,
            "leaf_count": self.leaf_count,
            "root_hash": self.root,
        }


def build_tree_from_payloads(payloads: list[Any]) -> MerkleTree:
    return MerkleTree(payloads)


def _eq(a: str, b: str) -> bool:
    import hmac

    return hmac.compare_digest(a.lower(), b.lower())
