# Role / Workspace UX Map — one session, many workspaces

**Scope:** how the four console experiences in the Flutter app (Beekeeper, Organization / FPO,
Buyer, Consumer) are presented as **workspaces of a single user session** instead of separate
logins. Companion: `AUTH_SESSION_MODEL.md` (session), `QR_HONEY_PASSPORT.md` (consumer path).

## 1. The model

A workspace is a full-screen experience the account may enter *without logging out and without
re-entering a persona login*. `Workspace` is defined in `lib/data/auth.dart`:

| Workspace | Experience | Reaches via |
|---|---|---|
| `beekeeper` | Production, harvests, batches, bee health, IoT | `MainShell` (default home) |
| `organization` | Collections → batches → lab → products → anchoring/release | `OrgPortalScreen` |
| `buyer` | Jar allocation / product purchase | `BuyerPortalScreen` |
| `consumer` | Scan / verify / read the Honey Passport | `ConsumerScreen` |

## 2. Eligibility (only what is actually granted)

`HoneyChainStore.availableWorkspaces` decides what the account may enter:

- **Demo (no backend compiled):** all four personae are available — the demo identity
  (`DemoSeed`) genuinely drives the whole chain in the seed (hives → FPO batches → products →
  jars → consumer QR), so every console is a real view over that data.
- **Backend-backed (`_backendSignedIn` + role):** narrowed to the workspaces the role maps to:
  - `beekeeper` → Beekeeper + Consumer
  - `fpo` / `admin` / `field_officer` / `organization` / `processor` / `lab` → + Organization/FPO
  - `buyer` → + Buyer
  - `consumer` is always available (public passport verification is a read-only experience).

`switchWorkspace()` rejects any workspace not in `availableWorkspaces` and never touches the
session (see `test/auth_session_test.dart`).

## 3. Switching UX

The More tab shows a chip row. Tapping a workspace:

1. persists the new `activeWorkspace` in `LocalStore` (`honey.activeWorkspace`),
2. opens that console directly via `Navigator.push` — **no separate login**,
3. a back-press returns to the Beekeeper shell without ending the session.

The previous first-launch gate (`WhoAreYouScreen`) still lets a fresh (signed-out) user choose
an entry point. Once a session exists, switching happens through the same experience without
re-authentication.

## 4. Persistence

The active workspace is restored on restart (`ensureStarted` re-reads
`LocalStore.loadActiveWorkspace()`), so restoring a session also restores the workspace the
person was in.

## 5. Map to the recommended role list (from the Product Spec)

| Spec role | Today's workspace console | Gap |
|---|---|---|
| Beekeeper | `beekeeper` ✅ | — |
| Field officer | `organization` (FPO portal) | no dedicated FO screen; honest label "Organization / FPO" |
| FPO staff / admin | `organization` ✅ | — |
| Lab | `organization` (lab steps in batch flow) | no standalone lab console |
| Processor | `organization` (product consolidation) | no standalone processor console |
| Distributor / Retailer | — | not modelled (no distinct console) |
| Buyer | `buyer` ✅ | — |
| Consumer / Investor / Regulator | `consumer` ✅ | — |

**Honest note:** Lab / Processor / Field-officer consoles are *not* separate screens today.
The relevant steps exist inside the FPO batch workflow. Building dedicated consoles is future
work and is **not claimed here**.