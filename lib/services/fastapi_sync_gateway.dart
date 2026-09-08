import '../core/api/api_client.dart';
import '../models/domain.dart';
import 'sync_service.dart';

/// Pushes locally created records to the FastAPI backend through
/// `POST /api/v1/sync/push`, which is idempotent by `client_id`.
///
/// The offline queue (SyncEngine) already guarantees retries; this gateway
/// keeps the queue sane by:
///  - never retrying a record the server already accepted (backend_id replay);
///  - failing fast as [ApiExceptionKind.network]/[timeout] so the queue keeps
///    the record for the next sync pass.
class FastApiSyncGateway implements SyncGateway {
  FastApiSyncGateway(this._client);

  final ApiClient _client;

  /// Accepted client ids remembered this session to avoid re-POSTing rows the
  /// server already has when a previous ack was lost mid-read.
  final Set<String> _knownAccepted = {};

  @override
  Future<SyncResult> pushHarvest(Harvest harvest) async {
    if (_knownAccepted.contains(harvest.id)) {
      return const SyncResult.success('');
    }
    final ack = await _pushItem({
      'entity': 'harvest',
      'client_id': harvest.id,
      'data': {
        'hive_id': harvest.hiveId,
        'quantity_kg': harvest.quantityKg,
        'honey_type': harvest.honeyType,
        'harvested_at': harvest.harvestedAt.toUtc().toIso8601String(),
      },
    });
    if (ack.accepted) _knownAccepted.add(harvest.id);
    return ack.accepted
        ? SyncResult.success(ack.backendId)
        : const SyncResult.failure();
  }

  @override
  Future<SyncResult> pushBatch(Batch batch) async {
    if (_knownAccepted.contains(batch.id)) {
      return const SyncResult.success('');
    }
    final ack = await _pushItem({
      'entity': 'batch',
      'client_id': batch.id,
      'data': {
        'batch_code': batch.code,
        'organization_id': batch.organizationId,
        'honey_type': batch.honeyType,
        'origin': batch.origin,
        'quantity_kg': batch.quantityKg,
      },
    });
    if (ack.accepted) _knownAccepted.add(batch.id);
    return ack.accepted
        ? SyncResult.success(ack.backendId)
        : const SyncResult.failure();
  }

  Future<_PushAck> _pushItem(Map<String, dynamic> item) async {
    final response = await _client.postJson('/api/v1/sync/push', body: {
      'items': [item],
    });
    for (final key in ['accepted', 'rejected']) {
      final list = response[key];
      if (list is! List || list.isEmpty) continue;
      final entry = list.first;
      if (entry is Map) {
        return _PushAck(
          accepted: entry['accepted'] == true,
          backendId: _asString(entry['backend_id']),
        );
      }
    }
    return const _PushAck(accepted: false);
  }

  static String _asString(Object? value) => value == null ? '' : '$value';
}

class _PushAck {
  const _PushAck({required this.accepted, this.backendId = ''});

  final bool accepted;
  final String backendId;
}