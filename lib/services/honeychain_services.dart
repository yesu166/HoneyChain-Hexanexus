import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/demo_seed.dart';
import '../models/domain.dart';
import '../repositories/local_honeychain_repository.dart';

class HiveInsightService {
  HiveInsight createInsight(Hive hive, List<HiveReading> readings) {
    if (readings.isEmpty) {
      return const HiveInsight(
        hiveId: '',
        healthScore: 90,
        riskLevel: RiskLevel.healthy,
        riskExplanation: 'No readings available yet.',
        productivityInsight: '',
        inspectionRecommendation: 'Continue normal weekly inspection.',
      );
    }
    final firstWeight = readings.first.weightKg;
    final latest = readings.last;
    final weightChange = (latest.weightKg - firstWeight) / firstWeight * 100;

    final tempStatus = latest.temperatureC > 35 ? ReadingStatus.high : ReadingStatus.healthy;
    final humidityStatus = latest.humidityPercent > 68 ? ReadingStatus.high : ReadingStatus.healthy;
    final weightStatus = weightChange <= -5
        ? WeightStatus.dropping
        : (weightChange >= 1 ? WeightStatus.growing : WeightStatus.steady);

    RiskLevel risk;
    String adviceCode;
    if (tempStatus == ReadingStatus.high) {
      risk = RiskLevel.highRisk;
      adviceCode = 'cool';
    } else if (humidityStatus == ReadingStatus.high) {
      risk = latest.humidityPercent >= 75 ? RiskLevel.highRisk : RiskLevel.attentionRequired;
      adviceCode = 'ventilation';
    } else {
      risk = RiskLevel.healthy;
      adviceCode = 'inspect';
    }

    final score = switch (risk) {
      RiskLevel.highRisk => 55,
      RiskLevel.attentionRequired => 70,
      RiskLevel.healthy => 90,
    };

    return HiveInsight(
      hiveId: hive.id,
      healthScore: score,
      riskLevel: risk,
      riskExplanation: switch (risk) {
        RiskLevel.highRisk =>
          'Hive ${hive.name} needs your attention today.',
        RiskLevel.attentionRequired =>
          'Hive ${hive.name} needs a small adjustment.',
        RiskLevel.healthy => 'Hive ${hive.name} is doing well.',
      },
      productivityInsight: weightStatus == WeightStatus.growing
          ? 'Hive weight is increasing.'
          : 'Hive weight is steady.',
      inspectionRecommendation: risk == RiskLevel.healthy
          ? 'Continue normal weekly inspection.'
          : 'Please take action as recommended.',
      tempStatus: tempStatus,
      humidityStatus: humidityStatus,
      weightStatus: weightStatus,
      adviceCode: adviceCode,
    );
  }
}

class BatchService {
  BatchService(this.repository);
  final HoneychainRepository repository;

  Batch createBatch({required List<Harvest> harvests, required String organizationId, required String origin}) {
    final quantity = harvests.fold<double>(0, (sum, harvest) => sum + harvest.quantityKg);
    return createBatchDirect(
      organizationId: organizationId,
      origin: origin,
      honeyType: harvests.isEmpty ? 'Honey' : harvests.first.honeyType,
      quantityKg: quantity,
      harvests: harvests,
    );
  }

  Batch createBatchDirect({
    required String organizationId,
    required String origin,
    required String honeyType,
    required double quantityKg,
    DateTime? createdAt,
    List<Harvest> harvests = const [],
  }) {
    final sequence = (repository.batches.length + 127).toString().padLeft(5, '0');
    final created = createdAt ?? DateTime.now();
    final batch = Batch(
      id: 'batch-$sequence',
      code: 'HC-TN-$sequence',
      organizationId: organizationId,
      honeyType: honeyType,
      origin: origin,
      quantityKg: quantityKg,
      createdAt: created,
      status: BatchStatus.created,
    );
    repository.addBatch(batch, harvests.map((harvest) => BatchHarvest(batchId: batch.id, harvestId: harvest.id, quantityKg: harvest.quantityKg)).toList());
    repository.addEvent(AuditEvent(id: 'event-$sequence-created', batchId: batch.id, type: 'CREATED', actor: 'Nilgiris Honey FPO', recordedAt: created, description: 'Batch ${batch.code} created (${quantityKg.toStringAsFixed(1)} kg).'));
    return batch;
  }

