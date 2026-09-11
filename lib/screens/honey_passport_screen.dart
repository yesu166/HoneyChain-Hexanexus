import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/passport_verification_service.dart';
import '../services/trace_qr_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/section_label.dart';

/// The single, canonical Honey Passport.
///
/// Renders a batch (optionally within a jar / product) as a **trust tier**
/// derived from the actual records (see [TrustService]), an honest evidence /
/// caveat panel, the recorded journey and a real QR that a consumer can
/// scan. No decorative "verified" certificates and no placeholder QR is ever
/// shown here.
class HoneyPassportScreen extends StatelessWidget {
  const HoneyPassportScreen({super.key, this.batch, this.jar, this.product})
      : assert(
          batch != null || jar != null || product != null,
          'A batch, jar or product is required',
        );

  final Batch? batch;
  final HoneyJar? jar;
  final ProductBatch? product;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final jar = this.jar;
    final product = this.product;
    final batch = jar != null
        ? store.batchById(jar.sourceBatchId)
        : product != null
            ? store.batchById(product.parentBatchId)
            : this.batch;

    if (batch == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
          foregroundColor: AppTheme.ink,
          elevation: 0,
          title: Text(
            store.tr('passport.title'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ),
        body: Center(
          child: Text(
            jar?.jarId ?? '',
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('passport.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final trust = store.trustFor(batch);
          final verified = trust.passCount > 0 && trust.failCount == 0;
          final qrPayload = jar != null
              ? TraceQrService.buildForJar(jar.jarId)
              : product != null
                  ? TraceQrService.buildForProduct(product.productCode)
                  : TraceQrService.buildForProduct(batch.code);
          final events = store.journeyFor(batch);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _TrustCertCard(batch: batch, trust: trust, verified: verified),
              const SizedBox(height: 22),
              _OnlineVerificationPanel(subjectCode: batch.code),
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.quality')),
              _QualityPanel(trust: trust),
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.origin')),
              _IdentityCard(
                store: store,
                batch: batch,
                jar: jar,
                product: product,
              ),
              if (jar != null) ...[
                const SizedBox(height: 14),
                _JarCard(store: store, jar: jar, batchCode: batch.code),
              ],
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.timeline')),
              _EventTimeline(events: events, store: store),
              const SizedBox(height: 26),
              _PassportQr(payload: qrPayload),
              const SizedBox(height: 28),
            ],
          );
        },
      ),
    );
  }
}

class _TrustCertCard extends StatelessWidget {
  const _TrustCertCard({
    required this.batch,
    required this.trust,
    required this.verified,
  });

  final Batch batch;
  final TrustState trust;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final tier = trust.tier;
    final accent = verified
        ? AppTheme.green
        : tier == TrustTier.organizationVerified
            ? AppTheme.orange
            : AppTheme.grey;

    final title = verified
        ? store.tr('passport.lab.verified')
        : tier.label;
    final caption = verified
        ? '${store.tr('batch.label')} ${batch.code}'
        : '${tier.who} evidence is on record for ${batch.code} - '
            '${trust.claims.isEmpty ? 'no independent proof yet' : 'proof is partial'}.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              verified
                  ? Icons.verified_rounded
                  : Icons.shield_outlined,
              color: accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.inkSoft,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            batch.code,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.trust});

  final TrustState trust;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final claims = trust.claims.isEmpty
        ? <String>['Beekeeper-reported harvest records only.']
        : trust.claims;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final claim in claims)
          _EvidenceRow(icon: Icons.check_circle_rounded, text: claim, ok: true),
        for (final caveat in trust.caveats)
          _EvidenceRow(icon: Icons.info_outline_rounded, text: caveat, ok: false),
        if (trust.isPrototypeAnchor)
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.hub_outlined, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.tr('passport.anchor.infrastructure'),
                    style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.icon, required this.text, required this.ok});

  final IconData icon;
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: ok ? AppTheme.green : AppTheme.orangeDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: ok ? FontWeight.w700 : FontWeight.w400,
                color: ok ? AppTheme.ink : AppTheme.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.store,
    required this.batch,
    required this.jar,
    required this.product,
  });

  final HoneyChainStore store;
  final Batch batch;
  final HoneyJar? jar;
  final ProductBatch? product;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          if (product != null)
            _InfoRow(
              label: store.tr('qr.info.batch'),
              value: '${product!.productCode} · ${product!.size.label}',
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('passport.batch.id'), value: batch.code),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('passport.honey.type'), value: batch.honeyType),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('passport.farmer'), value: jar?.beekeeperName ?? store.profile.name),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('passport.location'), value: batch.origin),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('passport.source'),
            value: jar != null
                ? store.sourceHivesForBatch(batch).join(', ')
                : store.batchSourceHive(batch),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('passport.quantity'),
            value: '${formatKg(batch.quantityKg)} kg',
          ),
        ],
      ),
    );
  }
}

class _JarCard extends StatelessWidget {
  const _JarCard({
    required this.store,
    required this.jar,
    required this.batchCode,
  });

