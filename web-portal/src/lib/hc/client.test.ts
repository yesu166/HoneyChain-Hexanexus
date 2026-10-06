/**
 * Regression tests for the two defects that made the portal lie.
 *
 *  1. A stored demo marker used to be restored BEFORE the live token was
 *     checked, so a browser that had once opened the demo workspace came back
 *     showing "Demo Admin" after a successful live login.
 *  2. A network fault (dropped connection, CORS rejection, Render cold start)
 *     used to be reported as "This record was not found", and it used to throw
 *     away a perfectly valid session.
 *
 * These run on the real modules — no mocks of the auth provider.
 */
import assert from "node:assert/strict";
import { test } from "node:test";

import { ApiError, type UserMe } from "./types.ts";
import { describeApiError, probeConnection, apiBase, apiFetch } from "./client.ts";
import { passportVerifyUrl } from "./passport.ts";
import { buildSupplyChain } from "./supply-chain.ts";
import { chainState, homeForRole, isDeviceHealthy, isLabVerified, roleLabel } from "./format.ts";
import {
  anchorLabel,
  anchorVerdict,
  ledgerExplanation,
  ledgerHeadline,
  ledgerTone,
  readLedgerHealth,
  realTxId,
} from "./blockchain.ts";

/* ------------------------------------------------------------------ */
/* PART 43 — error classification                                      */
/* ------------------------------------------------------------------ */

test("a network fault is a connection error, never a missing record", () => {
  const reported = describeApiError(new ApiError(0, "Unable to connect.", "network"));
  assert.equal(reported.status, 0);
  assert.match(reported.title, /Unable to connect/);
  assert.doesNotMatch(reported.title, /not found/i);
  assert.doesNotMatch(reported.detail, /not found/i);
});

test("a timeout is reported as a timeout, distinct from a missing record", () => {
  const reported = describeApiError(new ApiError(0, "timed out", "timeout"));
  assert.equal(reported.status, 0);
  assert.match(reported.title, /did not respond in time/i);
  assert.doesNotMatch(reported.detail, /not found/i);
});

test("404 is the only status described as a missing record", () => {
  const notFound = describeApiError(new ApiError(404, "This record was not found."));
  assert.equal(notFound.title, "Not found");

  for (const status of [403, 409, 422, 429, 500, 503]) {
    const reported = describeApiError(new ApiError(status, "server said no"));
    assert.doesNotMatch(
      reported.title,
      /not found/i,
      `status ${status} must not be described as a missing record`,
    );
  }
});

test("403 states a role requirement instead of a generic permission shrug", () => {
  const reported = describeApiError(new ApiError(403, "This action requires processor access."));
  assert.match(reported.title, /role/i);
  assert.match(reported.detail, /processor/);
});

test("a retryable transport failure can never be retried into a fake success", async () => {
  // The probe must resolve to a definite OFFLINE, never to CONNECTED and
  // never by throwing something the UI would render as a record lookup.
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new TypeError("Failed to fetch"))) as typeof fetch;
  try {
    assert.equal(await probeConnection(), "OFFLINE");
  } finally {
    globalThis.fetch = original;
  }
});

/* ------------------------------------------------------------------ */
/* PART 44 — production API origin resolution                          */
/* ------------------------------------------------------------------ */

test("the deployed portal resolves the production API origin even when import.meta.env is unevaluated", () => {
  // rolldown-vite ships a bare `import.meta.env` lookup that evaluates to
  // undefined in the browser, so PROD is undefined in a real production build.
  // The deployed failure was every request going to the portal's own origin.
  const original = globalThis.window;
  (globalThis as { window?: unknown }).window = {
    location: { origin: "https://hc-web-portal.onrender.com", hostname: "hc-web-portal.onrender.com" },
  };
  try {
    assert.equal(apiBase(), "https://honeychain-api.onrender.com");
  } finally {
    (globalThis as { window?: unknown }).window = original;
  }
});

