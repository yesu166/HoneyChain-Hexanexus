import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/qr_placeholder.dart';
import '../widgets/section_label.dart';

class HoneyPassportScreen extends StatelessWidget {
  const HoneyPassportScreen({super.key, this.batch, this.jar})
      : assert(batch != null || jar != null, 'A batch or jar is required');

  final Batch? batch;
  final HoneyJar? jar;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final jar = this.jar;
    final batch = jar != null ? store.batchById(jar.sourceBatchId) : this.batch;
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
    final status = batch.displayStatus ?? BatchDisplayStatus.pending;
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
          final verifications = store.verificationsFor(batch);
          final verified = status == BatchDisplayStatus.verified &&
              verifications.isNotEmpty &&
              verifications.first.status == VerificationStatus.pass;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _CertCard(
                batch: batch,
                status: status,
                verified: verified,
                testedAt: verified ? verifications.first.testedAt : null,
              ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.quality')),
              if (verified) ...[
                _CheckRow(label: store.tr('passport.check.moisture'), ok: true),
                _CheckRow(label: store.tr('passport.check.sugar'), ok: true),
                if (verifications.first.summary.contains('authenticity'))
                  _CheckRow(label: store.tr('passport.check.authenticity'), ok: true),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.greenSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '• ${verifications.first.summary}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                      height: 1.4,
                    ),
                  ),
                ),
              ] else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    store.tr(
                      status == BatchDisplayStatus.inLab
                          ? 'passport.inlab.note'
                          : 'passport.pending.note',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.origin')),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: AppTheme.radiusCard,
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      label: store.tr('passport.farmer'),
                      value: jar?.beekeeperName ?? store.profile.name,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _InfoRow(
                      label: store.tr('passport.location'),
                      value: batch.origin,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _InfoRow(
                      label: store.tr('passport.source'),
                      value: jar != null
                          ? store.sourceHivesForBatch(batch).join(', ')
                          : store.batchSourceHive(batch),
                    ),
                  ],
                ),
              ),
              if (jar != null) ...[
                const SizedBox(height: 22),
                SectionLabel(store.tr('passport.jar')),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: AppTheme.radiusCard,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                        label: store.tr('passport.jar.id'),
                        value: jar.jarId,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _InfoRow(
                        label: store.tr('passport.jar.size'),
                        value: jar.packageSize,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _InfoRow(
                        label: store.tr('passport.jar.batch'),
                        value: batch.code,
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
                ),
              ],
              const SizedBox(height: 22),
              SectionLabel(store.tr('passport.timeline')),
              _Timeline(status: status, jar: jar),
              const SizedBox(height: 26),
              Center(child: QrCodePlaceholder(seed: jar?.jarId ?? batch.code)),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  jar != null
                      ? 'honeychain://jar/${jar.jarId}'
                      : store.tr('passport.scan'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          );
        },
      ),
    );
  }
}

class _CertCard extends StatelessWidget {
  const _CertCard({
    required this.batch,
    required this.status,
    required this.verified,
    this.testedAt,
  });

  final Batch batch;
  final BatchDisplayStatus status;
  final bool verified;
  final DateTime? testedAt;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final accent = verified
        ? AppTheme.green
        : status == BatchDisplayStatus.inLab
            ? AppTheme.orange
            : AppTheme.grey;
    final title = verified
        ? store.tr('passport.lab.verified')
        : store.tr(
            status == BatchDisplayStatus.inLab
                ? 'status.in.lab'
                : 'status.pending',
          );
    final caption = verified
        ? '${store.tr('batch.label')} ${batch.code}'
        : store.tr(
            status == BatchDisplayStatus.inLab
                ? 'passport.inlab.note'
                : 'passport.pending.note',
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(
          color: accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
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
              verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
              color: accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
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
          if (testedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '· ${formatDate(testedAt!)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.inkFaint,
              ),
            ),
          ],
        ],
      ),
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
                fontSize: 14,
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.ok});

  final String label;
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
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 20,
            color: ok ? AppTheme.green : AppTheme.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
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

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status, this.jar});

  final BatchDisplayStatus status;
  final HoneyJar? jar;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final lab = status == BatchDisplayStatus.verified ||
        status == BatchDisplayStatus.inLab;
    final verified = status == BatchDisplayStatus.verified;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _Step(
            label: store.tr('passport.step.harvested'),
            state: _StepState.done,
          ),
          _StepConnector(state: lab ? _StepState.done : _StepState.pending),
          _Step(
            label: store.tr('passport.step.lab'),
            state: lab ? _StepState.done : _StepState.pending,
          ),
          _StepConnector(state: verified ? _StepState.done : _StepState.pending),
          _Step(
            label: store.tr('passport.step.verified'),
            state: verified ? _StepState.done : _StepState.pending,
          ),
          if (jar != null) ...[
            _StepConnector(state: _StepState.done),
            _Step(
              label: store.tr('passport.step.packaged'),
              state: _StepState.done,
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, pending }

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final color = done ? AppTheme.green : AppTheme.grey;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.remove_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: done ? AppTheme.ink : AppTheme.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final color = state == _StepState.done ? AppTheme.green : AppTheme.border;
    return Container(
      width: 22,
      height: 2,
      margin: const EdgeInsets.only(bottom: 22),
      color: color,
    );
  }
}