import '../models/domain.dart';

/// Deterministic demo data for the beekeeper-facing HoneyChain app.
/// Mirrors the reference UI narrative: generic beekeeper demo
/// · Local Apiary · 4 hives.
class DemoSeed {
  static final now = DateTime.now()

  static const profile = BeekeeperProfile(
    name: 'Beekeeper',
    memberId: 'HC-9082',
    organizationName: 'Local Honey Cooperative',
    location: 'Local Apiary',
    phone: '9876543210',
  );

  static const cluster = Cluster(
    id: 'cluster-tn-01',
    name: 'Local Honey Cluster',
    state: 'Tamil Nadu',
  );
  static const beekeeperOrg = Organization(
    id: 'org-beekeeper-01',
    name: 'My Apiary',
    type: OrganizationType.fpo,
    clusterId: 'cluster-tn-01',
  );
  static const fpo = Organization(
    id: 'org-fpo-01',
    name: 'Local Honey Cooperative',
    type: OrganizationType.fpo,
    clusterId: 'cluster-tn-01',
  );
  static const lab = Organization(
    id: 'org-lab-01',
    name: 'Regional Honey Laboratory',
    type: OrganizationType.lab,
    clusterId: 'cluster-tn-01',
  );
  static const ravi = User(
    id: 'user-beekeeper',
    name: 'Beekeeper',
    role: UserRole.beekeeper,
    organizationId: 'org-beekeeper-01',
  );

  /// Cooperating organizations / FPOs for the collection & batching flow.
  /// Multi-organization prototype — the active organization is selectable.
  static const organizations = <Organization>[
    Organization(
      id: 'ORG-TN-001',
      name: 'Local Honey Cooperative',
      type: OrganizationType.fpo,
      clusterId: 'cluster-tn-01',
    ),
    Organization(
      id: 'ORG-TN-002',
      name: 'Tamil Honey Cooperative',
      type: OrganizationType.fpo,
      clusterId: 'cluster-tn-01',
    ),
    Organization(
      id: 'ORG-TN-003',
      name: 'Private Honey Collection Centre',
      type: OrganizationType.fpo,
      clusterId: 'cluster-tn-01',
    ),
  ];

  /// Small realistic demo apiary — four hives that drive the whole narrative:
  /// one healthy, two flagged by the seeded alerts, and the anomalous hive the
  /// disease/IoT simulations exercise. No explosion of fake hives.
  static const hives = [
    Hive(id: 'hive-001', name: 'Hive #1', detail: 'Mango Orchard', beekeeperId: 'user-beekeeper', organizationId: 'org-beekeeper-01', location: 'North Corner', honeyType: 'Floral Honey'),
    Hive(id: 'hive-002', name: 'Hive #2', detail: 'Mustard Field', beekeeperId: 'user-beekeeper', organizationId: 'org-beekeeper-01', location: 'Near stream · East side', honeyType: 'Mustard Honey'),
    Hive(id: 'hive-003', name: 'Hive #3', detail: 'Neem Grove', beekeeperId: 'user-beekeeper', organizationId: 'org-beekeeper-01', location: 'Center Block', honeyType: 'Neem Honey'),
    Hive(id: 'hive-004', name: 'Hive #4', detail: 'Guava Patch', beekeeperId: 'user-beekeeper', organizationId: 'org-beekeeper-01', location: 'South Fence', honeyType: 'Wildflower Honey'),
  ];

  static List<HiveReading> readingsFor(String hiveId) {
    final temp = switch (hiveId) {
      'hive-004' => 37.4,
      _ => 32.5,
    };
    final humidity = switch (hiveId) {
      'hive-002' => 71.0,
      'hive-003' => 77.0,
      _ => 63.0,
    };
    final weight = switch (hiveId) {
      'hive-001' => 26.0,
      'hive-002' => 24.0,
      'hive-003' => 21.0,
      'hive-004' => 19.0,
      _ => 20.0 + hiveId.hashCode % 6,
    };
    return List.generate(7, (index) {
      final daysAgo = 6 - index;
      final drift = (index - 3) * 0.15;
      return HiveReading(
        id: '$hiveId-reading-$index',
        hiveId: hiveId,
        recordedAt: now.subtract(Duration(days: daysAgo)),
        temperatureC: temp + drift,
        humidityPercent: humidity + index * 0.4,
        weightKg: weight + index * 0.12,
      );
    });
  }

