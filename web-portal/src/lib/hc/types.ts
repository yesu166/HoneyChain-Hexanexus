/**
 * Mirrors `PERMISSION_MATRIX` in HoneyChain's `backend/app/core/rbac.py`.
 *
 * `platform_oversight` is deliberately a separate role from `admin`: the
 * backend grants `admin` every action EXCEPT the platform organization and
 * membership lifecycle, so an admin signing in cannot read
 * `/platform/organizations` or `/platform/beekeepers`. Adding the role here is
 * what lets a real oversight account reach the screens it is entitled to
 * instead of falling through to the default navigation.
 */
export type Role =
  | "beekeeper"
  | "fpo"
  | "lab"
  | "processor"
  | "buyer"
  | "retailer"
  | "admin"
  | "institution"
  | "platform_oversight";

export type DataMode = "live" | "demo";

export interface TokenResponse {
  access_token: string;
  token_type: string;
  expires_in_minutes: number;
}

export interface UserMe {
  id: string;
  email: string;
  name: string;
  phone: string;
  role: Role | string;
  roles: Role[];
  org_id: string;
}

export interface Hive {
  id: string;
  hive_code: string;
  beekeeper_id: string;
  org_id?: string;
  status: string;
  created_at?: string;
  location?: string | null;
}

export interface Reading {
  id: string;
  hive_id: string;
  temperature_c?: number | null;
  humidity_percent?: number | null;
  weight_kg?: number | null;
  recorded_at?: string;
  source?: string;
}

export interface HealthScore {
  hive_id: string;
  risk_level: string;
  risk_score: number;
  contributing_factors: { factor: string; contribution: string }[];
  recommended_action: string;
  simulated: boolean;
  timestamp: string;
}

export interface Harvest {
  id: string;
  hive_id: string;
  beekeeper_id: string;
  harvested_at: string;
  quantity_kg: number;
  honey_type: string;
  collected?: boolean;
}

export interface Batch {
  id: string;
  batch_code: string;
  status: string;
  honey_type: string;
  quantity_kg: number;
  origin: string;
  organization_id: string;
  trust_tier: string;
  created_at?: string;
  lab_result?: string | null;
}

export interface CustodyEvent {
  id: string;
  batch_id: string;
  action: string;
  actor: string;
  notes: string;
  event_at: string;
  to_actor?: string;
  to_org?: string;
}

export interface LabTest {
  id: string;
  batch_id: string;
  lab_id: string;
  status: string;
  result?: string | null;
  requested_note?: string;
  tested_by?: string;
  requested_at?: string;
  tested_at?: string | null;
  batch_code?: string;
  honey_type?: string;
}

/**
 * A selectable laboratory, returned by `GET /api/v1/labs`.
 *
 * These are real organization rows. The test-request form picks a lab from this
 * list instead of letting an operator type an arbitrary organization id, so the
 * selector can never name a laboratory HoneyChain does not have on record.
 */
export interface LabOrganization {
  id: string;
  organization_key: string;
  name: string;
  type: string;
  state: string;
  district: string;
  status: string;
}

/** One recorded step of the aggregated provenance timeline. */
export interface ProvenanceStage {
  stage: string;
  at?: string | null;
  ref?: string | null;
  actor?: string | null;
  detail?: string | null;
}

/** One harvest contributing material to the batch. */
export interface ProvenanceHarvestSource {
  harvest_id?: string | null;
  hive_id?: string | null;
  beekeeper_id?: string | null;
  harvested_at?: string | null;
  quantity_kg?: number | null;
  allocated_kg?: number;
  honey_type?: string | null;
  location?: string | null;
}

/** One hive contributing a harvest to the batch. */
export interface ProvenanceHiveSource {
  hive_id?: string | null;
  hive_code?: string | null;
  beekeeper_id?: string | null;
  location?: string | null;
  status?: string | null;
}

