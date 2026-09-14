from __future__ import annotations

from typing import Any

from ..db.supabase import Repository

_GOVERNANCE_ACTIONS = {
    "organization.create",
    "organization.activate",
    "organization.suspend",
    "organization.deactivate",
    "organization.revoke_admin",
    "membership.assign",
    "membership.revoke",
    "member.suspend",
    "member.reinstate",
}


class PlatformService:
    """Platform-oversight operations: organization lifecycle, FPO-admin
    onboarding, beekeeper membership, and an append-only governance audit.

    Only the `platform_oversight` role reaches these methods (route layer
    enforces permission); this service owns the orchestration of the immutable
    server-generated organization keys, the one-time onboarding invite, and
    attribution of every sensitive mutation to the acting user.
    """

    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def _audit(self, *, action, user, target_type, target_key, detail=None):
        if action not in _GOVERNANCE_ACTIONS:
            return
        actor_id = getattr(user, "user_id", "") or ""
        actor_role = getattr(user, "role", "") or ""
        self._repo.append_audit_event(
            action=action,
            actor_user_id=actor_id,
            actor_role=actor_role,
            target_type=target_type,
            target_key=target_key,
            detail=detail,
        )

    def create_fpo(self, *, data: dict[str, Any], user: Any = None) -> dict[str, Any]:
        org = {
            "name": data["name"].strip(),
            "type": (data.get("type") or "FPO").strip() or "FPO",
            "status": "PENDING",
            "country": data.get("country", "") or "",
            "state": data.get("state", "") or "",
            "district": data.get("district", "") or "",
            "address": data.get("address", "") or "",
            "postal_code": data.get("postal_code", "") or "",
            "contact_email": data.get("contact_email", "") or "",
            "contact_phone": data.get("contact_phone", "") or "",
            "registration_no": data.get("registration_no", "") or "",
            "client_id": data.get("client_id", "") or "",
            "location": ", ".join(
                x
                for x in (
                    data.get("address", "") or "",
                    data.get("district", "") or "",
                    data.get("state", "") or "",
                )
                if x
            ),
        }
        created = self._repo.create_organization(org)
        created.setdefault("status", "PENDING")
        created.setdefault("location", "")
        self._audit(
            action="organization.create",
            user=user,
            target_type="organization",
            target_key=created.get("organization_key", ""),
            detail={"name": created.get("name", "")},
        )
        return created

    def activate_organization(self, org_key: str, user: Any = None) -> dict[str, Any]:
        result = self._set_status(org_key, "ACTIVE")
        if "error" not in result:
            self._audit(
                action="organization.activate",
                user=user,
                target_type="organization",
                target_key=result.get("organization_key", org_key),
            )
        return result

    def suspend_organization(self, org_key: str, user: Any = None) -> dict[str, Any]:
        result = self._set_status(org_key, "SUSPENDED")
        if "error" not in result:
            self._audit(
                action="organization.suspend",
                user=user,
                target_type="organization",
                target_key=result.get("organization_key", org_key),
            )
        return result

    def deactivate_organization(self, org_key: str, user: Any = None) -> dict[str, Any]:
        result = self._set_status(org_key, "DORMANT")
        if "error" not in result:
            self._audit(
                action="organization.deactivate",
                user=user,
                target_type="organization",
                target_key=result.get("organization_key", org_key),
            )
        return result

    def _set_status(self, org_key: str, status: str) -> dict[str, Any]:
        org = self._repo.update_organization_status(org_key, status)
        if org is None:
            return {"error": f"organization '{org_key}' does not exist"}
        return org

    def onboard_initial_admin(
        self, *, organization_key: str, email: str, role: str = "fpo", user: Any = None
    ) -> dict[str, Any]:
        org = self._repo.get_organization(organization_key)
        if org is None:
            return {"error": f"organization '{organization_key}' does not exist"}
        invite = self._repo.create_organization_invite(
            organization_key=org["organization_key"],
            email=email,
            role=role,
            invited_by=getattr(user, "user_id", "") if user is not None else "",
        )
        return invite

    def revoke_organization_invite(self, invite_id: str, user: Any = None) -> dict[str, Any]:
        invite = self._repo.revoke_organization_invite(invite_id)
        if invite is None:
            return {"error": "invite does not exist"}
        self._audit(
            action="organization.revoke_admin",
            user=user,
            target_type="organization_invite",
            target_key=invite.get("organization_key", ""),
            detail={"invite_id": invite_id, "email": invite.get("email", "")},
        )
        return invite

    def list_organizations(self) -> list[dict[str, Any]]:
        return self._repo.list_organizations()

    # ---- membership -------------------------------------------------------
    def _member_errors(self, org_key: str, user_id: str) -> dict[str, Any] | None:
        org = self._repo.get_organization(org_key)
        if org is None:
            return {"error": f"organization '{org_key}' does not exist"}
        member = self._repo.get_user(user_id)
        if member is None:
            return {"error": f"user '{user_id}' does not exist"}
        return None

    def assign_beekeeper(self, *, org_key: str, user_id: str, user: Any = None) -> dict[str, Any]:
        err = self._member_errors(org_key, user_id)
        if err:
            return err
        org = self._repo.get_organization(org_key)
        member = self._repo.get_user(user_id)
        beekeeper = self._repo.get_beekeeper(user_id)
        # Only beekeepers carry a Producer ID; assignment keeps it untouched.
        new_org_id = org["organization_key"]
        self._repo.set_user_org(user_id, new_org_id)
        if beekeeper is not None:
            self._repo.set_beekeeper_org(user_id, org["id"])
        self._audit(
            action="membership.assign",
            user=user,
            target_type="organization",
            target_key=org_key,
            detail={
                "user_id": user_id,
                "role": member.get("role", ""),
                "producer_id": str((beekeeper or {}).get("producer_id") or ""),
            },
        )
        return {"id": user_id, "org_id": new_org_id}

    def revoke_membership(self, *, org_key: str, user_id: str, user: Any = None) -> dict[str, Any]:
        err = self._member_errors(org_key, user_id)
        if err:
            return err
        member = self._repo.get_user(user_id)
        if member.get("org_id") != org_key:
            return {"error": f"user '{user_id}' is not a member of '{org_key}'"}
        self._repo.set_user_org(user_id, "")
        self._repo.set_beekeeper_org(user_id, None)
        self._audit(
            action="membership.revoke",
            user=user,
            target_type="organization",
            target_key=org_key,
            detail={"user_id": user_id, "role": member.get("role", "")},
        )
        return {"id": user_id, "org_id": ""}

    def suspend_member(self, *, org_key: str, user_id: str, user: Any = None) -> dict[str, Any]:
        err = self._member_errors(org_key, user_id)
        if err:
            return err
        member = self._repo.get_user(user_id)
        if member.get("org_id") != org_key:
            return {"error": f"user '{user_id}' is not a member of '{org_key}'"}
        self._repo.set_user_status(user_id, "SUSPENDED")
        self._audit(
            action="member.suspend",
            user=user,
            target_type="organization",
            target_key=org_key,
            detail={"user_id": user_id, "role": member.get("role", "")},
        )
        return {"id": user_id, "status": "SUSPENDED"}

    def reinstate_member(self, *, org_key: str, user_id: str, user: Any = None) -> dict[str, Any]:
        err = self._member_errors(org_key, user_id)
        if err:
            return err
        member = self._repo.get_user(user_id)
        if member.get("org_id") != org_key:
            return {"error": f"user '{user_id}' is not a member of '{org_key}'"}
        self._repo.set_user_status(user_id, "ACTIVE")
        self._audit(
            action="member.reinstate",
            user=user,
            target_type="organization",
            target_key=org_key,
            detail={"user_id": user_id, "role": member.get("role", "")},
        )
        return {"id": user_id, "status": "ACTIVE"}

    def list_members(self, org_key: str) -> list[dict[str, Any]]:
        mems = self._repo.list_users(role=None, org_id=org_key)
        return [_strip_user(m) for m in mems]

    def list_beekeepers(self, org_key: str | None = None) -> list[dict[str, Any]]:
        org_uuid: str | None = None
        if org_key:
            org = self._repo.get_organization(org_key)
            if org is None:
                return []
            org_uuid = org.get("id") or org_key
        rows = []
        for b in self._repo.list_beekeepers(org_id=org_uuid):
            row = {
                "id": b.get("id", ""),
                "name": b.get("name", ""),
                "phone": b.get("phone", ""),
                "producer_id": b.get("producer_id", ""),
                "organization_id": b.get("organization_id") or b.get("org_id") or "",
                "is_independent": bool(b.get("is_independent", True)),
                "client_id": b.get("client_id", ""),
                "org_key": "",
                "org_name": "",
            }
            org = self._repo.get_organization(row["organization_id"]) if row["organization_id"] else None
            if org:
                row["org_key"] = org.get("organization_key") or org.get("id") or ""
                row["org_name"] = org.get("name", "")
            rows.append(row)
        return rows

    def list_audit_events(self, limit: int = 100) -> list[dict[str, Any]]:
        return self._repo.list_audit_events(limit=limit)


def _strip_user(user: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in user.items() if k != "password_hash"}


def build_platform_service(repo: Repository) -> PlatformService:
    return PlatformService(repo)