  Batch updateStatus(Batch batch, BatchStatus status) { final updated = batch.copyWith(status: status); repository.updateBatch(updated); return updated; }

  /// Physically splits one batch into several sub-batches.
  ///
  /// Every child gets its own code, a [RelationType.split] relation to the
  /// parent and a SPLIT_FROM audit event, so the genealogy stays truthful.
  /// The parent batch is left untouched (a split creates, never rewrites).
  ///
  /// Guards: parts must sum to the parent quantity, otherwise the service
  /// throws instead of silently producing inconsistent custody.
  List<Batch> splitBatch(Batch parent, List<double> parts) {
    if (parts.isEmpty) {
      throw ArgumentError('At least one part is required to split a batch.');
    }
    final total = parts.fold<double>(0, (sum, p) => sum + p);
    if ((total - parent.quantityKg).abs() > 0.001) {
      throw ArgumentError(
        'Split parts must sum to the parent quantity '
        '(${parent.quantityKg.toStringAsFixed(1)} kg), got $total.',
      );
    }

    final children = <Batch>[];
    for (var i = 0; i < parts.length; i++) {
      final sequence =
          (repository.batches.length + 127).toString().padLeft(5, '0');
      final now = DateTime.now();
      final child = Batch(
        id: 'batch-$sequence',
        code: 'HC-TN-$sequence',
        organizationId: parent.organizationId,
        honeyType: parent.honeyType,
        origin: parent.origin,
        quantityKg: parts[i],
        createdAt: now,
        status: parent.status,
        syncStatus: SyncStatus.synced,
        displayStatus: parent.displayStatus,
      );
      repository.addBatch(child, const []);
      repository.addRelation(BatchRelation(
        id: 'rel-$sequence-${now.microsecondsSinceEpoch}',
        parentBatchId: parent.id,
        childBatchId: child.id,
        type: RelationType.split,
        createdAt: now,
      ));
      repository.addEvent(AuditEvent(
        id: 'event-$sequence-${now.microsecondsSinceEpoch}-split',
        batchId: child.id,
        type: 'SPLIT_FROM',
        actor: 'Organization / FPO',
        recordedAt: now,
        description:
            'Split from ${parent.code} (${parts[i].toStringAsFixed(1)} kg).',
      ));
      children.add(child);
    }
    return children;
  }

  /// Merges several lots into one new consolidated batch.
  ///
  /// The merged batch aggregates the children's harvest links and records an
  /// [RelationType.aggregate] relation per child (genealogy preserved). Trust
  /// of the merged result equals the weakest child's tier; callers must route
  /// that decision through [TrustService.mergeTier] and not guess it here.
  Batch mergeBatches(List<Batch> children) {
    if (children.isEmpty) {
      throw ArgumentError('At least one batch is required to merge.');
    }
    final first = children.first;
    final total =
        children.fold<double>(0, (sum, c) => sum + c.quantityKg);
    final sequence =
        (repository.batches.length + 127).toString().padLeft(5, '0');
    final now = DateTime.now();
    final homogeneousStatus = children.every(
          (c) => c.status == first.status,
        );
    final merged = Batch(
      id: 'batch-$sequence',
      code: 'HC-TN-$sequence',
      organizationId: first.organizationId,
      honeyType: first.honeyType,
      origin: first.origin,
      quantityKg: total,
      createdAt: now,
      status: homogeneousStatus ? first.status : BatchStatus.processing,
      syncStatus: SyncStatus.synced,
    );

    final links = <BatchHarvest>[];
    for (final child in children) {
      links.addAll(repository.harvestsForBatch(child.id));
      repository.addRelation(BatchRelation(
        id: 'rel-$sequence-${child.id}',
        parentBatchId: merged.id,
        childBatchId: child.id,
        type: RelationType.aggregate,
        createdAt: now,
      ));
      repository.addEvent(AuditEvent(
        id: 'event-$sequence-${child.code}-aggregate',
        batchId: merged.id,
        type: 'AGGREGATED_FROM',
        actor: 'Organization / FPO',
        recordedAt: now,
        description:
            'Aggregated from ${child.code} (${child.quantityKg.toStringAsFixed(1)} kg).',
      ));
    }
    repository.addBatch(merged, links);
    return merged;
  }