/**
 * `GET /api/v1/batches/{id}/provenance` — material lineage (hive → harvest →
 * batch → split/merge) plus operational provenance in a single response.
 *
 * The backend only aggregates records that already exist, so a missing stage
 * stays missing and `mass_balance.balanced` is a measurement, not a promise.
 */
export interface BatchProvenance {
  batch: Batch;
  harvest_sources: ProvenanceHarvestSource[];
  hive_sources: ProvenanceHiveSource[];
  relations: Record<string, unknown>[];
  custody: CustodyEvent[];
  lab_tests: LabTest[];
  certificates: Certificate[];
  /** Ledger anchor exactly as the repository stored it; `{}` when unanchored. */
  anchor: Record<string, unknown>;
  mass_balance: {
    batch_quantity_kg: number;
    allocated_kg: number;
    unallocated_kg: number;
    balanced: boolean;
  };
  timeline: ProvenanceStage[];
  genealogy: GenealogyNode[];
}

/**
 * Market linkage. These are CAPABILITIES of the FPO and Buyer surfaces, not
 * portals of their own — the catalog in `workspaces.ts` deliberately has no
 * "Market Linkage" card.
 *
 * Every field here mirrors a persisted column. `remaining_kg` in particular is
 * real committed stock, not a client-side guess: the seller decrements it on the
 * backend when an order is accepted, so the portal must render whatever it is
 * given rather than computing its own figure.
 */
export interface MarketListing {
  id: string;
  batch_id: string;
  seller_org_id: string;
  quantity_kg: number;
  remaining_kg: number;
  price_per_kg: number;
  currency: string;
  status: "OPEN" | "RESERVED" | "SOLD" | "WITHDRAWN";
  notes: string;
  listed_at?: string | null;
  closed_at?: string | null;
  client_id?: string;
  batch_code?: string;
  batch_origin?: string;
  batch_honey_type?: string;
  batch_trust_tier?: string;
  batch_status?: string;
}

export interface PurchaseOrder {
  id: string;
  listing_id: string;
  batch_id: string;
  buyer_org_id: string;
  buyer_user_id: string;
  quantity_kg: number;
  price_per_kg: number;
  /** Persisted at agreement time, so a later price change cannot alter it. */
  total_amount: number;
  currency: string;
  status: "REQUESTED" | "ACCEPTED" | "REJECTED" | "FULFILLED" | "CANCELLED";
  buyer_notes: string;
  seller_notes: string;
  requested_at?: string | null;
  decided_at?: string | null;
  decided_by?: string;
  fulfilled_at?: string | null;
  batch_code?: string;
  batch_origin?: string;
  batch_trust_tier?: string;
  seller_org_id?: string;
}

/** `GET /api/v1/market/marketplace` — open lots plus this caller's orders. */
export interface Marketplace {
  listings: MarketListing[];
  orders: PurchaseOrder[];
}

/**
 * A printed package label and its identity.
 *
 * `scan_count` and `first_scan_org` are the evidence the reuse detector reasons
 * about; they are stored, not computed in the browser, so two scanners can never
 * disagree about how many times a code has been seen.
 */
export interface QrPackage {
  id: string;
  package_code: string;
  batch_id: string;
  organization_id: string;
  quantity_kg: number;
  status: "ACTIVE" | "SCANNED" | "RECALLED";
  first_scan_org?: string;
  first_scan_at?: string | null;
  scan_count: number;
  issued_at?: string | null;
}

/** One reason a scan was flagged. The backend computes these; the UI never guesses. */
export interface QrSignal {
  code: string;
  detail: string;
}

export interface QrScanResult {
  package: QrPackage | null;
  result: "CLEAR" | "SUSPICIOUS";
  signals: QrSignal[];
  prior_scan_count: number;
}

/** One persisted scan row, as `GET /api/v1/qr/scans` returns it. */
export interface QrScanRecord {
  id: string;
  package_code: string;
  batch_id?: string | null;
  scanner_user_id: string;
  scanner_role?: string;
  organization_id?: string;
  result: "CLEAR" | "SUSPICIOUS";
  /** The persisted reasons, so an auditor can see why a scan was flagged. */
  signals: QrSignal[];
  scanned_at?: string | null;
}

