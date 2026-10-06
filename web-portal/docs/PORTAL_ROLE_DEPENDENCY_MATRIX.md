# Portal role dependency matrix

Derived from `backend/app/core/rbac.py` (`PERMISSION_MATRIX`) in the HoneyChain
backend, which is authoritative. The portal never decides a role; it renders what
`/auth/me` returns and asks the backend whether an action is permitted.

`admin` is `set(ACTIONS) - PLATFORM_ORGANIZATION_ACTIONS`. That single line is
why an admin signing into the portal sees `403` on `/platform/organizations` and
`/platform/beekeepers`: organization and membership governance were deliberately
withheld from `admin` and reserved for `platform_oversight`.

## Roles

| Role | Scope | Portal home | Notable |
| --- | --- | --- | --- |
| `beekeeper` | `read_own` | `/beekeeper` | Own harvests, hives, batches |
| `fpo` | `read_org` | `/org` | Org dashboard, custody, splits/merges |
| `lab` | `any` | `/lab` | Tests, certificates (issue/revoke) |
| `processor` | `read_org` | `/processor` | Packaging, custody, batch status |
| `buyer` | `any` | `/buyer` | Read-only lots + passport |
| `institution` | `any` | `/kvic` | Clusters, audit read, platform stats |
| `admin` | `any` | `/admin` | Domain admin, **not** platform org/membership |
| `platform_oversight` | `any` | `/admin/platform` | Organization + membership lifecycle |

## Portal screen to backend permission

| Portal screen | Route | Backend permission | `admin` | `platform_oversight` |
| --- | --- | --- | --- | --- |
| Business ops | `/admin` | `platform.stats`, `org.dashboard` | yes | no |
| System / platform | `/admin/platform` | `platform.stats`, `admin.audit` | yes | yes |
| Beekeeper table | `/platform/beekeepers` | `membership.view` | **403** | yes |
| Organization table | `/platform/organizations` | `organization.view_all` | **403** | yes |
| Clusters | `/kvic` | `org.dashboard` | yes | yes |
| Audit timeline | `admin.audit` | `admin.audit` | yes | yes |
| Passport (public) | `/api/v1/passport/{code}` | none (public, rate limited) | n/a | n/a |
| Ledger health (public) | `/api/v1/blockchain/health` | none (public) | n/a | n/a |

## Roles with no backend counterpart

The portal must not invent distributor or retailer workspaces. HoneyChain has no
such role and no such endpoint, so a screen for one would be an empty shell that
looks broken. The nearest real workflows are:

- distributor → custody transfer (`batch.transfer_custody`) held by `fpo` / `processor`
- retailer → read-only lot browsing plus passport verification, held by `buyer`

## How a 403 is surfaced

A 403 is a permission answer, not an empty result set. The portal renders the
error state for the table, so `403` can never be mistaken for "no organizations
exist". See `src/features/admin/admin-workspace.tsx`.

## Known dependency gaps

- There is no endpoint listing all users, so the "beekeepers" table shows
  `/platform/beekeepers` (platform membership), not a full user directory.
- `platform_oversight` cannot read domain data, so its portal navigation omits
  `/admin` (business) entirely rather than rendering cards that would all 403.
