import '../models/domain.dart';

/// Result of pushing one locally-created record to the backend.
class SyncResult {
  final bool success;
  final String? backendId;
  const SyncResult.success([this.backendId]) : success = true;
  const SyncResult.failure() : success = false, backendId = null;
}

/// Boundary with the remote backend. The real implementation (FastAPI +
/// Supabase) replaces the mock later; the offline queue stays unchanged.
abstract class SyncGateway {
  Future<SyncResult> pushHarvest(Harvest harvest);
  Future<SyncResult> pushBatch(Batch batch);
}

/// Simulated backend used until the FastAPI service exists.
///
/// Idempotent: a given client record id is accepted only once, so re-syncing
/// can never create duplicate harvests or batches.
class MockSyncGateway implements SyncGateway {
  final Set<String> _accepted = {};

  @override
  Future<SyncResult> pushHarvest(Harvest harvest) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _accepted.add(harvest.id) ? SyncResult.success(harvest.id) : const SyncResult.success('');
  }

  @override
  Future<SyncResult> pushBatch(Batch batch) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _accepted.add(batch.id) ? SyncResult.success(batch.id) : const SyncResult.success('');
  }
}

/// Drains the local pending queue whenever connectivity returns.
class SyncEngine {
  SyncEngine(this.gateway);

  final SyncGateway gateway;
  bool _syncing = false;

  bool get isSyncing => _syncing;

  Future<void> process({
    required List<Harvest> pendingHarvests,
    required List<Batch> pendingBatches,
    required void Function(Harvest harvest) onHarvestSynced,
    required void Function(Batch batch) onBatchSynced,
  }) async {
    if (_syncing) return;
    _syncing = true;
    try {
      for (final harvest in pendingHarvests) {
        final result = await gateway.pushHarvest(harvest);
        if (result.success) onHarvestSynced(harvest);
      }
      for (final batch in pendingBatches) {
        final result = await gateway.pushBatch(batch);
        if (result.success) onBatchSynced(batch);
      }
    } finally {
      _syncing = false;
    }
  }
}