  /// Records a correction against a batch WITHOUT rewriting its history.
  ///
  /// A CORRECTION audit event is always appended. Optional mutable fields
  /// (origin / honeyType / quantityKg) are updated on the batch itself; every
  /// earlier record keeps its original value so the audit trail stays intact.
  Batch recordCorrection(
    Batch batch, {
    required String description,
    String? actor,
    String? origin,
    String? honeyType,
    double? quantityKg,
  }) {
    final now = DateTime.now();
    repository.addEvent(AuditEvent(
      id: 'event-${batch.id}-correction-${now.microsecondsSinceEpoch}',
      batchId: batch.id,
      type: 'CORRECTION',
      actor: actor ?? 'Organization / FPO',
      recordedAt: now,
      description: description,
    ));
    if (origin == null && honeyType == null && quantityKg == null) {
      return batch;
    }
    final updated = batch.copyWith(
      origin: origin,
      honeyType: honeyType,
      quantityKg: quantityKg,
    );
    repository.updateBatch(updated);
    return updated;
  }
}

class VerificationService {
  VerificationService(this.repository, this.batchService);
  final HoneychainRepository repository;
  final BatchService batchService;

  LabVerification verify(Batch batch, VerificationStatus status) {
    final now = DateTime.now();
    final verification = LabVerification(id: '${batch.id}-verification', batchId: batch.id, labOrganizationId: DemoSeed.lab.id, status: status, testedAt: now, summary: status == VerificationStatus.pass ? 'Moisture and sugar profile are within expected ranges. Evidence supports quality verification.' : 'Further assessment is required before release.', evidence: [EvidenceFile(id: '${batch.id}-report', name: 'lab-report-${batch.code}.pdf', mimeType: 'application/pdf', uploadedAt: now)]);
    repository.addVerification(verification);
    batchService.updateStatus(batch, status == VerificationStatus.pass ? BatchStatus.labVerified : BatchStatus.labFailed);
    repository.addEvent(AuditEvent(id: '${batch.id}-lab', batchId: batch.id, type: 'LAB_${status.name.toUpperCase()}', actor: DemoSeed.lab.name, recordedAt: now, description: 'Laboratory verification: ${status.name}.'));
    return verification;
  }
}

class CustodyService {
  CustodyService(this.repository, this.batchService);
  final HoneychainRepository repository;
  final BatchService batchService;
  CustodyEvent accept(Batch batch) {
    final now = DateTime.now();
    final event = CustodyEvent(id: '${batch.id}-custody', batchId: batch.id, fromOrganizationId: DemoSeed.beekeeperOrg.id, toOrganizationId: DemoSeed.fpo.id, recordedAt: now, note: 'Collection center accepted custody from beekeeper.');
    repository.addCustody(event);
    batchService.updateStatus(batch, BatchStatus.collected);
    repository.addEvent(AuditEvent(id: '${batch.id}-collected', batchId: batch.id, type: 'COLLECTED', actor: DemoSeed.fpo.name, recordedAt: now, description: event.note));
    return event;
  }
}

class BlockchainService {
  BlockchainService(this.repository);
  final HoneychainRepository repository;