/**
 * Mobile processing van — the KVIC Field Officer submodule.
 *
 * `is_laboratory_certificate` is always false and is surfaced deliberately: a van
 * observation is a field result and must never be presented as lab certification.
 */
export interface VanSample {
  id: string;
  visit_id: string;
  batch_id?: string | null;
  sample_code: string;
  quantity_kg?: number | null;
  result: "PENDING" | "PASS" | "FAIL";
  moisture_percent?: number | null;
  notes: string;
  collected_at?: string | null;
  is_laboratory_certificate?: boolean;
  batch_trust_tier?: string;
}

export interface VanVisit {
  id: string;
  van_code: string;
  officer_user_id: string;
  organization_id: string;
  target_org_id?: string;
  target_name?: string;
  status: "SCHEDULED" | "ARRIVED" | "SAMPLE_COLLECTED" | "COMPLETED" | "CANCELLED";
  scheduled_for?: string | null;
  arrived_at?: string | null;
  completed_at?: string | null;
  notes?: string;
  samples: VanSample[];
}

/** `GET /api/v1/van/dashboard` — the field-officer submodule in one call. */
export interface VanDashboard {
  visits: VanVisit[];
  counts: Record<string, number>;
}

export interface NotificationItem {
  notification_id: string;
  hive_id?: string | null;
  batch_id?: string | null;
  device_id?: string | null;
  category: string;
  severity: string;
  reason: string;
  recommended_action: string;
  source: string;
  title: string;
  body: string;
  created_at: string;
  read: boolean;
}

export interface NotificationList {
  items: NotificationItem[];
  unread_count: number;
}

export interface IotDevice {
  device_id: string;
  device_name: string;
  device_type: string;
  device_status: string;
  assigned_hive_id?: string | null;
  organization_id: string;
  last_seen?: string | null;
  event_count: number;
  mode?: string;
  is_simulated?: boolean;
}

export interface TelemetryEvent {
  event_id: string;
  device_id: string;
  sequence: number;
  timestamp: string;
  payload: {
    temperature_c?: number | null;
    humidity_percent?: number | null;
    hive_weight_kg?: number | null;
  };
  is_simulated?: boolean;
}

export interface Certificate {
  certificate_id: string;
  batch_id: string;
  lab_id: string;
  certificate_type: string;
  issued_at?: string;
  valid_until?: string;
  content_hash?: string;
  status: string;
  issuer_name?: string;
  revoked_at?: string;
  revocation_reason?: string;
  anchor?: Record<string, unknown>;
}

export interface PassportEvent {
  type: string;
  at?: string;
  actor?: string;
  detail?: string;
}

export interface PassportResponse {
  subject: string;
  subject_code: string;
  batch_code: string;
  honey_type: string;
  origin: string;
  quantity_kg: number;
  trust_tier: string;
  events: PassportEvent[];
  verification?: {
    lab_id?: string;
    result?: string;
    tested_by?: string;
    tested_at?: string;
  } | null;
  anchor?: {
    data_hash?: string;
    tx_hash?: string;
    chain_status?: string;
    anchored_at?: string;
  };
  genealogy?: string[];
  caveat: string;
  /** Present on live responses: the full server payload, unmodified. */
  raw?: Record<string, unknown>;
}

export interface PlatformStats {
  registered_beekeepers: number;
  organizations: number;
  hives: number;
  harvests: number;
  honey_harvested_kg: number;
  batches: number;
  lab_tests: number;
  certificates: number;
  iot_devices: number;
  telemetry_events: number;
  users?: number;
  organization_status?: Record<string, number>;
  batch_trust?: Record<string, number>;
  batch_status?: Record<string, number>;
}

