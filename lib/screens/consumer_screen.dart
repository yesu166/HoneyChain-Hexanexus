import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/passport_verification_service.dart';
import '../services/trace_qr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/journey_timeline.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import 'honey_passport_screen.dart';
import 'scanner_screen.dart';

/// Consumer verification: ONE primary action that opens the real camera QR
/// scanner, with manual code entry kept as an explicit secondary fallback.
/// Every resolved code (jar / product / batch) opens the same single
/// [HoneyPassportScreen].
class ConsumerScreen extends StatefulWidget {
  const ConsumerScreen({super.key});

  @override
  State<ConsumerScreen> createState() => _ConsumerScreenState();
}

class _ConsumerScreenState extends State<ConsumerScreen> {
  final controller = TextEditingController();
  final store = HoneyChainStore.instance;
  String? lastVerifiedId;

  /// The backend passport result for a code that was NOT in the local
  /// registry. Honest states only — never fabricated.
  PassportVerificationResult? _onlineResult;
  bool _checkingOnline = false;

  /// Raw value of the latest typed/scanned code (for the online lookup).
  String? _lastRawScan;

  Future<void> _checkOnlinePassport(String raw) async {
    setState(() => _checkingOnline = true);
    final result = await store.verifyScannedPassport(raw);
    if (!mounted) return;
    setState(() {
      _checkingOnline = false;
      _onlineResult = result;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _verifyById() {
    final entered = controller.text.trim();
    if (entered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('consumer.enter.batch.id'))),
      );
      return;
    }
    final resolution = store.resolveScan(entered);
    if (resolution is ScanResolutionUnknown) {
      // Remember the typed code for the online passport lookup.
      _lastRawScan = entered;
    }
    _openPassport(resolution, rawScan: entered);
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(onResolved: _onScanResolved),
      ),
    );
  }

  Future<void> _onScanResolved(
    ScanResolution resolution, {
    String? raw,
  }) async {
    if (!mounted) return;
    if (raw != null && raw.trim().isNotEmpty) {
      _lastRawScan = raw.trim();
    }
    _openPassport(resolution, rawScan: _lastRawScan);
  }

  void _openPassport(ScanResolution resolution, {String? rawScan}) {
    switch (resolution) {
      case ScanResolutionJar(:final jar):
        setState(() {
          lastVerifiedId = jar.jarId;
          _onlineResult = null;
        });
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HoneyPassportScreen(jar: jar)),
        );
      case ScanResolutionProduct(:final product):
        setState(() {
          lastVerifiedId = product.productCode;
          _onlineResult = null;
        });
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HoneyPassportScreen(product: product)),
        );
      case ScanResolutionBatch(:final batch):
        setState(() {
          lastVerifiedId = batch.code;
          _onlineResult = null;
        });
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HoneyPassportScreen(batch: batch)),
        );
      case ScanResolutionUnknown(:final reason):
        // Not a local record: a consumer scanning a REAL jar/batch should
        // still verify against the backend passport registry when one is
        // compiled in, instead of dead-ending on "not in local registry".
        final raw = rawScan ?? _lastRawScan ?? '';
        if (raw.isNotEmpty) {
          _checkOnlinePassport(raw);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // Demo builds show the seeded demo genealogy; production builds show
        // an honest empty state until a jar/batch is actually scanned.
        final batch = HoneyChainStore.testMode ? store.seededDemoBatch() : null;
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('consumer.appbar'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('consumer.verify.honey')),
              const SizedBox(height: 20),
              Card(
                color: AppTheme.cardCream,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _openScanner,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(store.tr('consumer.scan.verify')),
                        ),
                      ),
                      if (batch != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          store
                              .tr('consumer.demo.batch')
                              .replaceFirst('{code}', batch.code),
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      Text(
                        store.tr('consumer.title2'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        store.tr('consumer.manual.fallback'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: store.tr('consumer.hint'),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _verifyById(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _verifyById,
                            child: Text(store.tr('consumer.verify.button')),
                          ),
                        ],
                      ),                ],
              ),
            ),
          ),
              if (_checkingOnline || _onlineResult != null) ...[
                const SizedBox(height: 14),
                _OnlinePassportResult(
                  busy: _checkingOnline,
                  result: _onlineResult,
                ),
              ],
              const SizedBox(height: 22),
              if (batch != null) ...[
                SectionHeader(title: store.tr('passport.title'), seeAllLabel: ''),
                const SizedBox(height: 12),
                _PassportSummary(
                  batch: batch,
                  justVerified: lastVerifiedId == batch.code,
                ),
                const SizedBox(height: 22),
                SectionHeader(
                  title: store.tr('batch.journey.title'),
                  seeAllLabel: '',
                ),
                const SizedBox(height: 12),
                _JourneyPanel(batch: batch),
              ] else
                const _EmptyConsumerState(),
            ],
          ),
        );
      },
    );
  }
}

