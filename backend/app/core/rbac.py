"""RBAC permission matrix for HoneyChain.

Roles: beekeeper, fpo, lab, admin, processor, buyer, institution,
platform_oversight.
Every action is granted role-by-action. The matrix lives server-side; the API
layer (require_permission) rejects anything not explicitly granted.

Scope conditions (org_id/user_id matching) are enforced by the services; the
matrix decides WHAT a role may attempt, not WHOSE data it may touch.
"""
from __future__ import annotations

from typing import Any

from fastapi import Depends, HTTPException, status

from ..core.security import CurrentUser, get_current_user

# Define the canonical permission set.
ACTIONS = {
    # harvest capture + evidence
    "harvest.create",
    "harvest.attach_evidence",
    "harvest.read",
    # hives and readings
    "hive.create",
    "reading.submit",
    # batches, custody, lineage
    "batch.create",
    "batch.split",
    "batch.merge",
    "batch.transfer_custody",
    "batch.read",
    "batch.update_status",
    # lab
    "lab.test_request",
    "lab.test_result",
    "lab.issue_certificate",
    "lab.revoke_certificate",
    "lab.read",
    # passport / verification
    "passport.read",
    "passport.verify_public",
    # IoT devices + telemetry
    "iot.device.read",
    "iot.device.create",
    "iot.telemetry.ingest",
    "iot.simulator.control",
    "notification.read",
    # org dashboards / platform stats
    "org.dashboard",
    "platform.stats",
    # platform organization oversight
    "organization.create",
    "organization.update",
    "organization.activate",
    "organization.suspend",
    "organization.deactivate",
    "organization.onboard_admin",
    "organization.revoke_admin",
    "organization.view_all",
    # platform membership oversight
    "membership.assign",
    "membership.revoke",
    "membership.view",
    "member.suspend",
    "member.reinstate",
    # admin / demo
    "admin.audit",
    "demo.tamper",
    "demo.restore",
    # sync
    "sync.push",
    # evidence-linked assertions + reconciliation + provenance impact
    "assertion.create",
    "assertion.read",
    "assertion.reconcile",
    "provenance.impact.read",
}

# Platform-oversight actions: organization + membership lifecycle. These are
# deliberately NOT part of the admin role — an administrator manages domain
# data, while organization/membership governance is reserved for the platform.
PLATFORM_ORGANIZATION_ACTIONS = {
    "organization.create",
    "organization.update",
    "organization.activate",
    "organization.suspend",
    "organization.deactivate",
    "organization.onboard_admin",
    "organization.revoke_admin",
    "organization.view_all",
    "membership.assign",
    "membership.revoke",
    "membership.view",
    "member.suspend",
    "member.reinstate",
}

# role -> permitted action, plus optional scope rule:
# ("read_own" | "read_org" | "any") — 'any' means admin/institution override.
PERMISSION_MATRIX: dict[str, dict[str, set[str]]] = {
    "beekeeper": {
        "allowed": {
            "harvest.create",
            "harvest.attach_evidence",
            "harvest.read",
            "hive.create",
            "reading.submit",
            "batch.create",
            "batch.split",
            "batch.merge",
            "batch.transfer_custody",
            "batch.read",
            "iot.device.read",
            "notification.read",
            "sync.push",
            "assertion.create",
            "assertion.read",
        },
        "scope": "read_own",
    },
    "fpo": {
        "allowed": {
            "harvest.read",
            "hive.create",
            "reading.submit",
            "batch.create",
            "batch.split",
            "batch.merge",
            "batch.transfer_custody",
            "batch.read",
            "batch.update_status",
            "lab.test_request",
            "lab.read",
            "passport.read",
            "iot.device.read",
            "iot.telemetry.ingest",
            "notification.read",
            "sync.push",
            "org.dashboard",
            "assertion.create",
            "assertion.read",
            "assertion.reconcile",
            "provenance.impact.read",
        },
        "scope": "read_org",
    },
    "lab": {
        "allowed": {
            "lab.test_request",
            "lab.test_result",
            "lab.issue_certificate",
            "lab.revoke_certificate",
            "lab.read",
            "batch.read",
            "harvest.read",
            "passport.read",
            "assertion.create",
            "assertion.read",
        },
        "scope": "any",
    },
    "processor": {
        "allowed": {
            "batch.create",
            "batch.split",
            "batch.merge",
            "batch.transfer_custody",
            "batch.update_status",
            "batch.read",
            "harvest.read",
            "passport.read",
            "iot.device.read",
            "notification.read",
            "sync.push",
            "org.dashboard",
            "assertion.create",
            "assertion.read",
            "assertion.reconcile",
            "provenance.impact.read",
        },
        "scope": "read_org",
    },
    "buyer": {
        "allowed": {
            "batch.read",
            "harvest.read",
            "passport.read",
            "assertion.read",
            # A buyer is an active participant in market linkage: it requests
            # lots and needs to see the seller's accept / reject / fulfil
            # decisions. `notification.read` is scoped to the caller's own
            # organization rows, so this cannot expose another org's inbox.
            "notification.read",
        },
        "scope": "any",
    },
    "institution": {
        "allowed": {
            "batch.read",
            "harvest.read",
            "passport.read",
            "admin.audit",
            "iot.device.read",
            "org.dashboard",
            "platform.stats",
            "assertion.read",
            "provenance.impact.read",
        },
        "scope": "any",
    },
    "platform_oversight": {
        "allowed": PLATFORM_ORGANIZATION_ACTIONS
        | {
            "platform.stats",
            "admin.audit",
            "org.dashboard",
            "assertion.read",
            "provenance.impact.read",
        },
        "scope": "any",
    },
    "admin": {
        # Administrator manages domain data and reads the immutable governance
        # audit trail. Organization + membership governance (including the
        # read-only platform views) is reserved for platform_oversight, so the
        # matrix is exactly "all domain actions, no platform governance".
        "allowed": (set(ACTIONS) - PLATFORM_ORGANIZATION_ACTIONS),
        "scope": "any",
    },
    "retailer": {
        "allowed": {
            "batch.read",
            "harvest.read",
            "passport.read",
            "assertion.read",
            "provenance.impact.read",
            "org.dashboard",
            "notification.read",
        },
        "scope": "read_org",
    },
}


def has_permission(role: str, action: str) -> bool:
    return action in PERMISSION_MATRIX.get(role, {}).get("allowed", set())


def scope_label(role: str) -> str:
    return PERMISSION_MATRIX.get(role, {}).get("scope", "none")


def require_permission(action: str):
    """Dependency factory: require the authenticated user to hold [action].

    Multi-role: user has access if ANY of their roles has the permission.
    """

    def _check(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if not any(has_permission(r, action) for r in user.roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"None of your roles {user.roles} are permitted to {action}",
            )
        return user

    return _check


# ---------------------------------------------------------------------------
# Scope enforcement helper (service layer)
# ---------------------------------------------------------------------------

def in_scope(user: CurrentUser, *, owner_org_id: str = "", owner_user_id: str = "") -> bool:
    # Check if any role has "any" scope or is admin/institution/platform_oversight
    for r in user.roles:
        if r in ("admin", "institution", "platform_oversight"):
            return True
        if scope_label(r) == "any":
            return True
    if owner_user_id and owner_user_id == user.user_id:
        return True
    if owner_org_id and owner_org_id == user.org_id:
        return True
    return False