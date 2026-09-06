import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';
import 'disease_screening_screen.dart';
import 'hive_details_screen.dart';

/// Reference-style single-alert experience: a big attention panel, honest
/// "What can you do?" guidance from the hive insight engine, a green
/// Check Hive action, a large listen-in-your-language button, and a truthful
/// "Call Expert" sheet. No phone number is invented — the app shows real
/// advisor channels (FPO / society) and guidance instead.
class BeeAlertDetailScreen extends StatelessWidget {
  const BeeAlertDetailScreen({super.key, required this.hive, this.alert});

  final Hive hive;
  final HiveAlert? alert;

  Future<void> _startDiseaseCheck(BuildContext context) async {
    final store = HoneyChainStore.instance;
    final source = await showDiseasePhotoSourceSheet(context);
    if (source == null) return;
    try {
      final picked = source
          ? await store.imageInput.pickFromCamera()
          : await store.imageInput.pickFromGallery();
      if (!context.mounted || picked == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DiseaseScreeningScreen(hive: hive, image: picked),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('screening.pick.failed'))),
      );
    }
  }

  void _showCallExpert(BuildContext context) {
    final store = HoneyChainStore.instance;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppTheme.orangeSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: AppTheme.orangeDark,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.tr('alert.expert.sheet.title'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        Text(
                          store.profile.organizationName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                store.tr('alert.expert.advice'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.ink,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              BeekeeperInfoCard(text: store.tr('alert.expert.no.phone')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: BeeTokens.touchPrimary,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    store.tr('common.ok'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        centerTitle: true,
        title: Text(
          store.tr('alert.detail.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final insight = store.insightFor(hive);
          final alert = this.alert;
          final note = switch (alert?.type) {
            AlertType.disease => store.tr('alert.disease.note'),
            AlertType.iot => store.tr('alert.iot.note'),
            AlertType.temperature => store.tr('alert.needs.cooling.note'),
            AlertType.humidity => store.tr('alert.needs.care.note')
                .replaceFirst('{hive}', hive.name),
            _ => insight.riskExplanation,
          };
          final title =
              store.tr('alert.may.need').replaceFirst('{hive}', hive.name);
          return ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: BeeTokens.spaceGutter,
              vertical: BeeTokens.spaceMd,
            ),
            children: [
              _AttentionPanel(
                title: title,
                subtitle: note,
                time: alert != null ? relativeTime(alert.createdAt, store) : null,
              ),
              const SizedBox(height: 22),
              Text(
                store.tr('alert.what.can.do'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 10),
              _AdviceStrip(insight: insight),
              const SizedBox(height: 12),
              _PhotoCheckRow(onTap: () => _startDiseaseCheck(context)),
              const SizedBox(height: 22),
              SizedBox(
                height: BeeTokens.touchPrimary,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HiveDetailsScreen(hive: hive),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.hive_outlined, size: 22),
                  label: Text(
                    store.tr('beekeeper.status.check'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BeekeeperListenButton(
                text: '$title. $note',
                label: store.tr('alert.listen'),
              ),
              const SizedBox(height: 12),
              BeekeeperSecondaryButton(
                icon: Icons.phone_in_talk_outlined,
                label: store.tr('alert.call.expert'),
                onPressed: () => _showCallExpert(context),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Leading red attention panel for a single hive alert.
class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.title,
    required this.subtitle,
    this.time,
  });

  final String title;
  final String subtitle;
  final String? time;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.red,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.45,
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    time!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Guidance card driven by the hive insight engine (never a diagnosis).
class _AdviceStrip extends StatelessWidget {
  const _AdviceStrip({required this.insight});

  final HiveInsight insight;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final (code, accent) = switch (insight.adviceCode) {
      'cool' => ('advice.cool', AppTheme.orange),
      'ventilation' => ('advice.ventilation', AppTheme.orange),
      _ => ('advice.inspect', AppTheme.green),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              insight.adviceCode == 'cool'
                  ? Icons.ac_unit_rounded
                  : insight.adviceCode == 'ventilation'
                      ? Icons.air_rounded
                      : Icons.visibility_outlined,
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.tr(code),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  store.tr('$code.note'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
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

/// Real action row: open the existing photo disease check for this hive.
class _PhotoCheckRow extends StatelessWidget {
  const _PhotoCheckRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.orange.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppTheme.orangeDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('hive.check.disease'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.tr('hive.check.disease.note'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}