/// Shown when no demo batch is seeded (production build): scan a real jar or
/// enter a code — never fabricated traceability.
class _EmptyConsumerState extends StatelessWidget {
  const _EmptyConsumerState();

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.qr_code_2, size: 40, color: Colors.black26),
            const SizedBox(height: 10),
            Text(
              store.tr('consumer.empty.title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              store.tr('consumer.empty.body'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassportSummary extends StatelessWidget {
  const _PassportSummary({required this.batch, required this.justVerified});

  final Batch batch;
  final bool justVerified;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final trust = store.trustFor(batch);
    final verified = trust.passCount > 0 && trust.failCount == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.cardCream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.honey.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Icon(
                    verified ? Icons.verified : Icons.pending_outlined,
                    size: 56,
                    color: verified ? AppTheme.green : AppTheme.orange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    verified
                        ? store.tr('passport.lab.verified')
                        : trust.tier.label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: verified ? null : AppTheme.orange,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    batch.code,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StatusPill(label: verified ? StatusPill.verified : StatusPill.pending),
            const SizedBox(height: 14),
            _row(store.tr('passport.batch.id'), batch.code),
            _row(store.tr('passport.honey.type'), batch.honeyType),
            _row(store.tr('passport.origin'), batch.origin),
            _row(
              store.tr('passport.quantity'),
              '${batch.quantityKg.toStringAsFixed(1)} kg',
            ),
            _row(
              store.tr('role.lab'),
              store.verificationsFor(batch).isEmpty
                  ? store.tr('consumer.lab.pending')
                  : store.verificationsFor(batch).first.status.name,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HoneyPassportScreen(batch: batch),
                  ),
                ),
                icon: const Icon(Icons.qr_code),
                label: Text(store.tr('consumer.view.full.passport')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: const TextStyle(color: Colors.black54)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _JourneyPanel extends StatelessWidget {
  const _JourneyPanel({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final events = store.journeyFor(batch);
    final pass = events.where((e) => e.type == BatchEventType.labPass).isNotEmpty;
    final anchored =
        events.where((e) => e.type == BatchEventType.anchored).isNotEmpty;
    final custody =
        events.where((e) => e.type == BatchEventType.collected).isNotEmpty;
    final steps = [
      TimelineStep(
        title: store.tr('passport.step.hive'),
        subtitle: store.tr('passport.step.hive.sub'),
        done: true,
      ),
      TimelineStep(
        title: store.tr('passport.step.fpo'),
        subtitle: custody
            ? store.tr('passport.step.fpo.sub')
            : store.tr('status.pending'),
        done: custody,
      ),
      TimelineStep(
        title: store.tr('role.lab'),
        subtitle: pass
            ? 'Verified — PASS'
            : store.tr('status.pending'),
        done: pass,
      ),
      TimelineStep(
        title: store.tr('passport.step.blockchain'),
        subtitle: anchored
            ? store.tr('passport.step.blockchain.anchored')
            : store.tr('passport.step.blockchain.not'),
        done: anchored,
      ),
      TimelineStep(
        title: store.tr('passport.step.consumer'),
        subtitle: store.tr('passport.step.consumer.sub'),
        done: true,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: JourneyTimeline(steps: steps),
      ),
    );
  }
}

/// Honest backend verification result for a code that is not a local record.
/// Every state maps to what the server actually said — nothing fabricated.
class _OnlinePassportResult extends StatelessWidget {
  const _OnlinePassportResult({required this.busy, required this.result});

  final bool busy;
  final PassportVerificationResult? result;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final r = result;
    if (busy || r == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Checking the backend passport registry…',
                  style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final (icon, color, title, detail) = switch (r.outcome) {
      VerifyOutcome.verified => (
        Icons.verified_rounded,
        AppTheme.green,
        'Verified against the backend registry',
        'Batch ${r.proof!.batchCode} · ${r.proof!.trustTier}',
      ),
      VerifyOutcome.notFound => (
        Icons.search_off_outlined,
        AppTheme.orangeDark,
        'No passport found for this code',
        r.message,
      ),
      VerifyOutcome.rateLimited => (
        Icons.speed_outlined,
        AppTheme.orangeDark,
        'Verification rate-limited',
        r.message,
      ),
      VerifyOutcome.unreachable => (
        Icons.cloud_off_outlined,
        AppTheme.red,
        'Backend unreachable',
        r.message,
      ),
      VerifyOutcome.error => (
        Icons.error_outline,
        AppTheme.red,
        'Verification failed',
        r.message,
      ),
      VerifyOutcome.unresolved => (
        Icons.cloud_off_outlined,
        AppTheme.inkSoft,
        'Online verification not available in this build',
        'This app was built without API_BASE_URL, so only local records '
            'can be checked. Nothing has been fabricated.',
      ),
    };
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (r.verified) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.proof!.anchor.txHash.isEmpty
                          ? 'Registry status: ${r.proof!.anchor.chainStatus}'
                          : 'Anchor tx: ${r.proof!.anchor.txHash}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // Tamper-evidence only — never a purity/health claim.
                      store.tr('passport.anchor.infrastructure'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}