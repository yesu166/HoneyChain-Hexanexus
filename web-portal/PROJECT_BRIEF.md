# HoneyChain Web Portal | Project Brief

> **Proposed repository description:** Role-based React portal for HoneyChain, covering supply-chain workflows, laboratory verification, processing, buyer procurement, institutional oversight, and public QR Honey Passport lookup.

## Overview
HC-web-portal is the web interface layer for HoneyChain. It presents role-specific workspaces for supply-chain participants and a public Honey Passport experience for inspecting the provenance information associated with a QR-linked package.

## Problem and opportunity
Supply-chain teams need different views of shared records. A single general-purpose dashboard can hide role-specific tasks, while disconnected tools make it harder to follow a batch across collection, testing, processing, and fulfilment.

## Proposed approach
- Provide role-specific web workflows for beekeepers, FPO/collection teams, laboratories, processors, buyers, institutions, and administrators.
- Use the HoneyChain backend as the operational API and source of persisted application data.
- Offer a public, no-login passport lookup that exposes only intended public information.
- Represent asynchronous and external service states honestly, including pending, failed, unavailable, and unverified states.
- Keep authorization and validation on the backend rather than trusting the client interface.

## Current scope and maturity
This repository is the web portal, not a standalone production dataset. Features that depend on the HoneyChain API, database, or Fabric service are only fully usable when those services are configured and reachable. A successful frontend build does not by itself prove end-to-end production readiness.

## Roadmap proposal
1. Document a reproducible local setup and required environment variables.
2. Run role-by-role smoke tests against a known test backend.
3. Verify public QR/passport behaviour for valid, unknown, revoked, and unavailable records.
4. Test authorization failures, empty data, network errors, and expired sessions.
5. Keep a capability matrix that separates implemented UI from backend-dependent or unverified workflows.
6. Publish a clear deployment and demo-reset checklist before presenting the portal as a live system.

## Trust and privacy boundaries
The UI must never manufacture successful verification or blockchain confirmation. Public passport responses should avoid exposing personal or non-public operational information. A displayed ledger state should be backed by the configured service response, not by a static presentation label.

## Collaboration proposal
Useful external contributions include accessible interaction design, responsive layout fixes, component tests, API contract tests, error-state improvements, and documentation. Changes to permission-sensitive workflows should include corresponding backend or integration tests where applicable.

## Licensing and reuse
The repository's root license, if present, governs reuse. This brief does not grant additional rights. Confirm the license and contribution policy before describing the repository as open source.