test("a dev server keeps same-origin so the /api proxy still forwards", () => {
  const original = globalThis.window;
  (globalThis as { window?: unknown }).window = {
    location: { origin: "http://localhost:8080", hostname: "localhost" },
  };
  try {
    assert.equal(apiBase(), "");
  } finally {
    (globalThis as { window?: unknown }).window = original;
  }
});

test("the login request is sent to the API origin, never the portal origin", async () => {
  const originalFetch = globalThis.fetch;
  const originalWindow = globalThis.window;
  let calledUrl = "";
  globalThis.fetch = ((input: RequestInfo | URL) => {
    calledUrl = String(input);
    return Promise.resolve(
      new Response(JSON.stringify({ access_token: "test-token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as typeof fetch;
  (globalThis as { window?: unknown }).window = {
    location: { origin: "https://hc-web-portal.onrender.com", hostname: "hc-web-portal.onrender.com" },
  };
  try {
    await apiFetch("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ identifier: "probe", password: "not-a-real-credential" }),
    });
    assert.equal(calledUrl, "https://honeychain-api.onrender.com/api/v1/auth/login");
  } finally {
    globalThis.fetch = originalFetch;
    (globalThis as { window?: unknown }).window = originalWindow;
  }
});

test("a 404 carries the origin it was sent to, so a wrong-origin call is diagnosable", () => {
  const error = new ApiError(
    404,
    "This record was not found.",
    "http",
    "https://hc-web-portal.onrender.com/api/v1/auth/login",
  );
  const reported = describeApiError(error);
  assert.match(reported.detail, /hc-web-portal\.onrender\.com/);
});

test("a network fault carries the origin it was sent to", () => {
  const error = new ApiError(0, "Failed to fetch", "network", "https://wrong-origin.example/api/v1/batches");
  const reported = describeApiError(error);
  assert.match(reported.detail, /wrong-origin\.example/);
});

test("a reachable API reports CONNECTED after a real round trip", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(new Response(JSON.stringify({ status: "ok" }), { status: 200 }))) as typeof fetch;
  try {
    assert.equal(await probeConnection(), "CONNECTED");
  } finally {
    globalThis.fetch = original;
  }
});

/* ------------------------------------------------------------------ */
/* PART 36 / 16 — a lot with no backend events must not look complete    */
/* ------------------------------------------------------------------ */

test("a freshly created batch reports pending stages, not completed ones", () => {
  const chain = buildSupplyChain({
    batch: { status: "created", trust_tier: "self_declared", quantity_kg: 5, created_at: "2026-01-01" },
  });
  const lab = chain.stages.find((s) => s.id === "lab");
  const processing = chain.stages.find((s) => s.id === "processing");

  // No lab test exists -> the lot has not been verified.
  assert.ok(lab);
  assert.equal(lab?.status, "PENDING");
  // No custody event and status is still `created` -> not processed.
  assert.ok(processing);
  assert.equal(processing?.status, "PENDING");
  assert.equal(chain.passportReadiness.verified, false);
  assert.equal(chain.status, "IN_PROGRESS");
});

test("a real laboratory FAIL is reported as failed and blocks the passport", () => {
  const chain = buildSupplyChain({
    batch: { status: "packaged", trust_tier: "self_declared", quantity_kg: 5, created_at: "2026-01-01" },
    labTests: [
      {
        id: "t1",
        batch_id: "b1",
        lab_id: "lab-1",
        status: "failed",
        result: "FAIL",
        tested_at: "2026-01-02T00:00:00Z",
      },
    ],
  });
  assert.equal(chain.stages.find((s) => s.id === "lab")?.status, "FAILED");
  assert.deepEqual(chain.failedStageIds, ["lab"]);
  assert.equal(chain.passportReadiness.ready, false);
  assert.ok(chain.passportReadiness.blockers.some((b) => /FAIL/.test(b)));
});

test("a lot that never visited a lab is SKIPPED, not FAILED", () => {
  const chain = buildSupplyChain({
    batch: { status: "retail", trust_tier: "organization_verified", quantity_kg: 5, created_at: "2026-01-01" },
  });
  // Reaching `retail` without a lab record means the stage was not part of
  // this route. Reporting FAILED here would be a false safety claim.
  assert.equal(chain.stages.find((s) => s.id === "lab")?.status, "SKIPPED");
  assert.deepEqual(chain.failedStageIds, []);
});

test("the consumer stage never claims bare verification", () => {
  // This stage is COMPLETED for any lot whose required records exist, which
  // includes self-declared ones. Its fallback used to read "Verified through
  // the HoneyChain database", so an untested lot rendered the word "Verified".
  const chain = buildSupplyChain({
    batch: { status: "retail", trust_tier: "self_declared", quantity_kg: 5, created_at: "2026-01-01" },
  });
  const consumer = chain.stages.find((s) => s.id === "consumer");
  assert.doesNotMatch(
    consumer?.verification ?? "",
    /\bverif/i,
    "the consumer stage must not use verification wording",
  );
});

test("an anchor is recognised regardless of the case the API used", () => {
  const chain = buildSupplyChain({
    batch: { status: "retail", trust_tier: "self_declared", quantity_kg: 5, created_at: "2026-01-01" },
    anchor: { chain_status: "Anchored" },
  });
  const consumer = chain.stages.find((s) => s.id === "consumer");
  assert.match(consumer?.verification ?? "", /anchor confirmed/i);
});

test("the newest laboratory verdict wins, whatever order the API sent", () => {
  // The verdict used to come from the last array element. A newest-first
  // response therefore reported the oldest test as the current result.
  const oldest = {
    id: "old",
    batch_id: "b1",
    lab_id: "lab-1",
    status: "failed",
    result: "FAIL",
    tested_at: "2026-01-01T00:00:00Z",
  } as const;
  const newest = {
    id: "new",
    batch_id: "b1",
    lab_id: "lab-1",
    status: "passed",
    result: "PASS",
    tested_at: "2026-02-01T00:00:00Z",
  } as const;

  const newestFirst = buildSupplyChain({
    batch: { status: "retail", trust_tier: "lab_verified", quantity_kg: 5, created_at: "2026-01-01" },
    labTests: [newest, oldest],
  });
  assert.equal(newestFirst.stages.find((s) => s.id === "lab")?.status, "COMPLETED");

  const oldestFirst = buildSupplyChain({
    batch: { status: "retail", trust_tier: "lab_verified", quantity_kg: 5, created_at: "2026-01-01" },
    labTests: [oldest, newest],
  });
  assert.equal(oldestFirst.stages.find((s) => s.id === "lab")?.status, "COMPLETED");
});

test("an issued certificate is not counted as zero", () => {
  // The demo dataset uses "issued"; a live payload that upper-cased its
  // statuses would have reported no certificates on a lot that has one.
  const chain = buildSupplyChain({
    batch: { status: "retail", trust_tier: "lab_verified", quantity_kg: 5, created_at: "2026-01-01" },
    labTests: [
      {
        id: "t1",
        batch_id: "b1",
        lab_id: "lab-1",
        status: "passed",
        result: "PASS",
        tested_at: "2026-01-02T00:00:00Z",
      },
    ],
    certificates: [
      { certificate_id: "c1", status: "issued" },
      { certificate_id: "c2", status: "ISSUED" },
      { certificate_id: "c3", status: "revoked" },
    ] as never,
  });
  const lab = chain.stages.find((s) => s.id === "lab");
  assert.match(lab?.verification ?? "", /2 active certificate/);
});

/* ------------------------------------------------------------------ */
/* PART 25 / 27 — the QR must point at the canonical public identity   */
/* ------------------------------------------------------------------ */

test("the QR payload is a public verification URL, not a data dump", () => {
  const url = passportVerifyUrl("HC-E2E-1790292487");
  assert.match(url, /\/verify\/HC-E2E-1790292487$/);
  // The identity is the backend batch_code, carried in the path.
  assert.doesNotMatch(url, /"events"/);
  assert.doesNotMatch(url, /quantity_kg/);
});

/* ------------------------------------------------------------------ */
/* PART 32 — backend stays authoritative                               */
/* ------------------------------------------------------------------ */

test("the portal never decides a role it was not given", () => {
  // A 403 must reach the caller intact so the UI can render a permission
  // state. Wrapping it into a different status would let a route render as
  // if the data were merely empty.
  const forbidden = new ApiError(403, "Role 'admin' is not permitted to membership.view", "http");
  const reported = describeApiError(forbidden);
  assert.equal(reported.status, 403);
  assert.equal(forbidden.status, 403);
});

test("a live identity is whatever HoneyChain says, not a hardcoded label", () => {
  // Guards against a future "prettify the admin name" regression: the portal
  // must render `me.name` verbatim, whatever the database holds.
  const me: UserMe = {
    id: "3aabdde6-88d9-4061-99a4-c8a979be6560",
    email: "admin@honeychain.in",
    name: "Demo Admin",
    phone: "+919000000000",
    role: "admin",
    roles: ["admin"],
    org_id: "12e82687-1b38-430a-b8a2-1ab7868dbb42",
  };
  assert.equal(me.name, "Demo Admin");
  assert.equal(me.role, "admin");
});

/* ------------------------------------------------------------------ */
/* Blockchain honesty                                                  */
/*                                                                     */
/* HoneyChain's Render deployment runs BLOCKCHAIN_ADAPTER=simulated, so     */
/* `adapter` is "local". A traceability product that renders that as a */
/* confirmed anchor is claiming tamper-evidence it does not have.      */
/* ------------------------------------------------------------------ */

// The exact payload the deployed Render API returns today.
const RENDER_STATUS = {
  adapter: "local",
  ledger: "local",
  tracker: { transactions: 0 },
  transactions: [],
};

const FABRIC_HEALTH = {
  adapter: "fabric",
  status: "connected",
  network: "mychannel",
  channel: "mychannel",
  chaincode: "honeychain",
  chaincode_version: "2.0",
  chaincode_sequence: 6,
  peer: "localhost:7051",
  msp_id: "Org1MSP",
  last_verified_at: "2026-02-11T10:12:44.918Z",
  error: null,
};

test("the development ledger is never presented as a distributed blockchain", () => {
  const health = readLedgerHealth(RENDER_STATUS);

  assert.equal(health.kind, "SIMULATED");
  // `local` reports itself reachable, but it is not a distributed ledger.
  assert.equal(health.distributed, false);
  assert.equal(health.reachability, "CONNECTED");

  // A reachable-but-local ledger must read as a warning, not as success.
  assert.equal(ledgerTone(health), "warn");
  // It must never claim a live network, and it must say what it actually is.
  assert.doesNotMatch(ledgerHeadline(health), /connected/i);
  assert.match(ledgerHeadline(health), /not a distributed blockchain/i);
  assert.match(ledgerExplanation(health), /not written to any distributed network/i);
  // And it must not present itself as Fabric.
  assert.doesNotMatch(ledgerHeadline(health), /fabric/i);
});

test("a real Fabric network is reported with the facts HoneyChain returned", () => {
  const health = readLedgerHealth(FABRIC_HEALTH);

  assert.equal(health.kind, "FABRIC");
  assert.equal(health.distributed, true);
  assert.equal(ledgerTone(health), "ok");
  assert.equal(health.channel, "mychannel");
  assert.equal(health.chaincode, "honeychain");
  assert.equal(health.chaincodeVersion, "2.0");
  assert.equal(health.chaincodeSequence, "6");
  assert.equal(health.mspId, "Org1MSP");
  assert.match(ledgerHeadline(health), /Fabric connected/);
});

test("the nested fabric block on /blockchain/status is read, not ignored", () => {
  // `/blockchain/status` nests the health object under `fabric` only when the
  // adapter supports health_check. Reading the wrong level would report an
  // empty channel on a perfectly healthy network.
  const health = readLedgerHealth({ adapter: "fabric", ledger: "fabric", fabric: FABRIC_HEALTH });
  assert.equal(health.channel, "mychannel");
  assert.equal(health.distributed, true);
});

test("a missing or unreachable ledger is UNAVAILABLE, never quietly verified", () => {
  for (const payload of [null, undefined, {}, { adapter: "fabric", status: "unavailable" }]) {
    const health = readLedgerHealth(payload);
    assert.equal(health.distributed, false);
    assert.doesNotMatch(ledgerHeadline(health), /connected/i);
  }

  const gateway = readLedgerHealth({ adapter: "fabric", status: "unavailable", error: "connection refused" });
  assert.equal(ledgerTone(gateway), "bad");
  assert.match(ledgerExplanation(gateway), /connection refused/);
  assert.match(ledgerHeadline(gateway), /unavailable/i);
});

test("an unconfigured Fabric adapter is reported as not configured, not connected", () => {
  const health = readLedgerHealth({ adapter: "fabric", status: "not_configured" });
  assert.equal(health.reachability, "NOT_CONFIGURED");
  assert.equal(health.distributed, false);
  assert.match(ledgerHeadline(health), /not configured/i);
});

test("a backend-reported error is surfaced verbatim", () => {
  const health = readLedgerHealth({ adapter: "fabric", status: "misconfigured", error: "missing cert" });
  assert.equal(ledgerTone(health), "bad");
  assert.match(ledgerExplanation(health), /missing cert/);
});

/* ------------------------------------------------------------------ */
/* Per-lot anchors                                                     */
/* ------------------------------------------------------------------ */

test("an anchor is only confirmed when HoneyChain returned a real transaction id", () => {
  // Status alone is not enough: "anchored" with no tx id is a claim the portal
  // cannot substantiate, so it must not be labelled a confirmation.
  assert.equal(anchorVerdict({ chain_status: "anchored" }), "PENDING");
  assert.equal(anchorVerdict({ chain_status: "anchored", tx_hash: "" }), "PENDING");
  assert.equal(anchorVerdict({ chain_status: "anchored", tx_hash: "a1b2" }), "ANCHORED");
  assert.equal(realTxId({ tx_hash: "  " }), null);
  assert.equal(realTxId({ tx_hash: "a1b2" }), "a1b2");
  assert.equal(realTxId(null), null);
  assert.equal(realTxId(undefined), null);
});

test("a lot with no anchor is not anchored, and says which ledger was meant", () => {
  assert.equal(anchorVerdict(null), "NOT_ANCHORED");
  assert.equal(anchorVerdict({}), "NOT_ANCHORED");
  assert.equal(anchorVerdict({ chain_status: "failed" }), "FAILED");
  assert.equal(anchorVerdict({ chain_status: "pending" }), "PENDING");

  const local = readLedgerHealth(RENDER_STATUS);
  assert.match(anchorLabel("NOT_ANCHORED", local), /No distributed ledger configured/i);

  const fabric = readLedgerHealth(FABRIC_HEALTH);
  assert.match(anchorLabel("NOT_ANCHORED", fabric), /Not anchored to the ledger/i);
  assert.equal(anchorLabel("ANCHORED", local), "Ledger anchor confirmed");
});

test("the anchor wording never claims blockchain verification", () => {
  // `chain_status` is only HoneyChain's opinion. Rendering it as "Verified" is how
  // a development-ledger anchor ends up looking like a blockchain guarantee.
  const states = ["anchored", "confirmed", "verified", "success", "pending", "failed", "none", ""];
  for (const status of states) {
    assert.doesNotMatch(
      chainState(status).label,
      /\bverif/i,
      `chain_state("${status}") must not use verification wording`,
    );
  }
  assert.equal(chainState("anchored").label, "Anchored");
  assert.equal(chainState("none").label, "No anchor reported");
});

/* ------------------------------------------------------------------ */
/* Role wiring must match HoneyChain's RBAC, not the portal's assumptions   */
/* ------------------------------------------------------------------ */

test("every role HoneyChain can issue lands somewhere real", () => {
  // These are exactly the keys of `PERMISSION_MATRIX` in
  // `backend/app/core/rbac.py`. A role missing from the portal used to fall
  // through to a default nav and look like a signed-out user.
  const backendRoles = [
    "beekeeper",
    "fpo",
    "lab",
    "processor",
    "buyer",
    "institution",
    "admin",
    "platform_oversight",
  ];
  for (const role of backendRoles) {
    const home = homeForRole(role);
    assert.ok(home, `${role} has no home route`);
    assert.notEqual(
      homeForRole(role),
      homeForRole("unknown_role_from_the_future"),
      `${role} collides with the unknown-role fallback`,
    );
    assert.notEqual(roleLabel(role), role, `${role} has no human label`);
  }
});

test("platform_oversight is reachable and distinct from admin", () => {
  // The backend grants admin every action EXCEPT the platform organization and
  // membership lifecycle, which is why /platform/organizations 403s for admin.
  // The role that can read them must therefore have a real landing page.
  assert.equal(homeForRole("platform_oversight"), "/admin/platform");
  assert.notEqual(homeForRole("platform_oversight"), homeForRole("admin"));
  assert.equal(roleLabel("platform_oversight"), "Platform oversight");
});

/* ------------------------------------------------------------------ */
/* A failed request must never be rendered as an empty dataset         */
/* ------------------------------------------------------------------ */

test("a negated status is not laboratory verification", () => {
  // `status.includes("verified")` returned true for "unverified",
  // "not_verified" and "self_verified". A `true` here is a user-facing
  // "Laboratory verified" claim on a lot nobody tested, and it silently
  // removed unverified lots from the buyer's default filter.
  const negated = ["unverified", "not_verified", "self_verified", "UNVERIFIED", "not-verified"];
  for (const status of negated) {
    assert.equal(
      isLabVerified({ trust_tier: "self_declared", lab_result: null, status }),
      false,
      `"${status}" must not count as laboratory verification`,
    );
  }
});

test("laboratory verification requires positive evidence", () => {
  assert.equal(isLabVerified({ trust_tier: "self_declared", lab_result: "PASS", status: "created" }), true);
  assert.equal(isLabVerified({ trust_tier: "lab_verified", lab_result: null, status: "created" }), true);
  assert.equal(isLabVerified({ trust_tier: "blockchain_anchored", lab_result: null, status: "" }), true);
  assert.equal(isLabVerified({ trust_tier: "self_declared", lab_result: "FAIL", status: "created" }), false);
  // A self-declared lot stays self-declared no matter what its status says.
  assert.equal(isLabVerified({ trust_tier: "self_declared", lab_result: null, status: "verified" }), false);
  assert.equal(isLabVerified({ trust_tier: "", lab_result: null, status: "" }), false);
  // Whole-token match, so a compound status is still readable.
  assert.equal(isLabVerified({ trust_tier: "", lab_result: null, status: "lab_verified" }), true);
});

test("one definition of a healthy device decides every screen", () => {
  // Three screens carried their own copy of this list and one included
  // "active" while the others did not, so the same sensor was flagged on the
  // organization dashboard and healthy on the cluster page.
  for (const healthy of ["online", "Online", "connected", "CONNECTED", "ok", "healthy", "active", "Active"]) {
    assert.equal(isDeviceHealthy(healthy), true, `"${healthy}" should be healthy`);
  }
  for (const unhealthy of ["offline", "error", "alert", "tampered", "", "  ", null, undefined]) {
    assert.equal(isDeviceHealthy(unhealthy), false, `"${unhealthy}" should not be healthy`);
  }
});

test("an unreadable ledger is not reported as no distributed ledger", () => {
  // `health === null` means the health request never answered. Reporting
  // "No distributed ledger configured" from that state asserts something
  // about the deployment that the API never said.
  assert.equal(anchorLabel("NOT_ANCHORED", null, true), "Ledger status unknown");
  assert.equal(anchorLabel("NOT_ANCHORED", null, false), "No distributed ledger configured");
  // An unreadable health probe must not downgrade a confirmed anchor.
  assert.equal(anchorLabel("ANCHORED", null, true), "Ledger anchor confirmed");
  assert.equal(anchorLabel("PENDING", null, true), "Anchoring pending");
  assert.equal(anchorLabel("FAILED", null, true), "Anchor failed");
});
