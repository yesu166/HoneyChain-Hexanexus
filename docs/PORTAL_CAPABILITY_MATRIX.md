# HoneyChain Portal Capability Matrix

This document describes the currently implemented web and mobile-facing options, their routes, their intended users, and the backend operations they expose. It reflects the source present in this repository; it does not treat hidden UI buttons as proof of authorization.

## 1. Portal map

| Surface | Route | Access | Main capability |
|---|---|---|---|
| Admin / Business Operations | `/admin` | Admin | Cross-workspace operations, platform statistics, organisations, beekeepers, audit, health, ledger and operational status |
| Platform Oversight | `/admin/platform` | Admin / platform oversight | Organisation/member lifecycle and governance |
| KVIC / Institution | `/kvic` | Institution / admin / platform oversight | Cluster status, organisations, statistics, alerts, mobile processing van |
| FPO / Collection | `/org` | FPO / admin | Collection, harvest intake, batch formation, verification, market linkage, hive/device views |
| Beekeeper | `/beekeeper` | Beekeeper / admin | Hive and harvest visibility on the web |
| Laboratory | `/lab` | Lab / admin | Laboratory queue, test start, PASS/FAIL result workflow |
| Processor | `/processor` | Processor / admin | Incoming/verified lots, processing, packaging, custody and Honey Yatra QR |
| Buyer / Procurement | `/buyer` | Buyer / admin | Verified lots, purchase requests, decisions and fulfilment |
| Ask My Bee | `/ask-my-bee` | Beekeeper / FPO / admin | Conversational assistance |
| Alerts | `/alerts` | Authenticated roles | Action-required notifications |
| Honey Passport | `/verify/:code`, `/passport/:code` | Public | No-login product verification |

## 2. Admin / Platform

### Admin workspace — `/admin`

The admin workspace is the broadest operational view.

It can expose:

- business statistics for registered beekeepers, organisations and batches
- organisation listing and status
- beekeeper listing
- audit timeline
- API health / service health
- blockchain/ledger status
- IoT fleet/device visibility
- access to every role-specific workspace already implemented by the portal
- cross-workspace review of the FPO, lab, processor, buyer, beekeeper, KVIC and Honey Passport surfaces

The admin role is also the backend super-admin role. The UI is not the authority: the API permission matrix remains authoritative.

### Platform oversight — `/admin/platform`

Governance functions include:

- create/update organisations
- activate/suspend/deactivate organisations
- onboard/revoke organisation administrators
- assign/revoke memberships
- view memberships
- suspend/reinstate members
- platform statistics and audit visibility

## 3. KVIC / Institution

### KVIC / Institution — `/kvic`

The institutional surface is intended for government and oversight users rather than generic business administration.

It can show:

- active organisations
- registered beekeepers
- active hives
- honey harvested
- batch counts and trust mix
- laboratory test counts
- IoT device counts
- ledger status
- organisations/clusters
- alerts requiring attention
- cluster details
- member / hive / harvest / laboratory status through cluster drill-down

### KVIC Honey Van submodule

The mobile-processing-van workflow is a capability inside the KVIC surface.

It supports:

1. viewing van dashboard/status
2. listing visits
3. scheduling a visit
4. opening a visit
5. advancing the visit through its lifecycle
6. collecting a field sample
7. recording a field result
8. reviewing notes/status

Current lifecycle is represented as:

`scheduled → arrived → sampled → completed`

A van field result is **not an accredited laboratory certificate** and does not silently promote a batch to laboratory-verified status.

## 4. FPO / Collection

### FPO / Collection Manager — `/org`

The FPO surface connects the producer side to the organised value chain.

It supports:

- dashboard / current work
- harvest intake
- viewing available producer harvests
- selecting real, uncollected harvests
- creating a batch from selected harvests
- preserving linked harvest quantities
- batch status and verification visibility
- laboratory test requests
- market linkage
- hive/readings/device visibility
- notifications/action-required states
- batch detail, lineage and provenance access

The batch flow is deliberately based on recorded harvest quantities rather than inventing a quantity in the browser.

## 5. Laboratory

### Laboratory workspace — `/lab`

The lab surface is designed around an explicit workflow:

`requested → in progress → PASS / FAIL`

It supports:

- laboratory queue
- pending sample review
- starting a test
- recording PASS or FAIL
- reviewing historical results
- batch navigation
- laboratory verification context
- certificate workflow through the backend laboratory permissions

The UI explicitly distinguishes a **laboratory result** from a **blockchain proof of provenance**.

## 6. Processor

