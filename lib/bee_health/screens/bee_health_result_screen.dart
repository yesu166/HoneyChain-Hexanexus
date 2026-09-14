import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/bee_health/services/bee_health_knowledge.dart';
import 'package:honeychain/theme/app_theme.dart';
import 'package:honeychain/widgets/listen_button.dart';

class BeeHealthResultScreen extends StatelessWidget {
  const BeeHealthResultScreen({
    super.key,
    required this.hive,
    required this.prediction,
    required this.answers,
    required this.questionsAsked,
  });
  final Hive hive;
  final BeeHealthPrediction prediction;
  final Map<String, BeeHealthValue> answers;
  final int questionsAsked;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final knowledge = BeeHealthKnowledge.instance;
    final condition = prediction.condition;
    final guidance = knowledge.guidance(condition.id);
    final observedSigns = answers.entries
        .where((e) => e.value == BeeHealthValue.yes)
        .map((e) => e.key)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(hive.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: condition.color.withValues(alpha: 0.1),
                borderRadius: AppTheme.radiusCard,
                border: Border.all(
                  color: condition.color.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.health_and_safety_rounded,
                    color: condition.color,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.tr('bh.result.title'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: AppTheme.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          store.tr('bh.result.${condition.id.toLowerCase()}'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: condition.color,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardWarm,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                store.tr('bh.result.confirmation'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
            if (observedSigns.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                store.tr('bh.result.signs'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sign in observedSigns)
                    Chip(
                      label: Text(
                        store.tr('bh.q.$sign'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: AppTheme.orangeSoft,
                      side: BorderSide.none,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              store.tr('bh.result.guidance'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            for (final point in guidance.management)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.inkSoft,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (guidance.warning.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.redSoft,
                  borderRadius: AppTheme.radiusCard,
                  border: Border.all(
                    color: AppTheme.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  guidance.warning,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (guidance.confirmationRequired.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                guidance.confirmationRequired,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.inkFaint,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ListenButton(
              text: [
                store.tr('bh.result.title'),
                store.tr('bh.result.${condition.id.toLowerCase()}'),
                store.tr('bh.result.confirmation'),
                store.tr('bh.result.guidance'),
                ...guidance.management,
                if (guidance.warning.isNotEmpty) guidance.warning,
              ].join('. '),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  store.recordBeeHealth(
                    hiveId: hive.id,
                    conditionId: condition.id,
                    answers: answers.map((k, v) => MapEntry(k, v.code)),
                    questionsAsked: questionsAsked,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(store.tr('bh.result.treatment.recorded')),
                    ),
                  );
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.orange,
                  minimumSize: const Size.fromHeight(58),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  store.tr('bh.result.record'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  store.tr('bh.result.back'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