/**
 * Faithful mirror of `backend/app/schemas/org.py::OrgDashboardRead`.
 *
 * An earlier revision of this portal expected a nested shape (`organization`,
 * `kpis`, `recent_harvests`, …) that HoneyChain never returned, which silently
 * broke the FPO portal. The fields below are the ones the API actually sends.
 */
export interface OrgDashboard {
  org_id: string;
  org_name: string;
  active_beekeepers: number;
  hives: number;
  clusters: number;
  honey_harvested_kg: number;
  collections: number;
  batches: number;
  verified_batches: number;
  pending_actions: number;
  recent_activity: ActivityItem[];
  source: string;
}

export interface ActivityItem {
  type: string;
  label: string;
  timestamp: string;
  entity_ref: string;
}

/**
 * Faithful mirror of `backend/app/schemas/org.py::OrganizationRead`.
 *
 * Counters are NOT part of the API payload. Anything the UI wants to show next
 * to an organization is computed client-side from real rows (batches, hives,
 * harvests) — never invented by this portal.
 */
export interface OrganizationSummary {
  id: string;
  organization_key: string;
  name: string;
  type: string;
  status: string;
  country: string;
  state: string;
  district: string;
  address: string;
  postal_code: string;
  contact_email: string;
  contact_phone: string;
  registration_no: string;
  location: string;
  client_id: string;
}

/** Derived, client-side aggregation shown beside an organization. */
export interface OrgRollup {
  hives: number;
  beekeepers: number;
  batches: number;
  verified_batches: number;
  honey_harvested_kg: number;
  unverified_batches: number;
}

export interface OrganizationMember {
  id: string;
  email: string;
  name: string;
  phone: string;
  role: string;
  org_id: string;
  status: string;
  producer_id: string;
}

export interface AuditEvent {
  id: string;
  actor_user_id: string;
  actor_role: string;
  action: string;
  target_type: string;
  target_key: string;
  detail: Record<string, unknown>;
  created_at: string;
}

export interface GenealogyRelation {
  type: string;
  other: string;
}

export interface GenealogyNode {
  id?: string;
  batch_code?: string;
  relationship?: string;
  quantity_kg?: number;
  trust_tier?: string;
  relations?: GenealogyRelation[];
  [key: string]: unknown;
}

/** `GET /api/v1/batches/{id}/lineage` — genealogy plus ledger integrity. */
export interface BatchLineage {
  batch_id: string;
  genealogy: GenealogyNode[];
  ledger: LedgerIntegrity;
}

export interface LedgerIntegrity {
  chain_id?: string;
  integrity_ok?: boolean;
  event_count?: number;
  checked_at?: string;
  [key: string]: unknown;
}

/** `GET /api/v1/batches/{id}/state` */
export interface BatchStateView {
  batch_id: string;
  status: string;
  trust_tier: string;
  holder: {
    batch_id?: string;
    holder_ref?: string;
    since?: string;
    event?: string;
  };
}

/**
 * Canonical batch lifecycle, mirroring `backend/app/services/lineage_service.py`.
 * The backend accepts any *allowed* transition, so no single supply chain is
 * mandatory — the UI must derive the path from what actually happened.
 */
export type BatchState =
  | "created"
  | "in_harvest"
  | "processing"
  | "packaged"
  | "in_qa"
  | "distribution"
  | "retail"
  | "recalled"
  | "rejected";

/** Mirrors `backend/app/schemas/custody.py::CustodyAction` (a strict enum). */
export type CustodyAction =
  | "HARVEST"
  | "COLLECTION"
  | "QUALITY_TEST"
  | "PROCESSING"
  | "PACKAGING"
  | "TRANSFER"
  | "DISTRIBUTION"
  | "SALE"
  | "CORRECTION";

export interface LineageStateRead {
  batch_id: string;
  from_state?: string;
  status: string;
  changed: boolean;
}

/** `GET /api/v1/assertions/{ref}/discrepancies` */
export interface DiscrepancyList {
  entity_ref: string;
  discrepancies: DiscrepancyItem[];
  open_count: number;
}

