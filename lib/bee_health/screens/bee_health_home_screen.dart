import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/bee_health/screens/bee_health_question_screen.dart';
import 'package:honeychain/models/domain.dart';

import 'package:honeychain/theme/app_theme.dart';
import 'package:honeychain/widgets/beekeeper_widgets.dart';

class BeeHealthHomeScreen extends StatefulWidget {
  const BeeHealthHomeScreen({super.key});
  @override
  State<BeeHealthHomeScreen> createState() => _BeeHealthHomeScreenState();
}

class _BeeHealthHomeScreenState extends State<BeeHealthHomeScreen> {
  String? _selectedHiveId;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final events = _selectedHiveId != null
        ? store.beeHealthEventsFor(_selectedHiveId!)
        : <BeeHealthEvent>[];
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('bh.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardWarm,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                store.tr('bh.honesty'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              store.tr('bh.pick.hive'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            for (final h in store.hives) ...[
              _HiveSelectorTile(
                hive: h,
                inspected: store.beeHealthEventsFor(h.id).isNotEmpty,
                selected: h.id == _selectedHiveId,
                onTap: () => setState(() => _selectedHiveId = h.id),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            if (_selectedHiveId == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    store.tr('bh.pick.hive.hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkFaint,
                      height: 1.4,
                    ),
                  ),
                ),
              )
            else ...[
              Text(
                store.tr('bh.history'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: AppTheme.radiusCard,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      store.tr('bh.no.history'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ),
                )
              else
                for (final e in events.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EventTile(event: e),
                  ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final h = store.hiveById(_selectedHiveId!);
                    if (h == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BeeHealthQuestionScreen(hive: h),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.orange,
                    minimumSize: const Size.fromHeight(68),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: Text(
                    store.tr('bh.start.check'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Large vertical hive option: colour coded for health, icon + name + real
/// hive code + status on the right. Fully tappable.
class _HiveSelectorTile extends StatelessWidget {
  const _HiveSelectorTile({
    required this.hive,
    required this.inspected,
    required this.selected,
    required this.onTap,
  });

  final Hive hive;
  final bool inspected;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final healthy = store.insightFor(hive).riskLevel == RiskLevel.healthy;
    final color = healthy ? AppTheme.green : AppTheme.orangeDark;

    return Material(
      color: selected ? color.withValues(alpha: 0.12) : AppTheme.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? color : AppTheme.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.hive_rounded, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hive.name.isEmpty ? hive.id : hive.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hiveCode(hive),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkFaint,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (inspected ? AppTheme.green : AppTheme.inkFaint)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: inspected ? AppTheme.green : AppTheme.inkFaint,
                    width: 1,
                  ),
                ),
                child: Text(
                  inspected
                      ? store.tr('bh.status.inspected')
                      : store.tr('bh.status.not.inspected'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: inspected ? AppTheme.green : AppTheme.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final BeeHealthEvent event;
  @override
  Widget build(BuildContext context) {
    final condition = BeeCondition.byId(event.conditionId);
    final color = condition?.color ?? AppTheme.grey;
    final conditionLabel = condition == null
        ? HoneyChainStore.instance.tr('bh.result.unknown')
        : HoneyChainStore.instance.tr('bh.result.${condition.id.toLowerCase()}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conditionLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  HoneyChainStore
                      .instance
                      .tr('bh.events.asked')
                      .replaceFirst('{n}', '${event.questionsAsked}'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _fmtDate(event.checkedAt),
            style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
