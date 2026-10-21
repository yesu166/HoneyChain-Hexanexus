# HoneyChain | Project Brief

> **Proposed repository description:** Rural-first honey traceability connecting beekeepers, FPOs, laboratories, processors, buyers, and consumers through batch records, QR Honey Passports, and evidence integrity.

## Overview
HoneyChain is a digital traceability platform for the Indian honey value chain. It aims to keep a harvest's provenance connected as honey moves through collection, laboratory testing, processing, packaging, custody, and consumer verification.

## Problem and opportunity
Supply-chain evidence can be fragmented across paper records, spreadsheets, certificates, and disconnected systems. That makes it harder for participants to follow a batch and for consumers to understand what has actually been verified.

## Proposed approach
- A rural-first, offline-aware beekeeper workflow for hive, inspection, and harvest records.
- Shared batch identity and role-based workflows for FPOs, laboratories, processors, buyers, and institutional users.
- A QR-linked Honey Passport that retrieves public, privacy-conscious provenance information.
- Layered evidence integrity using hashing, event records, and a permissioned-ledger integration where configured.
- AI/ML features as separate, clearly labelled integrations whose availability depends on their model services.

## Current scope and maturity
This repository brings together the Flutter app, FastAPI backend, React portal, database/migration material, ML components, and Hyperledger Fabric integration code. The exact live state of cloud infrastructure and external services must be verified independently. A source-code path or configured UI is not proof that a remote service is currently running.

## Roadmap proposal
1. Re-verify a clean local setup and document the supported development commands.
2. Demonstrate one complete batch journey from beekeeper record through verification and public passport.
3. Verify ledger submission and confirmation against a running Fabric network, with honest pending/failed/unavailable states.
4. Add repeatable end-to-end tests for roles, evidence lineage, QR lookup, and failure cases.
5. Publish deployment, threat-model, data-protection, and demo-reset instructions.
6. Track unfinished integrations in the capability matrix rather than presenting them as production-ready.

## Important limitations
A blockchain anchor can help establish that a record was committed and has not changed; it does **not** prove that the physical honey is pure or prevent adulteration. QR codes identify records and are not, by themselves, cryptographic signatures. Laboratory claims should be shown only when supported by the corresponding evidence.

## Collaboration proposal
Useful contributions include documentation, reproducible test cases, accessibility and offline UX improvements, API contract tests, safe demo data, and deployment fixes. Changes to trust states, permissions, and provenance semantics should include tests and an explanation of the threat or integrity property they protect.

## Licensing and reuse
The repository's root license, if present, governs reuse. This brief does not grant additional rights. Confirm a suitable license and community guidance before describing the project as open source or inviting broad external contributions.