/** `GET /api/v1/assertions/{ref}/impacts` */
export interface ImpactList {
  entity_ref: string;
  impacts: Record<string, unknown>[];
  count: number;
}

export interface DiscrepancyItem {
  title: string;
  reference_quantity_kg: number;
  claimed_quantity_kg: number;
  delta_kg: number;
  tolerance_kg: number;
  status: string;
  reference_party: string;
  claimed_party: string;
}

export interface ProductivityPredictionRequest {
  apiary: string;
  total_brood: number;
  varroa_2: number;
  hygiene_2: number;
}

export interface ProductivityPredictionResponse {
  predicted_honey_yield_kg: number;
  model: string;
}

/* ------------------------------------------------------------------ */
/* Ask My Bee (HoneyChain server-side assistant)                          */
/* ------------------------------------------------------------------ */

/**
 * `GET /api/v1/ai/status` — tells the portal whether the server-side
 * assistant can be used. The server never reveals secrets here.
 */
export interface AIStatus {
  enabled: boolean;
  configured: boolean;
  model: string;
}

export interface AIChatMessage {
  role: "user" | "assistant";
  content: string;
}

/** `POST /api/v1/ai/chat` request body (1..40 messages). */
export interface AIChatRequest {
  messages: AIChatMessage[];
  request_id?: string;
}

export interface AIChatResponse {
  reply: string;
  request_id?: string | null;
  /** How many server-side HoneyChain tools the assistant consulted. */
  tool_count: number;
}

/**
 * `network` = the browser never got an HTTP response (wrong origin, CORS
 * rejection, TLS failure, DNS). `timeout` = connected but no answer in time.
 * `http` = the server answered with a status. Keeping these apart stops a
 * network fault from being reported as a missing record.
 */
export type ApiFailure = "network" | "timeout" | "http";

export class ApiError extends Error {
  status: number;
  kind: ApiFailure;
  /** The exact URL the failing request was sent to, for diagnosis. */
  url?: string;
  constructor(status: number, message: string, kind: ApiFailure = "http", url?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.kind = kind;
    this.url = url;
  }
}

