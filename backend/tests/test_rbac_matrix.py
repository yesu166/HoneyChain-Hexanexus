from __future__ import annotations

import pytest

from app.core.rbac import (
    ACTIONS,
    PLATFORM_ORGANIZATION_ACTIONS,
    PERMISSION_MATRIX,
    has_permission,
    in_scope,
    scope_label,
)
from app.core.security import CurrentUser


def test_admin_has_every_domain_action():
    for action in ACTIONS - PLATFORM_ORGANIZATION_ACTIONS:
        assert has_permission("admin", action)


def test_admin_excluded_from_platform_org_oversight():
    for action in PLATFORM_ORGANIZATION_ACTIONS:
        assert not has_permission("admin", action)


def test_platform_oversight_has_org_oversight_only():
    for action in PLATFORM_ORGANIZATION_ACTIONS:
        assert has_permission("platform_oversight", action)
    assert has_permission("platform_oversight", "platform.stats")
    assert not has_permission("platform_oversight", "batch.create")
    assert not has_permission("platform_oversight", "harvest.create")
    assert not has_permission("platform_oversight", "demo.tamper")


def test_non_oversight_roles_denied_org_oversight():
    for role in ("beekeeper", "fpo", "lab", "processor", "buyer", "institution"):
        for action in PLATFORM_ORGANIZATION_ACTIONS:
            assert not has_permission(role, action)


def test_buyer_read_only():
    assert has_permission("buyer", "batch.read")
    assert has_permission("buyer", "passport.read")
    assert not has_permission("buyer", "batch.transfer_custody")
    assert not has_permission("buyer", "demo.tamper")


def test_demo_tamper_admin_only():
    assert has_permission("admin", "demo.tamper")
    assert not has_permission("beekeeper", "demo.tamper")
    assert not has_permission("fpo", "demo.tamper")
    assert not has_permission("lab", "demo.tamper")


def test_lab_certificate_permissions():
    assert has_permission("lab", "lab.issue_certificate")
    assert has_permission("lab", "lab.revoke_certificate")
    assert not has_permission("beekeeper", "lab.issue_certificate")


def test_scope_rules():
    beekeeper = CurrentUser(user_id="u1", role="beekeeper", org_id="ORG-A")
    assert in_scope(beekeeper, owner_user_id="u1")
    assert not in_scope(beekeeper, owner_user_id="u2")
    admin = CurrentUser(user_id="a1", role="admin", org_id="")
    assert in_scope(admin, owner_user_id="anyone")


def test_unknown_role_denied():
    assert not has_permission("ghost", "batch.read")


def test_scopes_labeled():
    assert scope_label("institution") == "any"
    assert scope_label("beekeeper") == "read_own"