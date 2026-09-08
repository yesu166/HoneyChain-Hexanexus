import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/domain.dart';
import 'sync_service.dart';

/// Pushes locally created records to Supabase idempotently.
///
/// Every syncable row carries the app's stable local id as `client_id`
/// (unique partial index in the schema) and is inserted with
/// `onConflict: client_id, ignoreDuplicates` — retries can never create
/// duplicates. Reference entities (organization → beekeeper → hive) are
/// materialized first through the same key so the whole record graph lands in
/// dependency order and every foreign key resolves.
///
/// Writes go through RLS as the signed-in user; without a session (or when the
/// user lacks the corresponding roles) the gateway throws and the store keeps
/// the record in its durable pending queue for the next retry.
class SupabaseSyncGateway implements SyncGateway {
  SupabaseSyncGateway(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------
  // Harvests
  // ---------------------------------------------------------------------

  @override
  Future<SyncResult> pushHarvest(Harvest harvest) async {
    _requireSignedIn();
    try {
      final uid = _client.auth.currentUser!.id;
      final beekeeperId = await _ensureClientRow(
        'beekeepers',
        {
          'client_id': harvest.beekeeperId,
          'name': harvest.beekeeperId,
          'profile_id': uid,
          'is_independent': true,
        },
      );
      final hiveId = await _ensureClientRow(
        'hives',
        {
          'client_id': harvest.hiveId,
          'hive_code': harvest.hiveId,
          'beekeeper_id': beekeeperId,
          'status': 'active',
        },
      );
      await _client.from('harvest_events').upsert({
        'client_id': harvest.id,
        'hive_id': hiveId,
        'beekeeper_id': beekeeperId,
        'harvested_at': harvest.harvestedAt.toUtc().toIso8601String(),
        'quantity_kg': harvest.quantityKg,
        'honey_type': harvest.honeyType,
      }, onConflict: 'client_id', ignoreDuplicates: true).select('id');
      return SyncResult.success(harvest.id);
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('pushHarvest failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Batches
  // ---------------------------------------------------------------------

  @override
  Future<SyncResult> pushBatch(Batch batch) async {
    _requireSignedIn();
    try {
      final orgId = await _ensureClientRow(
        'organizations',
        {
          'client_id': batch.organizationId,
          'name': batch.organizationId,
          'type': 'PROCESSOR',
        },
      );
      await _client.from('batches').upsert({
        'client_id': batch.id,
        'batch_code': batch.code,
        'status': _mapBatchStatus(batch.status),
        'honey_type': batch.honeyType,
        'quantity_kg': batch.quantityKg,
        'organization_id': orgId,
        'trust_tier': 'self_declared',
      }, onConflict: 'client_id', ignoreDuplicates: true).select('id');
      return SyncResult.success(batch.id);
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('pushBatch failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  void _requireSignedIn() {
    if (_client.auth.currentUser == null) {
      throw Exception('pending sync requires a signed-in HoneyChain user');
    }
  }

  /// Returns the DB id of the row for [clientId], creating it via an idempotent
  /// upsert when absent.
  Future<String> _ensureClientRow(
    String table,
    Map<String, dynamic> row,
  ) async {
    final inserted = await _client
        .from(table)
        .upsert(row, onConflict: 'client_id', ignoreDuplicates: true)
        .select('id');
    if (inserted.isNotEmpty) return inserted.first['id'] as String;
    final existing = await _client
        .from(table)
        .select('id')
        .eq('client_id', row['client_id'] as String)
        .maybeSingle();
    final id = existing?['id'] as String?;
    if (id == null) {
      throw Exception('could not resolve client row in "$table"');
    }
    return id;
  }

  /// Maps the wider local lifecycle to the DB status vocabulary.
  static String _mapBatchStatus(BatchStatus status) =>
      status == BatchStatus.created ? 'created' : 'listed';
}