export interface HoneyChainApi {
  login: (identifier: string, password: string) => Promise<TokenResponse>;
  me: () => Promise<UserMe>;
  platformStats: () => Promise<PlatformStats>;
  platformOrganizations: () => Promise<OrganizationSummary[]>;
  platformMembers: (orgKey: string) => Promise<OrganizationMember[]>;
  platformBeekeepers: () => Promise<OrganizationMember[]>;
  platformAudit: () => Promise<AuditEvent[]>;
  orgDashboard: (orgId: string) => Promise<OrgDashboard>;
  hives: () => Promise<Hive[]>;
  hive: (id: string) => Promise<Hive>;
  createHive: (body: { hive_code: string; location?: string; client_id?: string }) => Promise<Hive>;
  hiveReadings: (id: string) => Promise<Reading[]>;
  hiveHealth: (id: string) => Promise<HealthScore>;
  addReading: (
    id: string,
    body: {
      temperature_c?: number;
      humidity_percent?: number;
      weight_kg?: number;
    },
  ) => Promise<Reading>;
  harvests: () => Promise<Harvest[]>;
  createHarvest: (body: {
    hive_id: string;
    quantity_kg: number;
    honey_type?: string;
    client_id?: string;
  }) => Promise<Harvest>;
  batches: () => Promise<Batch[]>;
  batch: (id: string) => Promise<Batch>;
  createBatch: (body: BatchCreateBody) => Promise<Batch>;
  batchState: (id: string) => Promise<BatchStateView>;
  transitionBatch: (
    id: string,
    toState: BatchState,
    note?: string,
  ) => Promise<LineageStateRead>;
  requestLabTest: (batchId: string, labId: string, note?: string) => Promise<LabTest>;
  genealogy: (id: string) => Promise<GenealogyNode[]>;
  lineage: (id: string) => Promise<BatchLineage>;
  /** `GET /api/v1/batches/{id}/provenance` — canonical aggregated provenance. */
  batchProvenance: (batchId: string) => Promise<BatchProvenance>;
  custody: (id: string) => Promise<CustodyEvent[]>;
  addCustodyEvent: (
    id: string,
    body: {
      action: CustodyAction;
      notes?: string;
      to_actor?: string;
      to_org?: string;
      quantity_kg?: number;
      client_id?: string;
    },
  ) => Promise<CustodyEvent>;
  /** `GET /api/v1/labs` — real laboratory directory for the request selector. */
  labs: () => Promise<LabOrganization[]>;
  labQueue: (labId: string) => Promise<LabTest[]>;
  labTests: (batchId: string) => Promise<LabTest[]>;
  /** `POST /api/v1/labs/tests/{testId}/start` — requested → in_progress. */
  startLabTest: (testId: string) => Promise<LabTest>;
  submitLabResult: (
    testId: string,
    result: "PASS" | "FAIL",
    notes?: string,
  ) => Promise<LabTest>;
  notifications: () => Promise<NotificationList>;
  markNotificationRead: (id: string) => Promise<void>;
  assertions: (ref: string) => Promise<Record<string, unknown>[]>;
  verification: (ref: string) => Promise<Record<string, unknown>>;
  discrepancies: (ref: string) => Promise<DiscrepancyList>;
  impacts: (ref: string) => Promise<ImpactList>;
  evidence: (id: string) => Promise<Record<string, unknown>>;
  iotDevices: () => Promise<IotDevice[]>;
  iotDevice: (id: string) => Promise<IotDevice>;
  iotTelemetry: (id: string) => Promise<TelemetryEvent[]>;
  passport: (code: string) => Promise<PassportResponse>;
  batchCertificates: (id: string) => Promise<Certificate[]>;
  verifyCertificate: (id: string) => Promise<Record<string, unknown>>;
  issueCertificate: (body: {
    batch_id: string;
    lab_id?: string;
    certificate_type?: string;
    issuer_name?: string;
    anchor?: boolean;
  }) => Promise<Certificate>;
  revokeCertificate: (id: string, reason: string) => Promise<Certificate>;
  blockchainStatus: () => Promise<Record<string, unknown>>;
  blockchainHealth: () => Promise<Record<string, unknown>>;
  blockchainTx: (ref: string) => Promise<Record<string, unknown>>;
  productivityPrediction: (
    body: ProductivityPredictionRequest,
  ) => Promise<ProductivityPredictionResponse>;
  /** `GET /api/v1/ai/status` — is the server-side Ask My Bee assistant usable? */
  aiStatus: () => Promise<AIStatus>;
  /** `POST /api/v1/ai/chat` — server-mediated assistant over the caller's data. */
  aiChat: (body: AIChatRequest) => Promise<AIChatResponse>;
  // --- Market linkage (FPO Market Linkage / Buyer Procurement) ---
  // These back capabilities inside the FPO and Buyer workspaces. There is no
  // "Market Linkage" portal and must not become one.
  marketListings: (status?: string) => Promise<MarketListing[]>;
  createListing: (body: {
    batch_id: string;
    quantity_kg: number;
    price_per_kg: number;
    currency?: string;
    notes?: string;
    client_id?: string;
  }) => Promise<MarketListing>;
  withdrawListing: (listingId: string) => Promise<MarketListing>;
  marketplace: () => Promise<Marketplace>;
  purchaseOrders: () => Promise<PurchaseOrder[]>;
  createOrder: (body: {
    listing_id: string;
    quantity_kg: number;
    buyer_notes?: string;
    client_id?: string;
  }) => Promise<PurchaseOrder>;
  decideOrder: (
    orderId: string,
    accept: boolean,
    sellerNotes?: string,
  ) => Promise<PurchaseOrder>;
  fulfilOrder: (orderId: string) => Promise<PurchaseOrder>;
  cancelOrder: (orderId: string) => Promise<PurchaseOrder>;
  // --- QR package identity + reuse detection ---
  qrPackages: (batchId?: string) => Promise<QrPackage[]>;
  issuePackage: (body: {
    batch_id: string;
    quantity_kg: number;
    package_code?: string;
    client_id?: string;
  }) => Promise<QrPackage>;
  recallPackage: (code: string) => Promise<QrPackage>;
  scanPackage: (code: string) => Promise<QrScanResult>;
  /** Flagged scans across the caller's packages, as recorded by the backend. */
  suspiciousScans: (limit?: number) => Promise<QrScanRecord[]>;
  // --- Mobile processing van (KVIC Field Officer) ---
  vanDashboard: () => Promise<VanDashboard>;
  vanVisits: (status?: string) => Promise<VanVisit[]>;
  scheduleVanVisit: (body: {
    van_code: string;
    target_org_id?: string;
    target_name?: string;
    notes?: string;
    client_id?: string;
  }) => Promise<VanVisit>;
  advanceVanVisit: (visitId: string) => Promise<VanVisit>;
  collectVanSample: (
    visitId: string,
    body: {
      batch_id: string;
      sample_code: string;
      quantity_kg?: number;
      moisture_percent?: number;
      notes?: string;
      client_id?: string;
    },
  ) => Promise<VanSample>;
  recordVanResult: (
    sampleId: string,
    result: "PASS" | "FAIL",
    notes?: string,
  ) => Promise<VanSample>;
  health: () => Promise<Record<string, unknown>>;
}

