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

/// Drains the local pending queue whenever connectivity allows.
///
/// Pushes records in dependency order (harvests before batches), retries each
/// item up to [maxAttempts] times within a pass, and reports per-item
/// success/failure through callbacks so the store can persist a durable queue
/// state.
class SyncEngine {
  SyncEngine(this.gateway);

  final SyncGateway gateway;
  bool _syncing = false;
  String? _lastError;

  bool get isSyncing => _syncing;

  /// Message from the most recent failed push, if any.
  String? get lastError => _lastError;

  Future<void> process({
    required List<Harvest> pendingHarvests,
    required List<Batch> pendingBatches,
    required void Function(Harvest harvest) onHarvestSynced,
    required void Function(Harvest harvest) onHarvestFailed,
    required void Function(Batch batch) onBatchSynced,
    required void Function(Batch batch) onBatchFailed,
    int maxAttempts = 3,
  }) async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    try {
      for (final harvest in pendingHarvests) {
        if (await _push(next: () => gateway.pushHarvest(harvest), maxAttempts: maxAttempts)) {
          onHarvestSynced(harvest);
        } else {
          onHarvestFailed(harvest);
        }
      }
      for (final batch in pendingBatches) {
        if (await _push(next: () => gateway.pushBatch(batch), maxAttempts: maxAttempts)) {
          onBatchSynced(batch);
        } else {
          onBatchFailed(batch);
        }
      }
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _push({
    required Future<SyncResult> Function() next,
    required int maxAttempts,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final result = await next();
        if (result.success) return true;
        _lastError = 'sync.rejected';
      } catch (e) {
        _lastError = '$e';
      }
    }
    return false;
  }
}