  final HoneyChainStore store;
  final HoneyJar jar;
  final String batchCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _InfoRow(label: store.tr('passport.jar.id'), value: jar.jarId),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('passport.jar.size'), value: jar.packageSize),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('passport.jar.batch'),
            value: batchCode,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('passport.jar.anchor'),
            value: jar.blockchainAnchorId?.isNotEmpty == true
                ? (jar.blockchainAnchorId ?? '—')
                : store.tr('passport.jar.not.anchored'),
          ),
        ],
      ),
    );
  }
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({required this.events, required this.store});

  final List<BatchEvent> events;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: AppTheme.radiusCard,
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          store.tr('passport.pending.note'),
          style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            _EventRow(event: events[i]),
            if (i < events.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 34),
                child: Divider(height: 1, indent: 16, endIndent: 16),
              ),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final BatchEvent event;

  @override
  Widget build(BuildContext context) {
    final icon = switch (event.type) {
      BatchEventType.registered => Icons.archive_rounded,
      BatchEventType.collected => Icons.local_shipping_rounded,
      BatchEventType.labPass => Icons.science_rounded,
      BatchEventType.labFail => Icons.warning_amber_rounded,
      BatchEventType.processing => Icons.precision_manufacturing_rounded,
      BatchEventType.anchored => Icons.link_rounded,
      BatchEventType.corrected => Icons.edit_note_rounded,
      BatchEventType.splitFrom => Icons.call_split_rounded,
      BatchEventType.aggregatedFrom => Icons.call_merge_rounded,
      BatchEventType.packaged => Icons.inventory_2_outlined,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.orangeDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDate(event.at)} · ${event.actor}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PassportQr extends StatelessWidget {
  const _PassportQr({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 168,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF2E2417),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF2E2417),
              ),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
],
      );
  }
}

/// Online verification against the FastAPI passport endpoint.
///
/// Only ever shows a green "verified" state when the server actually returned
/// a passport for this code with a real anchor. When no backend is compiled
/// in the panel says so instead of inventing a result.
class _OnlineVerificationPanel extends StatefulWidget {
  const _OnlineVerificationPanel({required this.subjectCode});

  final String subjectCode;

  @override
  State<_OnlineVerificationPanel> createState() => _OnlineVerificationPanelState();
}

class _OnlineVerificationPanelState extends State<_OnlineVerificationPanel> {
  PassportVerificationResult? _result;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final result =
        await HoneyChainStore.instance.verifyPassport(widget.subjectCode);
    if (!mounted) return;
    setState(() => _result = result);
  }

  Future<void> _retry() async {
    setState(() => _result = null);
    await _verify();
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final result = _result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: _buildContent(store, result),
    );
  }

  Widget _buildContent(HoneyChainStore store, PassportVerificationResult? result) {
    if (result == null) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verifying against the registry…',
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
          ),
        ],
      );
    }

    switch (result.outcome) {
      case VerifyOutcome.unresolved:
        return _MessagePanel(
          icon: Icons.cloud_off_outlined,
          color: AppTheme.inkSoft,
          title: 'Online verification not available in this build',
          detail:
              'This APK was built without API_BASE_URL, so the app cannot ask '
              'the backend registry. Everything above is validated against the '
              'local records only — nothing has been fabricated.',
        );
      case VerifyOutcome.verified:
        final proof = result.proof!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: AppTheme.green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Backend registry: ${proof.trustTier}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.greenDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AnchorBlock(proof: proof),
            const SizedBox(height: 10),
            const Text(
              'Tamper-evidence from the blockchain anchor, not a purity or '
              'health certificate.',
              style: TextStyle(fontSize: 11, color: AppTheme.inkFaint),
            ),
          ],
        );
      case VerifyOutcome.notFound:
        return _MessagePanel(
          icon: Icons.search_off_outlined,
          color: AppTheme.orangeDark,
          title: 'No passport on the backend for this code',
          detail: result.message,
        );
      case VerifyOutcome.rateLimited:
        return _MessagePanel(
          icon: Icons.speed_outlined,
          color: AppTheme.orangeDark,
          title: 'Verification rate-limited',
          detail: result.message,
        );
      case VerifyOutcome.unreachable:
        return _MessagePanel(
          icon: Icons.cloud_off_outlined,
          color: AppTheme.red,
          title: 'Backend verification unavailable',
          detail: result.message,
          actionLabel: 'Retry',
          onAction: _retry,
        );
      case VerifyOutcome.error:
        return _MessagePanel(
          icon: Icons.error_outline,
          color: AppTheme.red,
          title: 'Verification failed',
          detail: result.message,
          actionLabel: 'Retry',
          onAction: _retry,
        );
    }
  }
}

class _AnchorBlock extends StatelessWidget {
  const _AnchorBlock({required this.proof});

  final PassportProof proof;

  @override
  Widget build(BuildContext context) {
    final anchor = proof.anchor;
    return switch (anchor.status) {
      PassportAnchorStatus.anchored => _AnchorRow(
          color: AppTheme.green,
          icon: Icons.link_rounded,
          label: 'Blockchain anchored',
          value: 'tx ${_short(anchor.txHash)}',
        ),
      PassportAnchorStatus.pending => _AnchorRow(
          color: AppTheme.orangeDark,
          icon: Icons.hourglass_top_rounded,
          label: 'Anchor pending',
          value: 'The batch is queued for anchoring.',
        ),
      PassportAnchorStatus.none => _AnchorRow(
          color: AppTheme.inkSoft,
          icon: Icons.hub_outlined,
          label: 'Not anchored',
          value: 'No blockchain anchor is on record for this batch yet.',
        ),
    };
  }

  static String _short(String tx) =>
      tx.length > 14 ? '${tx.substring(0, 6)}…${tx.substring(tx.length - 6)}' : tx;
}

class _AnchorRow extends StatelessWidget {
  const _AnchorRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.35),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.inkFaint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}