  static List<Harvest> get harvests => [
    Harvest(id: 'harvest-001', hiveId: 'hive-001', beekeeperId: 'user-beekeeper', harvestedAt: DateTime(2026, 8, 12), honeyType: 'Floral Honey', quantityKg: 12),
    Harvest(id: 'harvest-002', hiveId: 'hive-002', beekeeperId: 'user-beekeeper', harvestedAt: DateTime(2026, 8, 25), honeyType: 'Mustard Honey', quantityKg: 15),
    Harvest(id: 'harvest-003', hiveId: 'hive-003', beekeeperId: 'user-beekeeper', harvestedAt: DateTime(2026, 7, 10), honeyType: 'Neem Honey', quantityKg: 10),
    Harvest(id: 'harvest-004', hiveId: 'hive-004', beekeeperId: 'user-beekeeper', harvestedAt: DateTime(2026, 7, 5), honeyType: 'Wildflower Honey', quantityKg: 12),
  ];

  static List<Batch> get batches => [
    Batch(
      id: 'batch-024',
      code: 'Batch #24',
      organizationId: 'org-fpo-01',
      honeyType: 'Mustard Honey',
      origin: 'Local Apiary',
      quantityKg: 24,
      createdAt: DateTime(2026, 8, 12),
      status: BatchStatus.labVerified,
      displayStatus: BatchDisplayStatus.verified,
    ),
    Batch(
      id: 'batch-023',
      code: 'Batch #23',
      organizationId: 'org-fpo-01',
      honeyType: 'Floral Honey',
      origin: 'Local Apiary',
      quantityKg: 18,
      createdAt: DateTime(2026, 8, 1),
      status: BatchStatus.labPending,
      displayStatus: BatchDisplayStatus.pending,
    ),
    Batch(
      id: 'batch-022',
      code: 'Batch #22',
      organizationId: 'org-fpo-01',
      honeyType: 'Neem Honey',
      origin: 'Local Apiary',
      quantityKg: 32,
      createdAt: DateTime(2026, 7, 15),
      status: BatchStatus.labPending,
      displayStatus: BatchDisplayStatus.inLab,
    ),
  ];

  static List<BatchHarvest> get batchLinks => const [
    BatchHarvest(batchId: 'batch-024', harvestId: 'harvest-002', quantityKg: 15),
    BatchHarvest(batchId: 'batch-023', harvestId: 'harvest-001', quantityKg: 12),
    BatchHarvest(batchId: 'batch-022', harvestId: 'harvest-003', quantityKg: 10),
    BatchHarvest(batchId: 'batch-022', harvestId: 'harvest-004', quantityKg: 12),
  ];

  static List<LabVerification> get verifications => [
    LabVerification(
      id: 'batch-024-verification',
      batchId: 'batch-024',
      labOrganizationId: 'org-lab-01',
      status: VerificationStatus.pass,
      testedAt: DateTime(2026, 8, 20, 16),
      summary: 'Moisture and sugar profile are within expected ranges. No indicators of adulteration were found.',
      evidence: [EvidenceFile(id: 'batch-024-report', name: 'lab-report-Batch-#24.pdf', mimeType: 'application/pdf', uploadedAt: DateTime(2026, 8, 20, 16))],
    ),
  ];

  static List<HiveAlert> get alerts => [
    HiveAlert(
      id: 'alert-hive-003-care',
      type: AlertType.humidity,
      severity: AlertSeverity.care,
      hiveId: 'hive-003',
      createdAt: DateTime(2026, 8, 27, 8),
    ),
    HiveAlert(
      id: 'alert-hive-004-cooling',
      type: AlertType.temperature,
      severity: AlertSeverity.urgent,
      hiveId: 'hive-004',
      createdAt: DateTime(2026, 8, 27, 11),
    ),
    HiveAlert(
      id: 'alert-batch-024-verified',
      type: AlertType.verification,
      severity: AlertSeverity.info,
      batchId: 'batch-024',
      batchLabel: 'Batch #24',
      createdAt: DateTime(2026, 8, 21, 17),
    ),
  ];
}