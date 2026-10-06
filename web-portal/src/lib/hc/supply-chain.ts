/**
 * Flexible HoneyChain supply-chain engine (frontend adapter).
 *
 * HoneyChain does not persist a "route" field, and it does not require one path.
 * `backend/app/services/lineage_service.py` accepts ANY allowed state
 * transition (`created → in_harvest → processing → packaged → in_qa →
 * distribution → retail`), and provenance arrives as separate records:
 * harvest links, custody events, lab tests, certificates and ledger anchors.
 *
 * So this module derives the chain from what actually happened. It never
 * assumes Beekeeper → FPO → Lab → Processor → Buyer is the only route, and it
 * distinguishes "this stage was skipped on this route" from "this stage
 * failed", which mean completely different things to a buyer or a consumer.
 *
 * Nothing here mutates or invents backend state; every value is traceable to a
 * record returned by the HoneyChain API.
 */
import type {
  Batch,
  Certificate,
  CustodyEvent,
  LabTest,
  StageEvidence,
  StageId,
  StageStatus,
  SupplyChain,
  SupplyChainStage,
} from "./types.ts";

/** Position of each backend batch state on the canonical lifecycle. */
const STATE_INDEX: Record<string, number> = {
  created: 0,
  in_harvest: 1,
  processing: 2,
  packaged: 3,
  in_qa: 4,
  distribution: 5,
  retail: 6,
  recalled: 7,
  rejected: 7,
};

/** States after which no further stage can be recorded. */
const TERMINAL_BAD_STATES = new Set(["recalled", "rejected"]);

export const VERIFIED_TIERS = new Set([
  "lab_verified",
  "blockchain_anchored",
  "authority_verified",
]);

export interface SupplyChainInput {
  batch: Pick<Batch, "status" | "trust_tier" | "created_at" | "quantity_kg">;
  custody?: CustodyEvent[];
  labTests?: LabTest[];
  certificates?: Certificate[];
  anchor?: { chain_status?: string; tx_hash?: string } | null;
}

export interface StageDefinition {
  id: StageId;
  label: string;
  actor: string;
  /** Required for a lot to be offered as verified provenance. */
  required: boolean;
}

/**
 * The operational stages a honey lot can pass through. `consumer` is the final
 * public verification layer and always exists; every other stage is optional
 * depending on the recorded route.
 */
export const STAGE_DEFINITIONS: StageDefinition[] = [
  { id: "source", label: "Beekeeper & harvest", actor: "Beekeeper", required: true },
  { id: "collection", label: "FPO collection", actor: "FPO", required: false },
  { id: "lab", label: "Laboratory verification", actor: "Laboratory", required: false },
  { id: "processing", label: "Processing", actor: "Processor", required: false },
  { id: "packaging", label: "Packaging", actor: "Processor", required: false },
  { id: "buyer", label: "Buyer / distribution", actor: "Buyer", required: false },
  { id: "consumer", label: "Consumer passport", actor: "Public", required: true },
];

function stateIndex(batch: Pick<Batch, "status">): number {
  return STATE_INDEX[(batch.status || "created").toLowerCase()] ?? 0;
}

function hasAction(events: CustodyEvent[], ...actions: string[]): CustodyEvent | undefined {
  return events.find((e) => actions.includes((e.action || "").toUpperCase()));
}

function stage(
  def: StageDefinition,
  status: StageStatus,
  extra: Partial<SupplyChainStage> = {},
): SupplyChainStage {
  return {
    id: def.id,
    label: def.label,
    actor: def.actor,
    status,
    required: def.required,
    optional: !def.required,
    evidence: [],
    verification: "",
    ...extra,
  };
}

const byId = (id: StageId): StageDefinition =>
  STAGE_DEFINITIONS.find((d) => d.id === id) ?? STAGE_DEFINITIONS[0];