  BlockchainAnchor anchor(
    Batch batch,
    String eventType, {
    Map<String, dynamic> details = const {},
  }) {
    final now = DateTime.now();
    final anchor = BlockchainAnchor(
      id: '${batch.id}-$eventType-anchor',
      batchId: batch.id,
      eventType: eventType,
      // Real SHA-256 commitment of the canonical local anchor payload.
      // This is a hash, not a blockchain transaction id; the local anchor
      // remains marked as demo until the live Fabric path is used.
      anchorId: 'sha256:${sha256.convert(utf8.encode(jsonEncode({
        'eventType': eventType,
        'details': details,
      })))}',
      anchoredAt: now,
      isMock: true,
      details: details,
    );
    repository.addAnchor(anchor);
    repository.addEvent(AuditEvent(
      id: '${anchor.id}-event',
      batchId: batch.id,
      type: 'ANCHORED',
      actor: 'HoneyChain Integrity Layer',
      recordedAt: now,
      description:
          '$eventType record anchored to prototype mock infrastructure.',
    ));
    return anchor;
  }

  BlockchainAnchor anchorPackaging(
    PackagingBatch packagingBatch,
    String eventType,
  ) {
    final now = DateTime.now();
    final anchor = BlockchainAnchor(
      id: '${packagingBatch.packagingBatchId}-$eventType-anchor',
      batchId: packagingBatch.sourceBatchId,
      packagingBatchId: packagingBatch.packagingBatchId,
      eventType: eventType,
      anchorId: 'MOCK-${packagingBatch.packagingBatchId}-$eventType',
      anchoredAt: now,
      isMock: true,
      details: {
        'sourceBatchId': packagingBatch.sourceBatchId,
        'packagingBatchId': packagingBatch.packagingBatchId,
        'buyerId': packagingBatch.buyerId,
        'quantityGrams': packagingBatch.quantityUsedGrams,
        'jarSizeGrams': packagingBatch.jarSizeGrams,
        'jarCount': packagingBatch.jarCount,
      },
    );
    repository.addAnchor(anchor);
    repository.addEvent(AuditEvent(
      id: '${anchor.id}-event',
      batchId: packagingBatch.sourceBatchId,
      type: 'PACKAGING_ANCHORED',
      actor: 'HoneyChain Packaging Integrity Layer',
      recordedAt: now,
      description:
          'Packaging allocation ${packagingBatch.packagingBatchId} (${packagingBatch.jarCount} jars) anchored to prototype mock blockchain.',
    ));
    return anchor;
  }
}

class GenealogyService {
  GenealogyService(this.repository);
  final HoneychainRepository repository;
  List<BatchRelation> relationsFor(Batch batch) => repository.relationsForBatch(batch.id);
}

class PassportService {
  PassportService(this.repository);
  final HoneychainRepository repository;
  QRPassport create(Batch batch) { final passport = QRPassport(slug: batch.code.toLowerCase(), batchId: batch.id, createdAt: DateTime.now()); repository.addPassport(passport); return passport; }
  QRPassport? find(String slug) => repository.passportForSlug(slug);
}

class MarketplaceService {
  MarketplaceService(this.repository, this.batchService);
  final HoneychainRepository repository;
  final BatchService batchService;
  MarketplaceListing list(Batch batch) { final listing = MarketplaceListing(id: '${batch.id}-listing', batchId: batch.id, quantityKg: batch.quantityKg, pricePerKg: 650, isActive: true); repository.addListing(listing); batchService.updateStatus(batch, BatchStatus.listed); return listing; }
  PurchaseRequest request(MarketplaceListing listing, String buyerName, double quantityKg, String message) { final request = PurchaseRequest(id: '${listing.id}-request', listingId: listing.id, buyerName: buyerName, quantityKg: quantityKg, message: message, createdAt: DateTime.now()); repository.addPurchaseRequest(request); return request; }
}
