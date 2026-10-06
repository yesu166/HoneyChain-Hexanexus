import { ApiError, type HoneyChainApi, type Role, type UserMe } from "./types";
import type {
  AIChatRequest,
  AIChatResponse,
  AIStatus,
  Batch,
  Certificate,
  CustodyEvent,
  Harvest,
  HealthScore,
  Hive,
  IotDevice,
  LabTest,
  MarketListing,
  NotificationItem,
  OrganizationSummary,
  PassportResponse,
  PurchaseOrder,
  QrPackage,
  QrScanRecord,
  QrScanResult,
  QrSignal,
  Reading,
  VanSample,
  VanVisit,
} from "./types";

const DEMO_PASSWORD_HINT = "Demo workspace does not use HoneyChain passwords.";

type DemoState = {
  users: UserMe[];
  currentUser: UserMe;
  orgs: OrganizationSummary[];
  hives: Hive[];
  readings: Reading[];
  harvests: Harvest[];
  batches: Batch[];
  tests: LabTest[];
  certificates: Certificate[];
  custody: CustodyEvent[];
  notifications: NotificationItem[];
  devices: IotDevice[];
  audit: Record<string, unknown>[];
  /**
   * Market / QR / van demo records.
   *
   * These are held in demo state and follow the SAME gates as the live backend
   * (a lab-unverified batch cannot be listed, an unissued code scans as
   * SUSPICIOUS). That is deliberate: a demo that let you sell unverified honey
   * or scan a fabricated clean code would teach the wrong behaviour. It is still
   * labeled demo data and is not HoneyChain.
   */
  listings: MarketListing[];
  orders: PurchaseOrder[];
  packages: QrPackage[];
  scans: QrScanRecord[];
  vanVisits: VanVisit[];
};

const DEMO_USERS: UserMe[] = [
  { id: "u-bk", email: "demo@honeychain.in", name: "Lakshmi Devi", phone: "", role: "beekeeper", roles: ["beekeeper"], org_id: "org-nilgiri" },
  { id: "u-fpo", email: "org@honeychain.in", name: "Ramanathan", phone: "", role: "fpo", roles: ["fpo"], org_id: "org-nilgiri" },
  { id: "u-lab", email: "lab@honeychain.in", name: "Coimbatore Quality Lab", phone: "", role: "lab", roles: ["lab"], org_id: "org-lab-cbe" },
  { id: "u-proc", email: "processor@honeychain.in", name: "Western Ghats Processing", phone: "", role: "processor", roles: ["processor"], org_id: "org-proc" },
  { id: "u-buyer", email: "buyer@honeychain.in", name: "Heritage Foods Procurement", phone: "", role: "buyer", roles: ["buyer"], org_id: "org-buyer" },
  { id: "u-kvic", email: "kvic@honeychain.in", name: "KVIC Institutional Oversight", phone: "", role: "institution", roles: ["institution"], org_id: "org-kvic" },
  { id: "u-admin", email: "admin@honeychain.in", name: "Platform administrator", phone: "", role: "admin", roles: ["admin"], org_id: "org-platform" },
];

function iso(daysAgo: number, hour = 9): string {
  const d = new Date("2026-09-22T08:00:00+05:30");
  d.setDate(d.getDate() - daysAgo);
  d.setHours(hour, 10, 0, 0);
  return d.toISOString();
}