### Processor workspace — `/processor`

The processor surface separates lots by their current laboratory state:

- waiting on laboratory verification
- verified and ready for processing
- held / blocked after laboratory failure

It supports:

- incoming-lot review
- verified-lot review
- quantity visibility
- batch genealogy
- custody
- processing/packaging workflow
- Honey Yatra QR package operations

Packaging is deliberately blocked in the UI until a laboratory PASS is on record, and the backend enforces the same business rule.

### Honey Yatra QR package operations

The processor/FPO package capability supports:

- issue a package identity for a packed batch
- generate the public verification URL
- generate/print the QR
- scan a package code
- view CLEAR vs suspicious scan results
- see suspicious signals
- view scan history
- recall a package
- review flagged scans

The QR label identifies a package. It does not contain the full passport data.

## 7. Buyer / Procurement

### Buyer workspace — `/buyer`

The buyer workflow is an actual procurement flow rather than a read-only lot gallery.

It supports:

- viewing open verified lots
- seeing available/remaining quantity
- requesting a quantity
- seeing requests awaiting seller action
- seeing accepted orders ready to fulfil
- fulfilling an accepted order
- cancelling a request where allowed
- viewing order history
- opening the relevant batch/passport

A fulfilled order creates a sale/custody event in the HoneyChain domain instead of existing only as a UI transaction.

## 8. Beekeeper

### Web beekeeper surface — `/beekeeper`

The web workspace can surface:

- My Hives
- recent harvests
- selected-hive readings
- hive-health state
- notifications / alerts
- hive creation
- harvest recording
- server-backed hive/harvest state

### Flutter field application

The Flutter application remains the primary rural-first producer surface.

Current documented capabilities include:

- create/manage hives
- record hive conditions and readings
- record inspections and field observations
- offline-first harvest capture
- durable sync queue
- harvest history
- batch / provenance state
- hive-health screening and guidance
- treatment follow-up workflow where available
- notifications
- Honey Passport view
- Honey Yatra QR scanning
- Ask My Bee / conversational assistance
- manual fallback when camera/voice/network capability is unavailable

Offline records are intentionally shown as offline/pending until the server confirms synchronization or an external anchor.

## 9. Ask My Bee

### `/ask-my-bee`

Ask My Bee is a conversational surface rather than a separate role.

It is available to beekeeper/FPO/admin users and is designed to:

- read relevant HoneyChain domain information
- provide operational guidance
- assist with hive/harvest actions
- use tool calling
- request confirmation before write operations
- fall back honestly when AI or backend services are unavailable

The backend exposes AI status and chat endpoints; the portal does not embed a Gemini secret.

## 10. Honey Passport and Honey Yatra QR

### Public consumer surface

The public passport can be opened from:

- Honey Yatra QR scan
- `/verify/<code>`
- `/passport/<code>`
- supported query-string links

It does not require an account.

The public response is designed to show only public, PII-free information such as:

- honey/product type
- origin
- quantity where public
- batch/package identity
- laboratory verification status
- recorded events/journey
- trust/verification tier
- blockchain anchor state
- package scan state
- provenance caveats

The browser never treats a QR payload itself as proof. It resolves an identifier against the backend.

## 11. Shared capability modules

These are not separate portals:

| Capability | Lives inside |
|---|---|
| Market linkage | FPO / Processor / Buyer |
| Honey Yatra QR | Processor / FPO / Consumer |
| Batch genealogy | Batch detail / FPO / Processor / Buyer / Passport |
| Blockchain status | Admin / Passport / batch evidence |
| Mobile processing van | KVIC / Institution |
| Alerts | Shared authenticated surface |
| Honey Passport | Public consumer surface |
| AI assistant | Beekeeper / FPO / Admin |
| Productivity model | Beekeeper / relevant backend-integrated surfaces |

## 12. Authorization rule

UI visibility is not security.

The backend permission matrix controls which operations a role can perform, while service-layer scope checks determine which organisation/user data that role can touch.

The portal was inspected specifically for this distinction because several views intentionally expose the same business entity to different roles.

## 13. Important terminology

- **HoneyChain:** the overall platform.
- **Honey Yatra QR:** the consumer/package QR capability.
- **Honey Passport:** the public, server-backed provenance view opened by the QR.
- **Package code:** the backend identity of a physical package.
- **Batch code:** the supply-chain batch identity.
- **Blockchain anchor:** a cryptographic commitment recorded on the configured ledger.
- **Laboratory result:** the recorded lab PASS/FAIL state; it is not the same thing as a blockchain anchor.