/** Body accepted by `POST /api/v1/batches`. */
export interface BatchCreateBody {
  batch_code: string;
  quantity_kg: number;
  origin?: string;
  honey_type?: string;
  harvest_ids?: string[];
  harvest_allocations?: { harvest_id: string; quantity_kg: number }[];
  status?: string;
  client_id?: string;
}

/* ------------------------------------------------------------------ */
/* Flexible supply chain (derived client-side — see lib/hc/supply-chain.ts) */
/* ------------------------------------------------------------------ */

export type StageId =
  | "source"
  | "collection"
  | "lab"
  | "processing"
  | "packaging"
  | "buyer"
  | "consumer";

export type StageStatus =
  | "COMPLETED"
  | "PENDING"
  | "SKIPPED"
  | "NOT_APPLICABLE"
  | "FAILED";

export interface StageEvidence {
  kind: string;
  label: string;
  at?: string;
}

export interface SupplyChainStage {
  id: StageId;
  label: string;
  actor: string;
  status: StageStatus;
  required: boolean;
  optional: boolean;
  completedAt?: string;
  /** Why a stage is not part of this route — never a failure claim. */
  skippedReason?: string;
  evidence: StageEvidence[];
  verification: string;
}

export interface SupplyChain {
  stages: SupplyChainStage[];
  operationalTotal: number;
  operationalCompleted: number;
  skipped: StageId[];
  failedStageIds: StageId[];
  trustTier: string;
  status: "IN_PROGRESS" | "TRACEABILITY_READY" | "PASSPORT_READY" | "REJECTED";
  passportReadiness: {
    ready: boolean;
    verified: boolean;
    blockers: string[];
    notes: string[];
  };
}

/* ------------------------------------------------------------------ */
/* Passport lifecycle (derived — see lib/hc/passport.ts)               */
/* ------------------------------------------------------------------ */

export type PassportLifecycleState =
  | "DRAFT"
  | "TRACEABILITY_READY"
  | "VERIFICATION_PENDING"
  | "VERIFIED"
  | "PUBLISHED"
  | "REVOKED";

export interface PassportSubject {
  /** The stable identifier encoded in the QR and used for lookups. */
  code: string;
  kind: "batch" | "passport" | "product" | "jar";
}