function seed(): DemoState {
  const orgs: OrganizationSummary[] = [
    {
      id: "org-nilgiri",
      organization_key: "nilgiri-hills",
      name: "Nilgiri Hills FPO",
      type: "FPO",
      status: "ACTIVE",
      country: "India",
      state: "Tamil Nadu",
      district: "Nilgiris",
      address: "Kotagiri Road, Udhagamandalam",
      postal_code: "643001",
      contact_email: "hello@nilgirihills.example",
      contact_phone: "+91 40000 10001",
      registration_no: "FPO-TN-100241",
      location: "Nilgiris, Tamil Nadu",
      client_id: "demo-nilgiri",
    },
    {
      id: "org-kutch",
      organization_key: "kutch-bee",
      name: "Kutch Bee Collective",
      type: "FPO",
      status: "ACTIVE",
      country: "India",
      state: "Gujarat",
      district: "Kutch",
      address: "Station Road, Bhuj",
      postal_code: "370001",
      contact_email: "hello@kutchbee.example",
      contact_phone: "+91 40000 10002",
      registration_no: "FPO-GJ-200118",
      location: "Kutch, Gujarat",
      client_id: "demo-kutch",
    },
    {
      id: "org-sundarban",
      organization_key: "sundarban-union",
      name: "Sundarban Honey Union",
      type: "FPO",
      status: "ACTIVE",
      country: "India",
      state: "West Bengal",
      district: "South 24 Parganas",
      address: "Market Road, Canning",
      postal_code: "743329",
      contact_email: "hello@sundarban.example",
      contact_phone: "+91 40000 10003",
      registration_no: "FPO-WB-300455",
      location: "South 24 Parganas, West Bengal",
      client_id: "demo-sundarban",
    },
    {
      id: "org-kashmir",
      organization_key: "kashmir-apiaries",
      name: "Kashmir Valley Apiaries",
      type: "FPO",
      status: "PENDING",
      country: "India",
      state: "Jammu & Kashmir",
      district: "Srinagar",
      address: "Boulevard Road, Srinagar",
      postal_code: "190001",
      contact_email: "hello@kashmirapiaries.example",
      contact_phone: "+91 40000 10004",
      registration_no: "FPO-JK-400871",
      location: "Srinagar, Jammu & Kashmir",
      client_id: "demo-kashmir",
    },
  ];

  const hives: Hive[] = [
    { id: "hive-kotagiri-1", hive_code: "NG-KOT-01", beekeeper_id: "u-bk", org_id: "org-nilgiri", status: "active", location: "Kotagiri slope, Nilgiris", created_at: iso(120) },
    { id: "hive-kotagiri-2", hive_code: "NG-KOT-02", beekeeper_id: "u-bk", org_id: "org-nilgiri", status: "attention", location: "Kotagiri slope, Nilgiris", created_at: iso(90) },
    { id: "hive-ooty-1", hive_code: "NG-OOT-04", beekeeper_id: "u-bk", org_id: "org-nilgiri", status: "active", location: "Ooty forest edge", created_at: iso(60) },
  ];

  const readings: Reading[] = [];
  const addReadings = (hiveId: string, baseTemp: number, baseHum: number, baseWt: number, drift = 0) => {
    for (let i = 6; i >= 0; i--) {
      readings.push({
        id: `r-${hiveId}-${i}`,
        hive_id: hiveId,
        temperature_c: Number((baseTemp + (6 - i) * drift + (i % 2 === 0 ? 0.3 : -0.2)).toFixed(1)),
        humidity_percent: Number((baseHum + (6 - i) * drift * 2).toFixed(1)),
        weight_kg: Number((baseWt + (6 - i) * 0.4).toFixed(1)),
        recorded_at: iso(i, 7),
        source: "iot",
      });
    }
  };
  addReadings("hive-kotagiri-1", 33.2, 54, 17.4);
  addReadings("hive-kotagiri-2", 36.8, 72, 14.1, 0.4);
  addReadings("hive-ooty-1", 32.4, 58, 16.2);

  const harvests: Harvest[] = [
    { id: "hv-1", hive_id: "hive-kotagiri-1", beekeeper_id: "u-bk", harvested_at: iso(12, 11), quantity_kg: 18.4, honey_type: "Multifloral", collected: true },
    { id: "hv-2", hive_id: "hive-kotagiri-2", beekeeper_id: "u-bk", harvested_at: iso(8, 10), quantity_kg: 9.2, honey_type: "Multifloral", collected: true },
    { id: "hv-3", hive_id: "hive-ooty-1", beekeeper_id: "u-bk", harvested_at: iso(3, 16), quantity_kg: 11.0, honey_type: "Acacia", collected: false },
  ];

  const batches: Batch[] = [
    { id: "batch-nil-01", batch_code: "HC-NIL-2408-01", status: "verified", honey_type: "Multifloral", quantity_kg: 42, origin: "Nilgiris, Tamil Nadu", organization_id: "org-nilgiri", trust_tier: "lab_verified", created_at: iso(20), lab_result: "PASS" },
    { id: "batch-nil-02", batch_code: "HC-NIL-2409-02", status: "lab_pending", honey_type: "Acacia", quantity_kg: 27, origin: "Nilgiris, Tamil Nadu", organization_id: "org-nilgiri", trust_tier: "organization_verified", created_at: iso(6), lab_result: null },
    { id: "batch-nil-03", batch_code: "HC-NIL-2410-03", status: "collected", honey_type: "Multifloral", quantity_kg: 19, origin: "Nilgiris, Tamil Nadu", organization_id: "org-nilgiri", trust_tier: "self_declared", created_at: iso(2), lab_result: null },
    { id: "batch-kut-01", batch_code: "HC-KUT-2407-04", status: "lab_failed", honey_type: "Desert multifloral", quantity_kg: 22, origin: "Kutch, Gujarat", organization_id: "org-kutch", trust_tier: "self_declared", created_at: iso(18), lab_result: "FAIL" },
    { id: "batch-sun-01", batch_code: "HC-SUN-2408-02", status: "verified", honey_type: "Mangrove", quantity_kg: 31, origin: "Sundarbans, West Bengal", organization_id: "org-sundarban", trust_tier: "lab_verified", created_at: iso(25), lab_result: "PASS" },
  ];

  const tests: LabTest[] = [
    { id: "test-1", batch_id: "batch-nil-01", lab_id: "org-lab-cbe", status: "passed", result: "PASS", requested_note: "Moisture, HMF, sugar profile", tested_by: "Coimbatore Quality Lab", requested_at: iso(16), tested_at: iso(14, 15), batch_code: "HC-NIL-2408-01", honey_type: "Multifloral" },
    { id: "test-2", batch_id: "batch-nil-02", lab_id: "org-lab-cbe", status: "requested", result: null, requested_note: "Routine verification", requested_at: iso(2, 8), tested_at: null, batch_code: "HC-NIL-2409-02", honey_type: "Acacia" },
    { id: "test-3", batch_id: "batch-kut-01", lab_id: "org-lab-cbe", status: "failed", result: "FAIL", requested_note: "Adulteration screen", tested_by: "Coimbatore Quality Lab", requested_at: iso(15), tested_at: iso(13), batch_code: "HC-KUT-2407-04", honey_type: "Desert multifloral" },
    { id: "test-4", batch_id: "batch-sun-01", lab_id: "org-lab-cbe", status: "passed", result: "PASS", requested_note: "Moisture, HMF", tested_by: "Coimbatore Quality Lab", requested_at: iso(22), tested_at: iso(21), batch_code: "HC-SUN-2408-02", honey_type: "Mangrove" },
    { id: "test-5", batch_id: "batch-nil-02", lab_id: "org-lab-cbe", status: "in_progress", result: null, requested_note: "Repeat moisture check", requested_at: iso(1, 11), tested_at: null, batch_code: "HC-NIL-2409-02", honey_type: "Acacia" },
  ];

  const certificates: Certificate[] = [
    { certificate_id: "CERT-NIL-2408-01", batch_id: "batch-nil-01", lab_id: "org-lab-cbe", certificate_type: "quality", issued_at: iso(14, 16), status: "issued", issuer_name: "Coimbatore Quality Lab" },
    { certificate_id: "CERT-SUN-2408-02", batch_id: "batch-sun-01", lab_id: "org-lab-cbe", certificate_type: "quality", issued_at: iso(21, 12), status: "issued", issuer_name: "Coimbatore Quality Lab" },
  ];

  const custody: CustodyEvent[] = [
    { id: "c-1", batch_id: "batch-nil-01", action: "HARVEST_COLLECTED", actor: "Nilgiri Hills FPO", notes: "Collected from Kotagiri yards", event_at: iso(19) },
    { id: "c-2", batch_id: "batch-nil-01", action: "LAB_SUBMITTED", actor: "Nilgiri Hills FPO", notes: "Sent to Coimbatore Quality Lab", event_at: iso(16) },
    { id: "c-3", batch_id: "batch-nil-01", action: "LAB_VERIFIED", actor: "Coimbatore Quality Lab", notes: "PASS — moisture 17.8%", event_at: iso(14, 15) },
    { id: "c-4", batch_id: "batch-nil-01", action: "RECEIVED_AT_PROCESSOR", actor: "Western Ghats Processing", notes: "42 kg received against collection note", event_at: iso(10) },
    { id: "c-5", batch_id: "batch-nil-02", action: "HARVEST_COLLECTED", actor: "Nilgiri Hills FPO", notes: "Acacia lot from Ooty edge", event_at: iso(5) },
    { id: "c-6", batch_id: "batch-nil-02", action: "LAB_SUBMITTED", actor: "Nilgiri Hills FPO", notes: "Awaiting result", event_at: iso(2) },
  ];

  const notifications: NotificationItem[] = [
    { notification_id: "n-1", hive_id: "hive-kotagiri-2", category: "hive", severity: "high", reason: "Temperature and humidity above usual range", recommended_action: "Inspect NG-KOT-02 today and record what you find.", source: "health-score", title: "Hive NG-KOT-02 needs a visit", body: "This hive is warmer and damper than usual. Check ventilation and look for stress in the colony.", created_at: iso(0, 6), read: false },
    { notification_id: "n-2", batch_id: "batch-nil-02", category: "lab", severity: "medium", reason: "Batch awaiting laboratory result", recommended_action: "Follow up with the laboratory on HC-NIL-2409-02.", source: "lab-queue", title: "Acacia batch still in lab queue", body: "HC-NIL-2409-02 cannot be packaged until the laboratory result is recorded.", created_at: iso(1, 9), read: false },
    { notification_id: "n-3", device_id: "dev-kutch-3", category: "iot", severity: "high", reason: "Device has not reported", recommended_action: "Check the sensor on Kutch yard 3 or replace the battery.", source: "iot", title: "Kutch sensor is silent", body: "Device Kutch-Y3 has not sent a reading since 19 Sep. Hive conditions cannot be confirmed.", created_at: iso(2, 18), read: false },
    { notification_id: "n-4", batch_id: "batch-kut-01", category: "quality", severity: "high", reason: "Laboratory FAIL", recommended_action: "Hold HC-KUT-2407-04. Do not package or sell.", source: "lab", title: "Kutch lot failed laboratory verification", body: "The laboratory recorded FAIL on HC-KUT-2407-04. Keep this lot out of the processing queue.", created_at: iso(13, 12), read: true },
    { notification_id: "n-5", category: "org", severity: "medium", reason: "Onboarding incomplete", recommended_action: "Confirm hive registration for Kashmir Valley Apiaries.", source: "platform", title: "Kashmir cluster still onboarding", body: "Four hives are registered. No batch has been created yet.", created_at: iso(4, 10), read: false },
  ];

  const devices: IotDevice[] = [
    { device_id: "dev-kot-1", device_name: "Kotagiri hive 1 sensor", device_type: "hive_monitor", device_status: "online", assigned_hive_id: "hive-kotagiri-1", organization_id: "org-nilgiri", last_seen: iso(0, 7), event_count: 184, mode: "live", is_simulated: false },
    { device_id: "dev-kot-2", device_name: "Kotagiri hive 2 sensor", device_type: "hive_monitor", device_status: "online", assigned_hive_id: "hive-kotagiri-2", organization_id: "org-nilgiri", last_seen: iso(0, 7), event_count: 162, mode: "live", is_simulated: false },
    { device_id: "dev-kutch-3", device_name: "Kutch yard 3 sensor", device_type: "hive_monitor", device_status: "offline", assigned_hive_id: null, organization_id: "org-kutch", last_seen: iso(3, 8), event_count: 40, mode: "live", is_simulated: false },
  ];

  const audit: Record<string, unknown>[] = [
    { event_type: "lab.result.recorded", title: "Lab result PASS", created_at: iso(14, 15), body: "HC-NIL-2408-01", chain_id: "" },
    { event_type: "certificate.issued", title: "Certificate issued", created_at: iso(14, 16), body: "CERT-NIL-2408-01", chain_id: "" },
    { event_type: "lab.result.recorded", title: "Lab result FAIL", created_at: iso(13, 12), body: "HC-KUT-2407-04", chain_id: "" },
    { event_type: "user.session", title: "Demo workspace opened", created_at: iso(0, 8), body: "Labeled demo data — not HoneyChain", chain_id: "" },
  ];

  return {
    users: DEMO_USERS,
    currentUser: DEMO_USERS[0],
    orgs,
    hives,
    readings,
    harvests,
    batches,
    tests,
    certificates,
    custody,
    notifications,
    devices,
    audit,
    listings: demoListings,
    orders: [],
    packages: demoPackages,
    scans: [],
    vanVisits: demoVanVisits,
  };
}

