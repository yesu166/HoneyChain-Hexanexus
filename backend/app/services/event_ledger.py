"""Offline-first, append-only, hash-chained event ledger.

Every describe-everything event (harvest, custody, certificate, state
transition, tamper report) is appended to a hash chain: each event carries the
hash of the previous event, so any reordering, insertion or deletion breaks a
link. The chain head can be anchored to the blockchain via the gateway.

Offline reality: a phone appends locally. Two devices appending at the same
head produces a fork. Truth rule: a fork is NEVER silently collapsed — both
branches are preserved and a ``fork`` marker event records the divergence, so
a later reconciliation can reason about it instead of losing a record.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Any

from ..core.crypto import canonical_json, hash_payload
from ..db.supabase import Repository


def _now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


@dataclass
class LedgerEvent:
    chain_id: str
    index: int
    event_type: str
    entity_ref: str
    payload: dict[str, Any]
    prev_hash: str = ""
    hash: str = ""
    ts: str = field(default_factory=_now)
    device_id: str = ""
    fork_of: str = ""  # blank except when this event diverges from a head

    def compute_hash(self) -> str:
        return hash_payload(
            {
                "chain_id": self.chain_id,
                "index": self.index,
                "event_type": self.event_type,
                "entity_ref": self.entity_ref,
                "payload": self.payload,
                "prev_hash": self.prev_hash,
                "ts": self.ts,
                "fork_of": self.fork_of,
            }
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "chain_id": self.chain_id,
            "index": self.index,
            "event_type": self.event_type,
            "entity_ref": self.entity_ref,
            "payload": self.payload,
            "prev_hash": self.prev_hash,
            "hash": self.hash,
            "ts": self.ts,
            "device_id": self.device_id,
            "fork_of": self.fork_of,
        }


class LedgerIntegrityError(ValueError):
    """Raised when the chain is tampered or a fork is being hidden."""


class EventLedger:
    """Hash-chained event ledger.

    The repository is the durable backend; the chain checkpoint is derived
    from the stored events so it can be re-verified at any time. In-memory
    chains (offline phone) just use an in-memory store until synced.
    """

    def __init__(self, repo: Repository | None = None) -> None:
        self._repo = repo
        self._memory: dict[str, list[LedgerEvent]] = {}

    # ------------------------------------------------------------- private
    def _storage(self, chain_id: str) -> list[LedgerEvent]:
        if self._repo is None:
            return self._memory.setdefault(chain_id, [])
        rows = []
        for r in self._repo.list_ledger_events(chain_id):
            clean = {k: v for k, v in r.items() if k != "id"}
            rows.append(LedgerEvent(**clean))
        return rows

    def _persist(self, event: LedgerEvent) -> None:
        if self._repo is None:
            self._memory.setdefault(event.chain_id, []).append(event)
            return
        self._repo.add_ledger_event(event.to_dict())

    # ---------------------------------------------------------------- heads
    def chain_heads(self, chain_id: str) -> list[LedgerEvent]:
        """All events that have no successor — normally one, but a fork has
        several. Both are preserved by design."""
        events = self._storage(chain_id)
        children: set[str] = set()
        for event in events:
            if event.fork_of or not event.hash:
                continue
            children.add(event.prev_hash)
        return [e for e in events if e.hash and e.hash not in children]

    def head_hash(self, chain_id: str) -> str:
        heads = self.chain_heads(chain_id)
        if not heads:
            return hash_payload({"empty": chain_id})
        return sorted(hash_.hash for hash_ in heads)[-1]

    # --------------------------------------------------------------- append
    def append(
        self,
        *,
        chain_id: str,
        event_type: str,
        entity_ref: str,
        payload: dict[str, Any],
        device_id: str = "",
        prev_hash: str | None = None,
        ts: str | None = None,
    ) -> LedgerEvent:
        """Append a new event to [chain_id].

        [prev_hash] defaults to the current head hash. If the caller explicitly
        names a different [prev_hash] the ledger creates a fork (both branches
        preserved) and records a ``fork`` marker so reconciliation is explicit.
        """
        events = self._storage(chain_id)
        if prev_hash is None:
            prev_hash = self.head_hash(chain_id)

        base_index = max((e.index for e in events if e.hash == prev_hash), default=-1)
        index = base_index + 1

        event = LedgerEvent(
            chain_id=chain_id,
            index=index,
            event_type=event_type,
            entity_ref=entity_ref,
            payload=payload,
            prev_hash=prev_hash,
            ts=ts or _now(),
            device_id=device_id,
        )
        # A fork: two events share a prev_hash but diverge. Preserve both.
        siblings = [e for e in events if e.hash and e.prev_hash == prev_hash and e.hash != event.compute_hash()]
        if siblings:
            event.fork_of = siblings[0].hash
            self._persist(
                LedgerEvent(
                    chain_id=chain_id,
                    index=index,
                    event_type="fork",
                    entity_ref=chain_id,
                    payload={
                        "a": event.compute_hash(),
                        "b": siblings[0].hash,
                    },
                    prev_hash=prev_hash,
                    ts=ts or _now(),
                    device_id="",
                )
            )
        event.hash = event.compute_hash()
        self._persist(event)
        return event

    # ------------------------------------------------------------- verify
    def verify_chain(self, chain_id: str) -> dict[str, Any]:
        """Recompute every link; report any tamper. Returns a chain report.

        A corrupted link raises nothing here; it is reported in the result so
        the caller can decide (e.g. surface a tamper report).
        """
        events = sorted(self._storage(chain_id), key=lambda e: (e.index, e.ts, e.hash))
        issues: list[dict[str, Any]] = []
        seen_link = False
        for event in events:
            if not event.hash:
                continue
            recomputed = event.compute_hash()
            if recomputed != event.hash:
                issues.append(
                    {
                        "index": event.index,
                        "event_type": event.event_type,
                        "expected_hash": recomputed,
                        "stored_hash": event.hash,
                        "kind": "hash_mismatch",
                    }
                )
            if seen_link and not event.fork_of:
                parent = next((e for e in events if e.hash == event.prev_hash), None)
                if parent is None or parent.hash != event.prev_hash:
                    issues.append(
                        {
                            "index": event.index,
                            "kind": "broken_link",
                            "prev_hash": event.prev_hash,
                        }
                    )
            seen_link = True
        return {
            "chain_id": chain_id,
            "event_count": len(events),
            "head_hash": self.head_hash(chain_id),
            "integrity_ok": not issues,
            "issues": issues,
        }

    def tamper_chain(self, chain_id: str, index: int, *, repo_override: Repository | None = None) -> None:
        """DEMO/ADMIN ONLY: support tamper-evidence demo.

        Rewrites stored payload of the event at [index] so the hash chain flag
        is tripped. This modifies the durable store on purpose; guarded by
        DEMO_MODE at the route layer.
        """
        if self._repo is None:
            events = self._memory.setdefault(chain_id, [])
        else:
            events = []
            for r in self._repo.list_ledger_events(chain_id):
                clean = {k: v for k, v in r.items() if k != "id"}
                events.append(LedgerEvent(**clean))
        target = next((e for e in events if e.index == index), None)
        if target is None:
            raise ValueError(f"no event at index {index} in chain {chain_id}")
        target.payload["tampered"] = True
        if self._repo is None:
            return
        self._persist(target)


def build_ledger(repo: Repository | None, *, chain_id: str = "honeychain") -> EventLedger:
    return EventLedger(repo)