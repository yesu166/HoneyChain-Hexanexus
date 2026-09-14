import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/honey_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'honey_passport_screen.dart';
import 'regulator_screen.dart';

/// Blockchain Registry / evidence screen.
///
/// Honesty rules: this screen NEVER fabricates a hash. It displays the real
/// Merkle root + Fabric transaction hash returned by the backend when a bundle
/// has actually been anchored, and otherwise says so explicitly ("Not anchored
/// yet" / "local demo mode"). It also never auto-anchors evidence when opened.
class BlockchainScreen extends StatefulWidget {
  const BlockchainScreen({super.key});

  @override
  State<BlockchainScreen> createState() => _BlockchainScreenState();
}

class _BlockchainScreenState extends State<BlockchainScreen> {
  final store = HoneyChainStore.instance;
  Batch? _batch;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        _batch = store.activeV2Batch ?? (store.batches.isNotEmpty ? store.batches.first : null);
        final batch = _batch;
        if (batch == null) {
          return Scaffold(
            appBar: AppBar(title: Text(store.tr('blockchain.evidence.title'))),
            body: Center(child: Text(store.tr('blockchain.no.batch'))),
          );
        }
        final anchors = store.anchorsFor(batch);
        final bundle = store.lastAnchoredBundle;

        return Scaffold(
          appBar: AppBar(title: Text(store.tr('blockchain.evidence.title'))),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _modeBanner(store, bundle: bundle),
              const SizedBox(height: 16),
              if (store.backendModeActive) ...[
                _LiveFabricCard(store: store),
                const SizedBox(height: 16),
              ],
              Text(
                store.tr('blockchain.integrity.title'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                store.tr('blockchain.integrity.desc'),
                style: TextStyle(color: AppTheme.inkSoft, height: 1.5),
              ),
              const SizedBox(height: 20),

              if (bundle != null)
                _RealAnchorCard(bundle: bundle)
              else if (anchors.isNotEmpty)
                _DemoCommitmentCard(batch: batch, anchors: anchors)
              else
                _PendingCard(batch: batch),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HoneyPassportScreen(batch: batch),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(store.tr('blockchain.consumer.passport')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegulatorScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.gavel_outlined),
                      label: Text(store.tr('blockchain.regulator.audit')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Honest state banner — real anchor, not-yet-anchored, or on-device demo.
  Widget _modeBanner(HoneyChainStore store, {ServerEvidenceBundle? bundle}) {
    final (IconData icon, Color iconColor, Color bg, Color border, String title) =
        bundle != null
            ? (
                Icons.check_circle_rounded,
                AppTheme.green,
                AppTheme.greenSoft,
                AppTheme.green,
                store.tr('blockchain.anchor.real'),
              )
            : store.backendModeActive
                ? (
                    Icons.hourglass_top_rounded,
                    AppTheme.honey,
                    const Color(0xFFFFF6E3),
                    AppTheme.honey,
                    store.tr('blockchain.pending'),
                  )
                : (
                    Icons.devices_rounded,
                    AppTheme.inkSoft,
                    AppTheme.cardWarm,
                    AppTheme.border,
                    store.tr('blockchain.demo'),
                  );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bundle != null
                  ? store.tr('blockchain.anchor.real.desc')
                  : store.backendModeActive
                      ? store.tr('blockchain.pending.desc')
                      : store.tr('blockchain.demo.desc'),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live Fabric connection + real committed anchor values when available.
class _LiveFabricCard extends StatelessWidget {
  const _LiveFabricCard({required this.store});

  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final health = store.blockchainHealth;
    final status = store.blockchainStatus;
    final bundle = store.lastAnchoredBundle;
    final connected = health?.isConnected ?? false;
    return Card(
      color: connected ? AppTheme.greenSoft : AppTheme.cardWarm,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: connected ? AppTheme.green : AppTheme.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.link : Icons.cloud_off_outlined,
                  color: connected ? AppTheme.greenDark : AppTheme.orangeDark,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    connected
                        ? 'Live Fabric network (via backend)'
                        : 'Fabric chain: ${health?.status ?? 'checking'}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: store.serverCollectionsBusy
                      ? null
                      : () => store.refreshServerCollections(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh blockchain status',
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (connected && health != null) ...[
              _fabricRow('Channel · chaincode',
                  '${health.channel} · ${health.chaincode}'),
              _fabricRow(
                'Version · sequence',
                'v${health.chaincodeVersion ?? '?'} · '
                    'seq ${health.chaincodeSequence ?? '?'}',
              ),
              _fabricRow('Peer · MSP',
                  '${health.peer.isNotEmpty ? health.peer : '—'} · '
                      '${health.mspId.isNotEmpty ? health.mspId : '—'}'),
              if (status != null)
                _fabricRow(
                    'Tracked transactions', '${status.transactionCount}'),
            ],
            if (bundle != null) ...[
              const Divider(height: 22),
              _fabricRow(store.tr('blockchain.bundle.id'), bundle.bundleId),
              _fabricRow(store.tr('blockchain.entity'), bundle.entityRef),
              _fabricRow(store.tr('blockchain.leaf.count'),
                  '${bundle.leafCount}'),
              _fabricRow(
                  store.tr('blockchain.network'), bundle.network),
              _fabricRow(
                  store.tr('blockchain.anchor.state'),
                  '${bundle.anchor['state'] ?? 'unknown'}'),
              const SizedBox(height: 8),
              _hashField(
                store.tr('blockchain.merkle.root'),
                bundle.rootHash.isEmpty ? '—' : bundle.rootHash,
              ),
              if (bundle.txHash.isNotEmpty) ...[
                const SizedBox(height: 8),
                _hashField(
                  store.tr('blockchain.tx.hash'),
                  bundle.txHash,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final result = await store.verifyLastBundle();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(
                          result == null
                              ? 'Verification failed'
                              : 'Bundle ${result.anchored ? 'ANCHORED' : 'NOT ANCHORED'} · '
                                  'evidence ${result.evidenceIntact ? 'intact' : 'tampered'}',
                        ),
                      ));
                  },
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: Text(store.tr('blockchain.verify.on.chain')),
                ),
              ),
            ],
            if (health != null && !connected && health.error != null) ...[
              const SizedBox(height: 6),
              Text(
                health.error!,
                style: TextStyle(fontSize: 12, color: AppTheme.orangeDark),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fabricRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style:
                      const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: AppTheme.ink,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _hashField(String label, String hash) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              hash,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      );
}

/// Real anchored bundle returned by the backend (never a mock value).
class _RealAnchorCard extends StatelessWidget {
  final ServerEvidenceBundle bundle;

  const _RealAnchorCard({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final anchored = bundle.isAnchored;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: anchored ? AppTheme.green : AppTheme.honey,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  anchored ? Icons.verified_rounded : Icons.flag_rounded,
                  color: anchored ? AppTheme.greenDark : AppTheme.honey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.tr('blockchain.anchored.record'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                StatusBadge(
                  label: anchored
                      ? store.tr('status.anchored')
                      : bundle.anchor['state'] ?? 'pending',
                  color: anchored ? AppTheme.green : AppTheme.honey,
                ),
              ],
            ),
            const Divider(height: 26),
            _row(store.tr('blockchain.bundle.id'), bundle.bundleId),
            _row(store.tr('blockchain.entity'), bundle.entityRef),
            _row(store.tr('blockchain.network'), bundle.network),
            _row(store.tr('blockchain.leaf.count'), '${bundle.leafCount}'),
            const SizedBox(height: 12),
            _hashBlock(
              store.tr('blockchain.merkle.root'),
              bundle.rootHash.isEmpty ? '—' : bundle.rootHash,
            ),
            if (bundle.txHash.isNotEmpty) ...[
              const SizedBox(height: 10),
              _hashBlock(store.tr('blockchain.tx.hash'), bundle.txHash),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hashBlock(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardWarm,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      );

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child:
                Text(label, style: const TextStyle(color: AppTheme.inkSoft)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline demo integrity commitment — clearly NOT a blockchain transaction.
class _DemoCommitmentCard extends StatelessWidget {
  final Batch batch;
  final List<BlockchainAnchor> anchors;

  const _DemoCommitmentCard({required this.batch, required this.anchors});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final anchor = anchors.isNotEmpty ? anchors.first : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_other_rounded,
                    color: AppTheme.honey),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.tr('blockchain.demo.commitment'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                StatusBadge(
                    label: store.tr('blockchain.demo.tag'),
                    color: AppTheme.honey),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              store.tr('blockchain.demo.commitment.desc'),
              style: TextStyle(
                  color: AppTheme.inkSoft,
                  height: 1.5,
                  fontSize: 13.5),
            ),
            if (anchor != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    store.tr('blockchain.demo.reference'),
                    style:
                        const TextStyle(color: AppTheme.inkSoft, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    anchor.anchorId.isEmpty ? '—' : anchor.anchorId,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Batch batch;

  const _PendingCard({required this.batch});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_empty, color: AppTheme.honey),
                const SizedBox(width: 10),
                Text(
                  store.tr('blockchain.awaiting'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              batch.status == BatchStatus.labVerified
                  ? store
                      .tr('blockchain.will.anchor')
                      .replaceFirst('{batch}', batch.code)
                  : store
                      .tr('blockchain.needs.lab')
                      .replaceFirst('{batch}', batch.code),
              style: TextStyle(color: AppTheme.inkSoft, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}