const demoListings: MarketListing[] = [
  {
    id: "listing-sun-01",
    batch_id: "batch-sun-01",
    seller_org_id: "org-sundarban",
    quantity_kg: 31,
    remaining_kg: 31,
    price_per_kg: 620,
    currency: "INR",
    status: "OPEN",
    notes: "Single-origin mangrove, Sundarbans. Lab certificate issued.",
    listed_at: iso(20),
    closed_at: null,
    client_id: "",
    batch_code: "HC-SUN-2408-02",
    batch_origin: "Sundarbans, West Bengal",
    batch_honey_type: "Mangrove",
    batch_trust_tier: "lab_verified",
    batch_status: "verified",
  },
];

const demoPackages: QrPackage[] = [
  {
    id: "pkg-sun-01",
    package_code: "HC-SUN-8F3A21",
    batch_id: "batch-sun-01",
    organization_id: "org-sundarban",
    quantity_kg: 10,
    status: "ACTIVE",
    first_scan_org: "",
    first_scan_at: null,
    scan_count: 0,
    issued_at: iso(19),
  },
];

const demoVanVisits: VanVisit[] = [
  {
    id: "van-1",
    van_code: "KVIC-VAN-02",
    officer_user_id: "u-kvic",
    organization_id: "org-kvic",
    target_org_id: "org-nilgiri",
    target_name: "Nilgiri Hills FPO — Kotagiri yards",
    status: "SCHEDULED",
    scheduled_for: iso(1),
    arrived_at: null,
    completed_at: null,
    notes: "Routine moisture check on the pending acacia lot.",
    samples: [],
  },
];

let state = seed();

export function resetDemo(role: Role | string) {
  state = seed();
  const user = DEMO_USERS.find((u) => u.role === role) || DEMO_USERS[0];
  state.currentUser = user;
  return user;
}

export function demoUserForRole(role: Role | string): UserMe {
  return DEMO_USERS.find((u) => u.role === role) || DEMO_USERS[0];
}

export const DEMO_ROLES: { role: Role; email: string; name: string }[] = [
  { role: "institution", email: "kvic@honeychain.in", name: "KVIC / Institution" },
  { role: "fpo", email: "org@honeychain.in", name: "FPO manager" },
  { role: "beekeeper", email: "demo@honeychain.in", name: "Beekeeper" },
  { role: "lab", email: "lab@honeychain.in", name: "Laboratory" },
  { role: "processor", email: "processor@honeychain.in", name: "Processor" },
  { role: "buyer", email: "buyer@honeychain.in", name: "Buyer" },
  { role: "admin", email: "admin@honeychain.in", name: "Platform admin" },
];

function scopedHives(): Hive[] {
  const role = state.currentUser.role;
  if (role === "beekeeper") return state.hives.filter((h) => h.beekeeper_id === state.currentUser.id);
  if (role === "fpo") return state.hives.filter((h) => h.org_id === state.currentUser.org_id);
  return state.hives;
}

function scopedBatches(): Batch[] {
  const role = state.currentUser.role;
  const org = state.currentUser.org_id;
  if (role === "fpo") return state.batches.filter((b) => b.organization_id === org);
  if (role === "beekeeper") return state.batches.filter((b) => b.organization_id === org);
  return state.batches;
}

function scopedNotes(): NotificationItem[] {
  const role = state.currentUser.role;
  if (role === "beekeeper") {
    return state.notifications.filter((n) => n.hive_id || n.category === "hive");
  }
  if (role === "lab") return state.notifications.filter((n) => n.category === "lab" || n.category === "quality");
  if (role === "processor") return state.notifications.filter((n) => n.batch_id);
  if (role === "fpo") {
    return state.notifications.filter((n) => n.category !== "org" || true);
  }
  return state.notifications;
}

function notFound(entity: string): never {
  throw new ApiError(404, `${entity} was not found.`);
}

