import { apiFetch } from "./client";
import type {
  AIChatRequest,
  AIChatResponse,
  AIStatus,
  AuditEvent,
  Batch,
  BatchLineage,
  BatchProvenance,
  BatchStateView,
  Certificate,
  CustodyAction,
  CustodyEvent,
  DiscrepancyList,
  GenealogyNode,
  Harvest,
  HealthScore,
  Hive,
  HoneyChainApi,
  ImpactList,
  IotDevice,
  LabOrganization,
  LabTest,
  LineageStateRead,
  MarketListing,
  Marketplace,
  NotificationList,
  OrgDashboard,
  OrganizationMember,
  OrganizationSummary,
  PassportResponse,
  PlatformStats,
  ProductivityPredictionRequest,
  ProductivityPredictionResponse,
  PurchaseOrder,
  QrPackage,
  QrScanRecord,
  QrScanResult,
  Reading,
  TelemetryEvent,
  TokenResponse,
  UserMe,
  VanDashboard,
  VanSample,
  VanVisit,
} from "./types";

export const liveApi: HoneyChainApi = {
  login: (identifier, password) =>
    apiFetch<TokenResponse>("/api/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ identifier, password }),
    }),
  me: () => apiFetch<UserMe>("/api/v1/auth/me"),
  platformStats: () => apiFetch<PlatformStats>("/api/v1/platform/stats"),
  platformOrganizations: () =>
    apiFetch<OrganizationSummary[]>("/api/v1/platform/organizations"),
  // HoneyChain has no `/platform/users` endpoint. Membership is read per
  // organization (`/organizations/{key}/members`) and platform-wide for
  // beekeepers (`/platform/beekeepers`). Both require the platform-oversight
  // permissions, so the caller must be an admin/institution role.
  platformMembers: (orgKey) =>
    apiFetch<OrganizationMember[]>(
      `/api/v1/platform/organizations/${encodeURIComponent(orgKey)}/members`,
    ),
  platformBeekeepers: () =>
    apiFetch<OrganizationMember[]>("/api/v1/platform/beekeepers"),
  platformAudit: () => apiFetch<AuditEvent[]>("/api/v1/platform/audit"),
  orgDashboard: (orgId) => apiFetch<OrgDashboard>(`/api/v1/org/${orgId}/dashboard`),
  hives: () => apiFetch<Hive[]>("/api/v1/hives"),
  hive: (id) => apiFetch<Hive>(`/api/v1/hives/${id}`),
  createHive: (body) =>
    apiFetch<Hive>("/api/v1/hives", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  hiveReadings: (id) => apiFetch<Reading[]>(`/api/v1/hives/${id}/readings`),
  hiveHealth: (id) => apiFetch<HealthScore>(`/api/v1/hives/${id}/health-score`),
  addReading: (id, body) =>
    apiFetch<Reading>(`/api/v1/hives/${id}/readings`, {
      method: "POST",
      body: JSON.stringify(body),
    }),
  harvests: () => apiFetch<Harvest[]>("/api/v1/harvests"),
  createHarvest: (body) =>
    apiFetch<Harvest>("/api/v1/harvests", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  batches: () => apiFetch<Batch[]>("/api/v1/batches"),
  batch: (id) => apiFetch<Batch>(`/api/v1/batches/${id}`),
  createBatch: (body) =>
    apiFetch<Batch>("/api/v1/batches", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  batchState: (id) => apiFetch<BatchStateView>(`/api/v1/batches/${id}/state`),
  transitionBatch: (id, toState, note = "") =>
    apiFetch<LineageStateRead>("/api/v1/batches/transition", {
      method: "POST",
      body: JSON.stringify({ batch_id: id, to_state: toState, note }),
    }),
  requestLabTest: (batchId, labId, note = "") =>
    apiFetch<LabTest>(`/api/v1/batches/${batchId}/lab-test`, {
      method: "POST",
      body: JSON.stringify({ batch_id: batchId, lab_id: labId, requested_note: note }),
    }),
  genealogy: (id) => apiFetch<GenealogyNode[]>(`/api/v1/batches/${id}/genealogy`),
  lineage: (id) => apiFetch<BatchLineage>(`/api/v1/batches/${id}/lineage`),
  custody: (id) => apiFetch<CustodyEvent[]>(`/api/v1/batches/${id}/custody-events`),
  addCustodyEvent: (id, body) =>
    apiFetch<CustodyEvent>(`/api/v1/batches/${id}/custody-events`, {
      method: "POST",
      // CustodyEventCreate requires `batch_id` (plus optional actor/notes/
      // to_actor/to_org). Without it the backend answers 422.
      body: JSON.stringify({ batch_id: id, ...body } satisfies {
        batch_id: string;
        action: CustodyAction;
        notes?: string;
        to_actor?: string;
        to_org?: string;
      }),
    }),
  // Real laboratory directory. The test-request form selects from this list so
  // a request can only name a laboratory HoneyChain actually has on record.
  labs: () => apiFetch<LabOrganization[]>("/api/v1/labs"),
  labQueue: (labId) => apiFetch<LabTest[]>(`/api/v1/labs/${labId}/queue`),
  labTests: (batchId) => apiFetch<LabTest[]>(`/api/v1/batches/${batchId}/lab-tests`),
  // A test moves `requested` -> `in_progress` -> result. NOTE: the backend
  // currently accepts a result on a test still in `requested`; `in_progress` is
  // a recorded state, not an enforced precondition. This UI walks the full
  // sequence so the recorded history is complete, but do not read the UI as
  // evidence that the API requires the intermediate step.
  startLabTest: (testId) =>
    apiFetch<LabTest>(`/api/v1/labs/tests/${encodeURIComponent(testId)}/start`, {
      method: "POST",
    }),
  // Canonical aggregated provenance: material lineage plus operational stages.
  batchProvenance: (batchId) =>
    apiFetch<BatchProvenance>(`/api/v1/batches/${encodeURIComponent(batchId)}/provenance`),
  submitLabResult: (testId, result, notes = "") =>
    apiFetch<LabTest>(`/api/v1/labs/tests/${testId}/result`, {
      method: "POST",
      body: JSON.stringify({ result, notes }),
    }),
  notifications: () => apiFetch<NotificationList>("/api/v1/notifications"),
  markNotificationRead: (id) =>
    apiFetch<void>(`/api/v1/notifications/${id}/read`, { method: "POST" }),
  assertions: (ref) => apiFetch<Record<string, unknown>[]>(`/api/v1/assertions/${ref}`),
  verification: (ref) =>
    apiFetch<Record<string, unknown>>(`/api/v1/assertions/${ref}/verification`),
  discrepancies: (ref) =>
    apiFetch<DiscrepancyList>(`/api/v1/assertions/${ref}/discrepancies`),
  impacts: (ref) => apiFetch<ImpactList>(`/api/v1/assertions/${ref}/impacts`),
  evidence: (id) => apiFetch<Record<string, unknown>>(`/api/v1/evidence/bundles/${id}`),
  iotDevices: () => apiFetch<IotDevice[]>("/api/v1/iot/devices"),
  iotDevice: (id) => apiFetch<IotDevice>(`/api/v1/iot/devices/${id}`),
  iotTelemetry: (id) => apiFetch<TelemetryEvent[]>(`/api/v1/iot/devices/${id}/telemetry`),
  passport: (code) => apiFetch<PassportResponse>(`/api/v1/passport/${encodeURIComponent(code)}`),
  batchCertificates: (id) => apiFetch<Certificate[]>(`/api/v1/batches/${id}/certificates`),
  verifyCertificate: (id) =>
    apiFetch<Record<string, unknown>>(`/api/v1/certificates/verify/${encodeURIComponent(id)}`),
  issueCertificate: (body) =>
    apiFetch<Certificate>("/api/v1/certificates/issue", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  // `reason` is required by the backend schema; sending an empty body is a 422.
  revokeCertificate: (id, reason) =>
    apiFetch<Certificate>(`/api/v1/certificates/${id}/revoke`, {
      method: "POST",
      body: JSON.stringify({ reason }),
    }),
  blockchainStatus: () => apiFetch<Record<string, unknown>>("/api/v1/blockchain/status"),
  blockchainHealth: () => apiFetch<Record<string, unknown>>("/api/v1/blockchain/health"),
  blockchainTx: (ref) =>
    apiFetch<Record<string, unknown>>(`/api/v1/blockchain/transactions/${encodeURIComponent(ref)}`),
  productivityPrediction: (body: ProductivityPredictionRequest) =>
    apiFetch<ProductivityPredictionResponse>("/predict-productivity", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  // `POST /predict-productivity` targets a *separate* HoneyChain model service
  // (PRODUCTIVITY_API_URL on the backend, not part of HoneyChain). When the model
  // service is not deployed the backend reports it as unavailable — the portal
  // must surface that honestly rather than invent a yield.
  aiStatus: () => apiFetch<AIStatus>("/api/v1/ai/status"),
  aiChat: (body: AIChatRequest) =>
    apiFetch<AIChatResponse>("/api/v1/ai/chat", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  health: () => apiFetch<Record<string, unknown>>("/api/v1/health"),
  // --- Market linkage. Capabilities of the FPO / Buyer surfaces, not portals. ---
  marketListings: (status) =>
    apiFetch<MarketListing[]>(
      status ? `/api/v1/market/listings?status=${encodeURIComponent(status)}` : "/api/v1/market/listings",
    ),
  createListing: (body) =>
    apiFetch<MarketListing>("/api/v1/market/listings", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  withdrawListing: (listingId) =>
    apiFetch<MarketListing>(`/api/v1/market/listings/${encodeURIComponent(listingId)}/withdraw`, {
      method: "POST",
    }),
  marketplace: () => apiFetch<Marketplace>("/api/v1/market/marketplace"),
  purchaseOrders: () => apiFetch<PurchaseOrder[]>("/api/v1/market/orders"),
  createOrder: (body) =>
    apiFetch<PurchaseOrder>("/api/v1/market/orders", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  decideOrder: (orderId, accept, sellerNotes = "") =>
    apiFetch<PurchaseOrder>(`/api/v1/market/orders/${encodeURIComponent(orderId)}/decide`, {
      method: "POST",
      body: JSON.stringify({ accept, seller_notes: sellerNotes }),
    }),
  fulfilOrder: (orderId) =>
    apiFetch<PurchaseOrder>(`/api/v1/market/orders/${encodeURIComponent(orderId)}/fulfil`, {
      method: "POST",
    }),
  cancelOrder: (orderId) =>
    apiFetch<PurchaseOrder>(`/api/v1/market/orders/${encodeURIComponent(orderId)}/cancel`, {
      method: "POST",
    }),
  // --- QR package identity + reuse detection ---
  qrPackages: (batchId) =>
    apiFetch<QrPackage[]>(
      batchId ? `/api/v1/qr/packages?batch_id=${encodeURIComponent(batchId)}` : "/api/v1/qr/packages",
    ),
  issuePackage: (body) =>
    apiFetch<QrPackage>("/api/v1/qr/packages", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  recallPackage: (code) =>
    apiFetch<QrPackage>(`/api/v1/qr/packages/${encodeURIComponent(code)}/recall`, {
      method: "POST",
    }),
  scanPackage: (code) =>
    apiFetch<QrScanResult>("/api/v1/qr/scan", {
      method: "POST",
      body: JSON.stringify({ package_code: code }),
    }),
  suspiciousScans: (limit = 50) =>
    apiFetch<QrScanRecord[]>(`/api/v1/qr/scans?limit=${limit}`),
  // --- Mobile processing van (KVIC Field Officer) ---
  vanDashboard: () => apiFetch<VanDashboard>("/api/v1/van/dashboard"),
  vanVisits: (status) =>
    apiFetch<VanVisit[]>(
      status ? `/api/v1/van/visits?status=${encodeURIComponent(status)}` : "/api/v1/van/visits",
    ),
  scheduleVanVisit: (body) =>
    apiFetch<VanVisit>("/api/v1/van/visits", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  advanceVanVisit: (visitId) =>
    apiFetch<VanVisit>(`/api/v1/van/visits/${encodeURIComponent(visitId)}/advance`, {
      method: "POST",
    }),
  collectVanSample: (visitId, body) =>
    apiFetch<VanSample>(`/api/v1/van/visits/${encodeURIComponent(visitId)}/samples`, {
      method: "POST",
      body: JSON.stringify(body),
    }),
  recordVanResult: (sampleId, result, notes = "") =>
    apiFetch<VanSample>(`/api/v1/van/samples/${encodeURIComponent(sampleId)}/result`, {
      method: "POST",
      body: JSON.stringify({ result, notes }),
    }),
};