export function buildSupplyChain(input: SupplyChainInput): SupplyChain {
  const batch = input.batch;
  const custody = input.custody ?? [];
  const tests = input.labTests ?? [];
  const certificates = input.certificates ?? [];
  const anchor = input.anchor ?? null;
  const at = stateIndex(batch);
  const state = (batch.status || "created").toLowerCase();
  const terminal = TERMINAL_BAD_STATES.has(state);
  const tier = (batch.trust_tier || "self_declared").toLowerCase();

  // The authoritative verdict is the most recent test, not the last element of
  // the array. `LabTest.tested_at` is optional and the API does not promise an
  // order, so pick the newest dated test and fall back to array order only when
  // no test carries a timestamp. Without this, a newest-first response would
  // report the oldest verdict as current.
  const dated = tests
    .map((t, index) => ({ test: t, index, at: t.tested_at || "" }))
    .filter((entry) => Boolean(entry.at));
  const latestTest = dated.length
    ? dated.reduce((best, entry) => (entry.at > best.at ? entry : best)).test
    : tests.length
      ? tests[tests.length - 1]
      : undefined;

  const labPassed =
    (latestTest?.status || "").toLowerCase() === "passed" ||
    (latestTest?.result || "").toUpperCase() === "PASS";
  const labFailed =
    (latestTest?.status || "").toLowerCase() === "failed" ||
    (latestTest?.result || "").toUpperCase() === "FAIL";
  const harvestEvent = hasAction(custody, "HARVEST");
  const collectionEvent = hasAction(custody, "COLLECTION");
  const processingEvent = hasAction(custody, "PROCESSING");
  const packagingEvent = hasAction(custody, "PACKAGING");
  const movementEvent = hasAction(custody, "DISTRIBUTION", "SALE", "TRANSFER");

  const stages: SupplyChainStage[] = [];

  // ---------------------------------------------------------------- source
  {
    const evidence: StageEvidence[] = harvestEvent
      ? [{ kind: "custody", label: `Custody event ${harvestEvent.action}`, at: harvestEvent.event_at }]
      : [];
    const completed = Boolean(harvestEvent) || at >= 1;
    stages.push(
      stage(byId("source"), completed ? "COMPLETED" : "PENDING", {
        completedAt: harvestEvent?.event_at,
        evidence,
        verification:
          "Harvest provenance is resolved by the public passport, which lists the " +
          "harvest rows linked to this lot.",
        skippedReason: completed
          ? undefined
          : "No harvest link or custody event is recorded for this lot yet.",
      }),
    );
  }

  // ------------------------------------------------------------ collection
  {
    const evidence: StageEvidence[] = collectionEvent
      ? [{ kind: "custody", label: `Custody event ${collectionEvent.action}`, at: collectionEvent.event_at }]
      : [];
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (collectionEvent) {
      s = "COMPLETED";
    } else if (at >= 3) {
      s = "SKIPPED";
      reason =
        "FPO collection was not part of this batch's recorded route. This is not " +
        "a failure — the lot simply did not pass through an FPO.";
    } else if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state}; no further collection will be recorded.`;
    }
    stages.push(
      stage(byId("collection"), s, {
        completedAt: collectionEvent?.event_at,
        evidence,
        skippedReason: reason,
      }),
    );
  }

  // ------------------------------------------------------------------- lab
  {
    const evidence: StageEvidence[] = tests.map((t) => ({
      kind: "lab_test",
      label: `${t.lab_id || "Laboratory"} · ${t.result || t.status}`,
      at: t.tested_at || t.requested_at,
    }));
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (labFailed) {
      s = "FAILED";
      reason = "A laboratory result of FAIL is on record for this lot.";
    } else if (labPassed) {
      s = "COMPLETED";
    } else if (latestTest) {
      reason = `Laboratory status is "${latestTest.status}"; no verdict yet.`;
    } else if (at >= 3) {
      s = "SKIPPED";
      reason =
        "Laboratory verification was not part of this supply-chain route. The lot " +
        "moved forward without a laboratory step.";
    } else if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state}; no laboratory step will be recorded.`;
    }
    // Case-insensitive, and "issued" counts as active: the demo dataset uses
    // that word and a live payload that upper-cases its statuses would
    // otherwise report zero certificates on a lot that has one.
    const activeCerts = certificates.filter((c) => {
      const s = (c.status || "").toLowerCase();
      return s === "active" || s === "issued" || s === "valid";
    });
    stages.push(
      stage(byId("lab"), s, {
        completedAt: latestTest?.tested_at ?? undefined,
        evidence,
        skippedReason: reason,
        verification: activeCerts.length
          ? `${activeCerts.length} active certificate${activeCerts.length === 1 ? "" : "s"} on record`
          : labPassed
            ? "Laboratory result recorded"
            : "No laboratory verdict recorded",
      }),
    );
  }

  // ------------------------------------------------------------ processing
  {
    const evidence: StageEvidence[] = processingEvent
      ? [{ kind: "custody", label: `Custody event ${processingEvent.action}`, at: processingEvent.event_at }]
      : [];
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (processingEvent || at >= 2) {
      s = "COMPLETED";
    } else if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state} before processing.`;
    } else if (labFailed) {
      reason = "A failed laboratory result blocks processing until it is resolved.";
    }
    stages.push(
      stage(byId("processing"), s, {
        completedAt: processingEvent?.event_at,
        evidence,
        skippedReason: reason,
      }),
    );
  }

  // ------------------------------------------------------------- packaging
  {
    const evidence: StageEvidence[] = packagingEvent
      ? [{ kind: "custody", label: `Custody event ${packagingEvent.action}`, at: packagingEvent.event_at }]
      : [];
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (packagingEvent || at >= 3) {
      s = "COMPLETED";
    } else if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state} before packaging.`;
    } else if (labFailed) {
      reason = "A failed laboratory result blocks packaging.";
    }
    stages.push(
      stage(byId("packaging"), s, {
        completedAt: packagingEvent?.event_at,
        evidence,
        skippedReason: reason,
      }),
    );
  }

  // ----------------------------------------------------------------- buyer
  {
    const evidence: StageEvidence[] = movementEvent
      ? [
          {
            kind: "custody",
            label: `${movementEvent.action}${
              movementEvent.to_org ? ` → ${movementEvent.to_org}` : ""
            }`,
            at: movementEvent.event_at,
          },
        ]
      : [];
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (at >= 5) {
      s = "COMPLETED";
    } else if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state}; it will not reach a buyer.`;
    } else if (movementEvent) {
      reason =
        "A custody movement is recorded, but the batch state has not reached " +
        "distribution yet.";
    }
    stages.push(
      stage(byId("buyer"), s, {
        completedAt: movementEvent?.event_at,
        evidence,
        skippedReason: reason,
      }),
    );
  }

  // -------------------------------------------------------------- consumer
  {
    const evidence: StageEvidence[] = [];
    if (anchor?.chain_status === "anchored") {
      evidence.push({
        kind: "anchor",
        label: `Ledger anchor ${anchor.tx_hash || "(no reference returned)"}`,
      });
    }
    const requiredDone = stages.every((s) => !s.required || s.status === "COMPLETED");
    let s: StageStatus = "PENDING";
    let reason: string | undefined;
    if (terminal) {
      s = "NOT_APPLICABLE";
      reason = `Batch is ${state}; the public passport is not offered as verified provenance.`;
    } else if (requiredDone) {
      s = "COMPLETED";
    } else {
      reason =
        "The public passport becomes available once the required stages are recorded.";
    }
    stages.push(
      stage(byId("consumer"), s, {
        evidence,
        skippedReason: reason,
        // Never the bare word "Verified". This stage is COMPLETED for any lot
        // whose required records exist, which includes self-declared ones, and
        // the absence of a negative finding is not a positive verification.
        // It also uses the same case-insensitive anchor check as every other
        // screen, so "Anchored" is not silently downgraded.
        verification:
          (anchor?.chain_status || "").toLowerCase() === "anchored"
            ? "Ledger anchor confirmed by HoneyChain"
            : "No blockchain record exists for this lot; provenance comes from recorded events.",
      }),
    );
  }

  const operational = stages.filter((s) => s.status !== "NOT_APPLICABLE");
  const completed = operational.filter((s) => s.status === "COMPLETED");
  const skipped = stages.filter((s) => s.status === "SKIPPED").map((s) => s.id);
  const failed = stages.filter((s) => s.status === "FAILED");

  const blockers: string[] = [];
  const notes: string[] = [];
  if (terminal) blockers.push(`Batch state is "${state}".`);
  if (labFailed) blockers.push("Laboratory result is FAIL.");
  for (const s of stages) {
    if (s.required && s.status !== "COMPLETED") {
      blockers.push(`${s.label} is not complete (${stageStatusCopy(s.status)}).`);
    }
  }
  if (skipped.length) {
    notes.push(
      `Not part of this route: ${skipped
        .map((id) => STAGE_DEFINITIONS.find((d) => d.id === id)?.label ?? id)
        .join(", ")}.`,
    );
  }
  if (!VERIFIED_TIERS.has(tier)) {
    notes.push(
      "No laboratory or ledger verification tier is on record for this lot, so the " +
        "passport reports it as self declared.",
    );
  }

  const status = terminal
    ? "REJECTED"
    : blockers.length
      ? "IN_PROGRESS"
      : VERIFIED_TIERS.has(tier)
        ? "PASSPORT_READY"
        : "TRACEABILITY_READY";

  return {
    stages,
    operationalTotal: operational.length,
    operationalCompleted: completed.length,
    skipped,
    failedStageIds: failed.map((s) => s.id),
    trustTier: tier,
    status,
    passportReadiness: {
      ready: !terminal && failed.length === 0,
      verified: VERIFIED_TIERS.has(tier),
      blockers,
      notes,
    },
  };
}

/** Copy for a stage badge — never "failed" when a stage was simply skipped. */
export function stageStatusCopy(status: StageStatus): string {
  switch (status) {
    case "COMPLETED":
      return "Completed";
    case "PENDING":
      return "Pending";
    case "SKIPPED":
      return "Skipped on this route";
    case "NOT_APPLICABLE":
      return "Not applicable";
    case "FAILED":
      return "Failed";
    default:
      return status;
  }
}

export function summaryLine(chain: SupplyChain): string {
  return `${chain.operationalCompleted} of ${chain.operationalTotal} operational stages completed`;
}