function healthFor(hiveId: string): HealthScore {
  const latest = [...state.readings].filter((r) => r.hive_id === hiveId).sort((a, b) => (b.recorded_at || "").localeCompare(a.recorded_at || ""))[0];
  const temp = latest?.temperature_c ?? 33;
  const hum = latest?.humidity_percent ?? 55;
  let risk_level = "low";
  let risk_score = 18;
  const factors: HealthScore["contributing_factors"] = [];
  if (temp >= 36) {
    risk_level = "high";
    risk_score = 78;
    factors.push({ factor: "Temperature", contribution: "Above the usual range for this yard" });
  } else if (temp >= 35) {
    risk_level = "medium";
    risk_score = 48;
    factors.push({ factor: "Temperature", contribution: "Slightly high" });
  }
  if (hum >= 70) {
    risk_level = risk_score >= 70 ? "high" : "medium";
    risk_score = Math.max(risk_score, 62);
    factors.push({ factor: "Humidity", contribution: "Damp conditions" });
  }
  if (!factors.length) factors.push({ factor: "Readings", contribution: "Within the usual range" });
  const recommended =
    risk_level === "high"
      ? "Visit this hive today. Check ventilation, look at the brood, and write down what you see."
      : risk_level === "medium"
        ? "Include this hive in the next inspection round."
        : "No special visit is needed. Continue regular checks.";
  return {
    hive_id: hiveId,
    risk_level,
    risk_score,
    contributing_factors: factors,
    recommended_action: recommended,
    simulated: false,
    timestamp: latest?.recorded_at || iso(0),
  };
}

function passportFor(code: string): PassportResponse {
  const batch = state.batches.find(
    (b) => b.batch_code.toLowerCase() === code.toLowerCase() || b.id === code,
  );
  if (!batch) throw new ApiError(404, "Unknown batch or passport code.");
  const events = state.custody
    .filter((c) => c.batch_id === batch.id)
    .sort((a, b) => a.event_at.localeCompare(b.event_at))
    .map((c) => ({ type: c.action, at: c.event_at, actor: c.actor, detail: c.notes }));
  const harvest = state.harvests[0];
  const timeline = [
    { type: "Hive", at: harvest?.harvested_at, actor: "Lakshmi Devi", detail: "NG-KOT-01, Kotagiri slope" },
    { type: "Harvest", at: harvest?.harvested_at, actor: "Lakshmi Devi", detail: `${harvest?.quantity_kg ?? batch.quantity_kg} kg ${batch.honey_type}` },
    ...events.map((e) => ({
      type: e.type.replaceAll("_", " "),
      at: e.at,
      actor: e.actor,
      detail: e.detail,
    })),
  ];
  const test = state.tests.find((t) => t.batch_id === batch.id && t.result);
  return {
    subject: "batch",
    subject_code: batch.batch_code,
    batch_code: batch.batch_code,
    honey_type: batch.honey_type,
    origin: batch.origin,
    quantity_kg: batch.quantity_kg,
    trust_tier: batch.trust_tier,
    events: timeline,
    verification: test
      ? { lab_id: test.lab_id, result: test.result || undefined, tested_by: test.tested_by, tested_at: test.tested_at || undefined }
      : null,
    anchor: { chain_status: "unavailable" },
    genealogy: [batch.batch_code],
    caveat:
      "This passport is shown from the labeled demo workspace. Blockchain anchoring is not available here. Laboratory results are not a chemical guarantee of purity.",
  };
}

