# Role & Permission Matrix (server-side RBAC)

Enforced by `backend/app/core/rbac.py` (function `has_permission`) and by the
`require_permission(action)` dependency. Roles come from the JWT subject and
are never trusted from the client.

## Roles

`beekeeper` · `fpo` · `lab` · `processor` · `admin` · `buyer` · `institution`

## Actions

Harvest: `harvest.create`, `harvest.attach_evidence`, `harvest.read`
Hives/IoT: `hive.create`, `reading.submit`
Batches: `batch.create`, `batch.split`, `batch.merge`,
`batch.transfer_custody`, `batch.read`, `batch.update_status`
Lab: `lab.test_request`, `lab.test_result`, `lab.issue_certificate`,
`lab.revoke_certificate`, `lab.read`
Passport: `passport.read`, `passport.verify_public`
Admin/demo: `admin.audit`, `demo.tamper`, `demo.restore`
Sync: `sync.push`

## Matrix

| Action | beekeeper | fpo | lab | processor | buyer | institution | admin |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| harvest.create | ✅ | | | | | | ✅ |
| harvest.attach_evidence | ✅ | | | | | | ✅ |
| harvest.read | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| hive.create | ✅ | ✅ | | | | | ✅ |
| reading.submit | ✅ | ✅ | | | | | ✅ |
| batch.create | ✅ | ✅ | | ✅ | | | ✅ |
| batch.split / merge | ✅ | ✅ | | ✅ | | | ✅ |
| batch.transfer_custody | ✅ | ✅ | | ✅ | | | ✅ |
| batch.read | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| batch.update_status | | ✅ | | ✅ | | | ✅ |
| lab.test_request / result | | ✅ | ✅ | | | | ✅ |
| lab.issue/revoke_certificate | | | ✅ | | | | ✅ |
| lab.read | | ✅ | ✅ | | | | ✅ |
| passport.read | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| admin.audit | | | | | | ✅ | ✅ |
| demo.tamper | | | | | | | ✅ |
| sync.push | ✅ | ✅ | | ✅ | | | ✅ |

## Scoping beyond the matrix

- `beekeeper` → `read_own` (only their own hives/harvests). Service layer
  enforces (e.g. `batches.get_for_user`).
- `fpo` / `processor` → `read_org` (their org only).
- `lab`, `buyer`, `institution`, `admin` → `any` (lab does its assigned
  batches; buyer reads published passports).

`in_scope(user, owner_user_id=, owner_org_id=)` is the helper used by
services; admin/institution always pass scope checks.

## Why server-side

- The UI may hide buttons, but the API is the enforcement point.
- Roles inside the JWT are resolved server-side and are non-forgeable (HS256
  signed with secret; subject/org read from token claims).