export const demoApi: HoneyChainApi = {
  login: async () => {
    throw new ApiError(403, `Live sign-in is required for HoneyChain. ${DEMO_PASSWORD_HINT}`);
  },
  me: async () => state.currentUser,
  platformStats: async () => ({
    registered_beekeepers: state.users.filter((u) => u.role === "beekeeper").length,
    organizations: state.orgs.length,
    hives: state.hives.length,
    harvests: state.harvests.length,
    honey_harvested_kg: state.harvests.reduce((s, h) => s + Number(h.quantity_kg || 0), 0),
    batches: state.batches.length,
    lab_tests: state.tests.length,
    certificates: state.certificates.length,
    iot_devices: state.devices.length,
    telemetry_events: state.readings.length,
    users: state.users.length,
    organization_status: {
      ACTIVE: state.orgs.filter((o) => o.status === "ACTIVE").length,
      PENDING: state.orgs.filter((o) => o.status === "PENDING").length,
    },
    batch_trust: {
      self_declared: state.batches.filter((b) => b.trust_tier === "self_declared").length,
      organization_verified: state.batches.filter((b) => b.trust_tier === "organization_verified").length,
      lab_verified: state.batches.filter((b) => b.trust_tier === "lab_verified").length,
    },
    batch_status: {
      verified: state.batches.filter((b) => b.status === "verified").length,
      lab_pending: state.batches.filter((b) => b.status === "lab_pending").length,
      lab_failed: state.batches.filter((b) => b.status === "lab_failed").length,
      collected: state.batches.filter((b) => b.status === "collected").length,
    },
  }),
  platformOrganizations: async () => state.orgs,
  platformAudit: async () =>
    state.audit.map((row, i) => ({
      id: String(row.id ?? `audit-${i}`),
      actor_user_id: String(row.actor_user_id ?? ""),
      actor_role: String(row.actor_role ?? ""),
      action: String(row.action ?? row.event_type ?? "audit_event"),
      target_type: String(row.target_type ?? ""),
      target_key: String(row.target_key ?? ""),
      detail: (row.detail as Record<string, unknown>) ?? {},
      created_at: String(row.created_at ?? ""),
    })),
  platformMembers: async (orgKey) =>
    state.users
      .filter((u) => u.org_id === orgKey)
      .map((u) => ({
        id: u.id,
        email: u.email,
        name: u.name,
        phone: u.phone,
        role: u.role,
        org_id: u.org_id,
        status: "ACTIVE",
        producer_id: "",
      })),
  platformBeekeepers: async () =>
    state.users
      .filter((u) => u.role === "beekeeper")
      .map((u) => ({
        id: u.id,
        email: u.email,
        name: u.name,
        phone: u.phone,
        role: u.role,
        org_id: u.org_id,
        status: "ACTIVE",
        producer_id: "",
      })),
  orgDashboard: async (orgId) => {
    const org = state.orgs.find((o) => o.id === orgId);
    if (!org) notFound("Organization");
    const orgBatches = state.batches.filter((b) => b.organization_id === orgId);
    const orgHives = state.hives.filter((h) => h.org_id === orgId);
    const orgHarvests = state.harvests.filter((h) => orgHives.some((x) => x.id === h.hive_id));
    const custodyForOrg = state.custody.filter((c) =>
      orgBatches.some((b) => b.id === c.batch_id),
    );
    const recent = [
      ...orgHarvests.map((h) => ({
        type: "harvest",
        label: `${h.quantity_kg} kg ${h.honey_type} harvested`,
        timestamp: h.harvested_at,
        entity_ref: h.id,
      })),
      ...orgBatches.map((b) => ({
        type: "batch",
        label: `Batch ${b.batch_code} → ${b.status}`,
        timestamp: b.created_at || "",
        entity_ref: b.id,
      })),
    ]
      .sort((a, b) => String(b.timestamp).localeCompare(String(a.timestamp)))
      .slice(0, 10);
    return {
      org_id: org.id,
      org_name: org.name,
      active_beekeepers: state.users.filter((u) => u.org_id === orgId && u.role === "beekeeper")
        .length,
      hives: orgHives.length,
      clusters: 1,
      honey_harvested_kg: orgHarvests.reduce((sum, h) => sum + Number(h.quantity_kg || 0), 0),
      collections: custodyForOrg.filter((c) => c.action === "COLLECTION").length,
      batches: orgBatches.length,
      verified_batches: orgBatches.filter(
        (b) => b.trust_tier === "lab_verified" || b.trust_tier === "blockchain_anchored",
      ).length,
      pending_actions: state.notifications.filter((n) => !n.read).length,
      recent_activity: recent,
      source: "demo",
    };
  },
  hives: async () => scopedHives(),
  hive: async (id) => scopedHives().find((h) => h.id === id) || notFound("Hive"),
  createHive: async (body) => {
    if (!body.hive_code.trim()) throw new ApiError(400, "Enter a hive code.");
    const hive: Hive = {
      id: `hive-${crypto.randomUUID()}`,
      hive_code: body.hive_code.trim(),
      beekeeper_id: state.currentUser.id,
      org_id: state.currentUser.org_id,
      status: "active",
      location: body.location || null,
      created_at: new Date().toISOString(),
    };
    state.hives = [hive, ...state.hives];
    return hive;
  },
  hiveReadings: async (id) => state.readings.filter((r) => r.hive_id === id),
  hiveHealth: async (id) => {
    if (!state.hives.some((h) => h.id === id)) notFound("Hive");
    return healthFor(id);
  },
  addReading: async (id, body) => {
    if (!state.hives.some((h) => h.id === id)) notFound("Hive");
    const reading: Reading = {
      id: `r-${crypto.randomUUID()}`,
      hive_id: id,
      temperature_c: body.temperature_c,
      humidity_percent: body.humidity_percent,
      weight_kg: body.weight_kg,
      recorded_at: new Date().toISOString(),
      source: "inspection",
    };
    state.readings = [reading, ...state.readings];
    return reading;
  },
  harvests: async () => {
    const hives = scopedHives();
    return state.harvests.filter((h) => hives.some((x) => x.id === h.hive_id) || state.currentUser.role === "admin" || state.currentUser.role === "institution" || state.currentUser.role === "fpo");
  },
  createHarvest: async (body) => {
    if (!body.hive_id) throw new ApiError(400, "Choose a hive.");
    if (!(body.quantity_kg > 0)) throw new ApiError(400, "Enter a harvest quantity.");
    const harvest: Harvest = {
      id: `hv-${crypto.randomUUID()}`,
      hive_id: body.hive_id,
      beekeeper_id: state.currentUser.id,
      harvested_at: new Date().toISOString(),
      quantity_kg: body.quantity_kg,
      honey_type: body.honey_type || "Not specified",
      collected: false,
    };
    state.harvests = [harvest, ...state.harvests];
    return harvest;
  },
  batches: async () => scopedBatches(),
  batch: async (id) => state.batches.find((b) => b.id === id) || notFound("Batch"),
  createBatch: async (body) => {
    if (state.batches.some((b) => b.batch_code === body.batch_code)) {
      throw new ApiError(409, "That batch code already exists.");
    }
    const batch: Batch = {
      id: `batch-${crypto.randomUUID()}`,
      batch_code: body.batch_code,
      status: body.status || "created",
      honey_type: body.honey_type || "Not specified",
      quantity_kg: body.quantity_kg,
      origin: body.origin || "",
      organization_id: state.currentUser.org_id,
      trust_tier: "self_declared",
      created_at: new Date().toISOString(),
      lab_result: null,
    };
    state.batches = [batch, ...state.batches];
    return batch;
  },
  batchState: async (id) => {
    const batch = state.batches.find((b) => b.id === id);
    if (!batch) notFound("Batch");
    const last = state.custody.filter((c) => c.batch_id === id).at(-1);
    return {
      batch_id: id,
      status: batch.status,
      trust_tier: batch.trust_tier,
      holder: { batch_id: id, holder_ref: last?.actor || "origin", since: last?.event_at },
    };
  },
  transitionBatch: async (id, toState, note = "") => {
    const batch = state.batches.find((b) => b.id === id);
    if (!batch) notFound("Batch");
    if (batch.status === toState) {
      return { batch_id: id, status: batch.status, changed: false };
    }
    const from = batch.status;
    batch.status = toState;
    return { batch_id: id, from_state: from, status: toState, changed: true, note } as {
      batch_id: string;
      from_state: string;
      status: string;
      changed: boolean;
    };
  },
  requestLabTest: async (batchId, labId, note = "") => {
    const batch = state.batches.find((b) => b.id === batchId);
    if (!batch) notFound("Batch");
    const test: LabTest = {
      id: `t-${crypto.randomUUID()}`,
      batch_id: batchId,
      lab_id: labId,
      status: "requested",
      result: null,
      requested_note: note,
      requested_at: new Date().toISOString(),
      batch_code: batch.batch_code,
      honey_type: batch.honey_type,
    };
    state.tests = [test, ...state.tests];
    return test;
  },
  genealogy: async (id) => {
    const batch = state.batches.find((b) => b.id === id);
    if (!batch) notFound("Batch");
    return [{ id: batch.id, batch_code: batch.batch_code, relationship: "source", quantity_kg: batch.quantity_kg }];
  },
  lineage: async (id) => {
    const batch = state.batches.find((b) => b.id === id);
    if (!batch) notFound("Batch");
    return {
      batch_id: id,
      genealogy: [
        { id: batch.id, batch_code: batch.batch_code, relationship: "source", quantity_kg: batch.quantity_kg },
      ],
      ledger: { chain_id: id, integrity_ok: true, event_count: state.custody.filter((c) => c.batch_id === id).length },
    };
  },
  // Aggregated provenance built only from records the demo workspace actually
  // holds — demo state has no batch↔harvest link rows, so material lineage
  // stays empty rather than being invented to fill the panel.
  batchProvenance: async (batchId) => {
    const batch = state.batches.find((b) => b.id === batchId);
    if (!batch) notFound("Batch");
    const custody = state.custody.filter((c) => c.batch_id === batchId);
    const lab_tests = state.tests.filter((t) => t.batch_id === batchId);
    const certificates = state.certificates.filter((c) => c.batch_id === batchId);
    const quantity = Number(batch.quantity_kg || 0);
    return {
      batch,
      harvest_sources: [],
      hive_sources: [],
      relations: [],
      custody,
      lab_tests,
      certificates,
      anchor: {},
      mass_balance: {
        batch_quantity_kg: quantity,
        allocated_kg: quantity,
        unallocated_kg: 0,
        balanced: true,
      },
      timeline: custody.map((c) => ({
        stage: c.action,
        at: c.event_at,
        ref: c.id,
        actor: c.actor,
        detail: c.notes,
      })),
      genealogy: [
        {
          id: batch.id,
          batch_code: batch.batch_code,
          relationship: "source",
          quantity_kg: batch.quantity_kg,
        },
      ],
    };
  },
  custody: async (id) => state.custody.filter((c) => c.batch_id === id),
  addCustodyEvent: async (id, body) => {
    const batch = state.batches.find((b) => b.id === id);
    if (!batch) notFound("Batch");
    if (body.action.toUpperCase().includes("PACK") && batch.lab_result !== "PASS" && batch.trust_tier !== "lab_verified") {
      throw new ApiError(409, "Packaging available after laboratory verification.");
    }
    const event: CustodyEvent = {
      id: `c-${crypto.randomUUID()}`,
      batch_id: id,
      action: body.action,
      actor: state.currentUser.name,
      notes: body.notes || "",
      event_at: new Date().toISOString(),
    };
    state.custody = [...state.custody, event];
    return event;
  },
  // Real laboratory directory, so the demo selector is driven by the same shape
  // the live endpoint returns instead of a hardcoded lab list.
  labs: async () =>
    state.orgs
      .filter((o) => /lab|laboratory/i.test(`${o.type} ${o.name}`))
      .map((o) => ({
        id: o.id,
        organization_key: o.organization_key,
        name: o.name,
        type: o.type,
        state: o.state,
        district: o.district,
        status: o.status,
      })),
  labQueue: async () => state.tests,
  labTests: async (batchId) => state.tests.filter((t) => t.batch_id === batchId),
  // The requested → in_progress step is real state, not decoration.
  startLabTest: async (testId) => {
    const test = state.tests.find((t) => t.id === testId);
    if (!test) notFound("Lab test");
    if (test.status === "requested") test.status = "in_progress";
    return test;
  },
  submitLabResult: async (testId, result, notes = "") => {
    const test = state.tests.find((t) => t.id === testId);
    if (!test) notFound("Lab test");
    test.result = result;
    test.status = result === "PASS" ? "passed" : "failed";
    test.tested_at = new Date().toISOString();
    test.tested_by = state.currentUser.name;
    if (notes) test.requested_note = notes;
    const batch = state.batches.find((b) => b.id === test.batch_id);
    if (batch) {
      batch.lab_result = result;
      batch.status = result === "PASS" ? "verified" : "lab_failed";
      batch.trust_tier = result === "PASS" ? "lab_verified" : "self_declared";
    }
    return test;
  },
  notifications: async () => {
    const items = scopedNotes();
    return { items, unread_count: items.filter((n) => !n.read).length };
  },
  markNotificationRead: async (id) => {
    const n = state.notifications.find((x) => x.notification_id === id);
    if (n) n.read = true;
  },
  assertions: async (ref) => [
    { id: `assert-${ref}`, entity_ref: ref, status: "recorded", source: "demo", nature: "declaration" },
  ],
  verification: async (ref) => {
    const batch = state.batches.find((b) => b.id === ref || b.batch_code === ref);
    return {
      trust_tier: batch?.trust_tier || "not_available",
      current_state: batch?.status || "unknown",
      caveat: "Demo verification state. Not a blockchain proof.",
    };
  },
  discrepancies: async (ref) => {
    if (ref === "batch-kut-01") {
      return {
        entity_ref: ref,
        open_count: 1,
        discrepancies: [
          {
            title: "Collection vs processor receipt",
            reference_quantity_kg: 22,
            claimed_quantity_kg: 18.5,
            delta_kg: 3.5,
            tolerance_kg: 1,
            status: "UNRESOLVED",
            reference_party: "Kutch Bee Collective",
            claimed_party: "Western Ghats Processing",
          },
        ],
      };
    }
    return { entity_ref: ref, discrepancies: [], open_count: 0 };
  },
  impacts: async (ref) => ({ entity_ref: ref, impacts: [], count: 0 }),
  evidence: async (id) => ({ id, status: "not_available" }),
  iotDevices: async () => {
    if (state.currentUser.role === "fpo" || state.currentUser.role === "beekeeper") {
      return state.devices.filter((d) => d.organization_id === state.currentUser.org_id);
    }
    return state.devices;
  },
  iotDevice: async (id) => state.devices.find((d) => d.device_id === id) || notFound("Device"),
  iotTelemetry: async (id) => {
    const device = state.devices.find((d) => d.device_id === id);
    if (!device) notFound("Device");
    const hiveId = device.assigned_hive_id;
    return state.readings
      .filter((r) => r.hive_id === hiveId)
      .map((r, i) => ({
        event_id: `t-${r.id}`,
        device_id: id,
        sequence: i + 1,
        timestamp: r.recorded_at || iso(0),
        payload: {
          temperature_c: r.temperature_c,
          humidity_percent: r.humidity_percent,
          hive_weight_kg: r.weight_kg,
        },
        is_simulated: false,
      }));
  },
  passport: async (code) => passportFor(code),
  batchCertificates: async (id) => state.certificates.filter((c) => c.batch_id === id),
  verifyCertificate: async (id) => {
    const cert = state.certificates.find((c) => c.certificate_id === id);
    if (!cert) throw new ApiError(404, "Certificate was not found.");
    return { certificate_id: cert.certificate_id, status: cert.status, verified: cert.status === "issued" };
  },
  issueCertificate: async (body) => {
    const batch = state.batches.find((b) => b.id === body.batch_id);
    if (!batch) notFound("Batch");
    if (batch.lab_result !== "PASS") {
      throw new ApiError(409, "A certificate can be issued only after a PASS result.");
    }
    const cert: Certificate = {
      certificate_id: `CERT-${batch.batch_code}`,
      batch_id: batch.id,
      lab_id: state.currentUser.org_id,
      certificate_type: body.certificate_type || "quality",
      issued_at: new Date().toISOString(),
      status: "issued",
      issuer_name: state.currentUser.name,
    };
    state.certificates = [cert, ...state.certificates.filter((c) => c.batch_id !== batch.id)];
    return cert;
  },
  revokeCertificate: async (id, reason) => {
    const cert = state.certificates.find((c) => c.certificate_id === id);
    if (!cert) notFound("Certificate");
    cert.status = "revoked";
    cert.revoked_at = new Date().toISOString();
    cert.revocation_reason = reason;
    return cert;
  },
  blockchainStatus: async () => ({
    adapter: "not_connected",
    status: "unavailable",
    ledger: "Not available",
    mode: "demo",
  }),
  blockchainHealth: async () => ({
    adapter: "not_connected",
    status: "unavailable",
    error: "Demo workspace is not connected to a ledger.",
    mode: "demo",
  }),
  blockchainTx: async () => {
    throw new ApiError(404, "No blockchain transaction is available in the demo workspace.");
  },
  productivityPrediction: async () => {
    throw new ApiError(0, "The productivity model is a separate HoneyChain service and is not part of this demo workspace.");
  },
  // The Offline Preview is not connected to HoneyChain, so the server-side
  // assistant genuinely does not exist here. Report it as unavailable instead
  // of inventing a reply that would look like real HoneyChain guidance.
  aiStatus: async (): Promise<AIStatus> => ({ enabled: false, configured: false, model: "" }),
  aiChat: async (_body: AIChatRequest): Promise<AIChatResponse> => {
    throw new ApiError(
      0,
      "Ask My Bee is a server-side HoneyChain assistant and is not available in the Offline Preview. The hive guidance below uses the labeled demo data only.",
    );
  },
  // --- Market linkage ---
  // Mirrors the live service gates exactly: the seller org is taken from the
  // batch, and a batch that has not passed the laboratory cannot be listed.
  marketListings: async (status) =>
    status ? state.listings.filter((l) => l.status === status) : [...state.listings],
  createListing: async (body) => {
    const batch = state.batches.find((b) => b.id === body.batch_id);
    if (!batch) notFound("Batch");
    if (batch.trust_tier !== "lab_verified" && batch.trust_tier !== "blockchain_anchored") {
      throw new ApiError(400, "Only a laboratory-verified batch may be listed for sale.");
    }
    if (batch.lab_result === "FAIL" || batch.status === "lab_failed") {
      throw new ApiError(409, `Batch status ${batch.status} blocks listing`);
    }
    if (body.quantity_kg > batch.quantity_kg) {
      throw new ApiError(400, "Cannot list more than the batch quantity.");
    }
    const listing: MarketListing = {
      id: `listing-${crypto.randomUUID()}`,
      batch_id: batch.id,
      seller_org_id: batch.organization_id,
      quantity_kg: body.quantity_kg,
      remaining_kg: body.quantity_kg,
      price_per_kg: body.price_per_kg,
      currency: body.currency || "INR",
      status: "OPEN",
      notes: body.notes || "",
      listed_at: new Date().toISOString(),
      closed_at: null,
      client_id: body.client_id || "",
      batch_code: batch.batch_code,
      batch_origin: batch.origin,
      batch_honey_type: batch.honey_type,
      batch_trust_tier: batch.trust_tier,
      batch_status: batch.status,
    };
    state.listings.push(listing);
    return listing;
  },
  withdrawListing: async (listingId) => {
    const listing = state.listings.find((l) => l.id === listingId);
    if (!listing) notFound("Listing");
    if (listing.status === "SOLD" || listing.status === "WITHDRAWN") return listing;
    listing.status = "WITHDRAWN";
    listing.closed_at = new Date().toISOString();
    return listing;
  },
  marketplace: async () => ({
    listings: state.listings.filter(
      (l) => l.status === "OPEN" && l.seller_org_id !== state.currentUser.org_id,
    ),
    orders: state.orders.filter((o) => o.buyer_org_id === state.currentUser.org_id),
  }),
  purchaseOrders: async () =>
    state.orders.filter(
      (o) =>
        o.buyer_org_id === state.currentUser.org_id ||
        o.seller_org_id === state.currentUser.org_id,
    ),
  createOrder: async (body) => {
    const listing = state.listings.find((l) => l.id === body.listing_id);
    if (!listing) notFound("Listing");
    if (listing.status !== "OPEN") {
      throw new ApiError(409, `Listing is ${listing.status}, not open`);
    }
    if (listing.seller_org_id === state.currentUser.org_id) {
      throw new ApiError(403, "An organization cannot purchase its own listing.");
    }
    if (body.quantity_kg > listing.remaining_kg) {
      throw new ApiError(409, `Only ${listing.remaining_kg} kg remain on this listing`);
    }
    const order: PurchaseOrder = {
      id: `order-${crypto.randomUUID()}`,
      listing_id: listing.id,
      batch_id: listing.batch_id,
      buyer_org_id: state.currentUser.org_id,
      buyer_user_id: state.currentUser.id,
      quantity_kg: body.quantity_kg,
      price_per_kg: listing.price_per_kg,
      total_amount: Math.round(body.quantity_kg * listing.price_per_kg * 100) / 100,
      currency: listing.currency,
      status: "REQUESTED",
      buyer_notes: body.buyer_notes || "",
      seller_notes: "",
      requested_at: new Date().toISOString(),
      decided_at: null,
      decided_by: "",
      fulfilled_at: null,
      batch_code: listing.batch_code,
      batch_origin: listing.batch_origin,
      batch_trust_tier: listing.batch_trust_tier,
      seller_org_id: listing.seller_org_id,
    };
    state.orders.push(order);
    return order;
  },
  decideOrder: async (orderId, accept, sellerNotes = "") => {
    const order = state.orders.find((o) => o.id === orderId);
    if (!order) notFound("Purchase order");
    if (order.status !== "REQUESTED") return order;
    const listing = state.listings.find((l) => l.id === order.listing_id);
    if (accept && order.quantity_kg > (listing?.remaining_kg ?? 0)) {
      throw new ApiError(409, "Only the remaining stock can be accepted");
    }
    order.status = accept ? "ACCEPTED" : "REJECTED";
    order.seller_notes = sellerNotes;
    order.decided_at = new Date().toISOString();
    order.decided_by = state.currentUser.id;
    if (accept && listing) {
      listing.remaining_kg = Math.round((listing.remaining_kg - order.quantity_kg) * 1000) / 1000;
      if (listing.remaining_kg <= 0) {
        listing.status = "SOLD";
        listing.closed_at = new Date().toISOString();
      }
    }
    return order;
  },
  fulfilOrder: async (orderId) => {
    const order = state.orders.find((o) => o.id === orderId);
    if (!order) notFound("Purchase order");
    if (order.status !== "ACCEPTED") {
      throw new ApiError(409, "Only an accepted order can be fulfilled");
    }
    // The sale is written to the batch's custody history exactly as the live
    // service does, so the demo never shows a completed sale the ledger lacks.
    state.custody.push({
      id: `c-${crypto.randomUUID()}`,
      batch_id: order.batch_id,
      action: "SALE",
      actor: state.currentUser.name,
      notes: `Market fulfilment of purchase order ${order.id} (${order.quantity_kg} kg)`,
      event_at: new Date().toISOString(),
    });
    order.status = "FULFILLED";
    order.fulfilled_at = new Date().toISOString();
    return order;
  },
  cancelOrder: async (orderId) => {
    const order = state.orders.find((o) => o.id === orderId);
    if (!order) notFound("Purchase order");
    if (order.status !== "REQUESTED") {
      throw new ApiError(409, "Only a pending request can be cancelled");
    }
    order.status = "CANCELLED";
    order.decided_at = new Date().toISOString();
    return order;
  },
  // --- QR packages ---
  qrPackages: async (batchId) =>
    batchId ? state.packages.filter((p) => p.batch_id === batchId) : [...state.packages],
  issuePackage: async (body) => {
    const batch = state.batches.find((b) => b.id === body.batch_id);
    if (!batch) notFound("Batch");
    if (body.quantity_kg > batch.quantity_kg) {
      throw new ApiError(400, "Package quantity exceeds the batch quantity.");
    }
    // Re-using an existing code resolves to the package that already owns that
    // identity — the rule that makes a duplicated print detectable rather than
    // producing two indistinguishable packages.
    const code =
      body.package_code || `HC-DEMO-${Math.random().toString(16).slice(2, 10).toUpperCase()}`;
    const existing = state.packages.find((p) => p.package_code === code);
    if (existing) return existing;
    const pkg: QrPackage = {
      id: `pkg-${crypto.randomUUID()}`,
      package_code: code,
      batch_id: batch.id,
      organization_id: batch.organization_id,
      quantity_kg: body.quantity_kg,
      status: "ACTIVE",
      first_scan_org: "",
      first_scan_at: null,
      scan_count: 0,
      issued_at: new Date().toISOString(),
    };
    state.packages.push(pkg);
    return pkg;
  },
  recallPackage: async (code) => {
    const pkg = state.packages.find((p) => p.package_code === code);
    if (!pkg) notFound("Package");
    pkg.status = "RECALLED";
    return pkg;
  },
  scanPackage: async (code) => {
    // Same signals as the live detector, derived from demo state. An unissued
    // code is reported UNKNOWN_CODE — the demo will not return a clean scan for
    // a label that was never issued.
    const pkg = state.packages.find((p) => p.package_code === code);
    const signals: QrSignal[] = [];
    if (!pkg) {
      signals.push({
        code: "UNKNOWN_CODE",
        detail: "No package with this code has been issued.",
      });
    } else {
      if (pkg.status === "RECALLED") {
        signals.push({ code: "RECALLED", detail: "This package was recalled by its issuer." });
      }
      if (pkg.first_scan_org) {
        signals.push(
          pkg.first_scan_org !== state.currentUser.org_id
            ? {
                code: "REUSE_BY_OTHER_ORG",
                detail: `Already scanned by organization ${pkg.first_scan_org}; this scan came from ${state.currentUser.org_id}.`,
              }
            : {
                code: "DUPLICATE_PRINT",
                detail:
                  "This code was already scanned by the same organization; two labels appear to share one identity.",
              },
        );
      }
    }
    const result = signals.length ? "SUSPICIOUS" : "CLEAR";
    const prior = pkg?.scan_count ?? 0;
    if (pkg) {
      pkg.scan_count += 1;
      if (!pkg.first_scan_at) {
        pkg.first_scan_at = new Date().toISOString();
        pkg.first_scan_org = state.currentUser.org_id;
        if (!signals.length) pkg.status = "SCANNED";
      }
    }
    const scan: QrScanResult = {
      package: pkg || null,
      result,
      signals,
      prior_scan_count: prior,
    };
    // Persisted as a record, mirroring the live `qr_scans` row, so the flagged
    // list and the immediate result agree on the same history.
    state.scans.unshift({
      id: `scan-${crypto.randomUUID()}`,
      package_code: code,
      batch_id: pkg?.batch_id ?? null,
      scanner_user_id: state.currentUser.id,
      scanner_role: state.currentUser.role,
      organization_id: state.currentUser.org_id,
      result,
      signals,
      scanned_at: new Date().toISOString(),
    });
    return scan;
  },
  suspiciousScans: async () => state.scans.filter((s) => s.result === "SUSPICIOUS"),
  // --- Mobile processing van ---
  vanDashboard: async () => {
    const visits = state.vanVisits;
    return {
      visits,
      counts: {
        SCHEDULED: visits.filter((v) => v.status === "SCHEDULED").length,
        ARRIVED: visits.filter((v) => v.status === "ARRIVED").length,
        SAMPLE_COLLECTED: visits.filter((v) => v.status === "SAMPLE_COLLECTED").length,
        COMPLETED: visits.filter((v) => v.status === "COMPLETED").length,
      },
    };
  },
  vanVisits: async (status) =>
    status ? state.vanVisits.filter((v) => v.status === status) : [...state.vanVisits],
  scheduleVanVisit: async (body) => {
    const visit: VanVisit = {
      id: `van-${crypto.randomUUID()}`,
      van_code: body.van_code,
      officer_user_id: state.currentUser.id,
      organization_id: state.currentUser.org_id,
      target_org_id: body.target_org_id || "",
      target_name: body.target_name || "",
      status: "SCHEDULED",
      scheduled_for: new Date().toISOString(),
      arrived_at: null,
      completed_at: null,
      notes: body.notes || "",
      samples: [],
    };
    state.vanVisits.push(visit);
    return visit;
  },
  advanceVanVisit: async (visitId) => {
    const visit = state.vanVisits.find((v) => v.id === visitId);
    if (!visit) notFound("Van visit");
    const next: Record<string, VanVisit["status"]> = {
      SCHEDULED: "ARRIVED",
      ARRIVED: "SAMPLE_COLLECTED",
      SAMPLE_COLLECTED: "COMPLETED",
    };
    const to = next[visit.status];
    if (!to) throw new ApiError(409, `Visit is already ${visit.status}`);
    visit.status = to;
    if (to === "ARRIVED") visit.arrived_at = new Date().toISOString();
    if (to === "COMPLETED") visit.completed_at = new Date().toISOString();
    return visit;
  },
  collectVanSample: async (visitId, body) => {
    const visit = state.vanVisits.find((v) => v.id === visitId);
    if (!visit) notFound("Van visit");
    if (visit.status !== "ARRIVED" && visit.status !== "SAMPLE_COLLECTED") {
      throw new ApiError(409, "The van must be on site before a sample is collected.");
    }
    if (!state.batches.some((b) => b.id === body.batch_id)) {
      throw new ApiError(400, "Batch not found");
    }
    const sample: VanSample = {
      id: `sample-${crypto.randomUUID()}`,
      visit_id: visitId,
      batch_id: body.batch_id,
      sample_code: body.sample_code,
      quantity_kg: body.quantity_kg ?? null,
      result: "PENDING",
      moisture_percent: body.moisture_percent ?? null,
      notes: body.notes || "",
      collected_at: new Date().toISOString(),
      is_laboratory_certificate: false,
    };
    visit.samples.push(sample);
    if (visit.status === "ARRIVED") visit.status = "SAMPLE_COLLECTED";
    return sample;
  },
  recordVanResult: async (sampleId, result, notes = "") => {
    for (const visit of state.vanVisits) {
      const sample = visit.samples.find((s) => s.id === sampleId);
      if (!sample) continue;
      sample.result = result;
      if (notes) sample.notes = notes;
      // A van observation never certifies a batch: the tier is echoed back
      // unchanged and the flag stays false.
      const batch = state.batches.find((b) => b.id === sample.batch_id);
      sample.is_laboratory_certificate = false;
      sample.batch_trust_tier = batch?.trust_tier || "";
      return sample;
    }
    notFound("Van sample");
  },
  health: async () => ({
    status: "ok",
    service: "honeychain-web-portal",
    mode: "demo",
    note: "Labeled demo workspace — not connected to HoneyChain.",
  }),
};

export function setDemoUser(user: UserMe) {
  state.currentUser = user;
}
