import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/bee_health/services/bee_health_question_engine.dart';
import 'package:honeychain/theme/app_theme.dart';

import '../widgets/symptom_illustration.dart';
import '../widgets/disease_reference_gallery.dart';

import 'bee_health_result_screen.dart';

class BeeHealthQuestionScreen extends StatefulWidget {
  const BeeHealthQuestionScreen({super.key, required this.hive});
  final Hive hive;
  @override
  State<BeeHealthQuestionScreen> createState() =>
      _BeeHealthQuestionScreenState();
}

class _BeeHealthQuestionScreenState extends State<BeeHealthQuestionScreen> {
  late final BeeHealthQuestionEngine _engine;
  late BeeHealthProgress _progress;

  @override
  void initState() {
    super.initState();
    _engine = BeeHealthQuestionEngine();
    _progress = _engine.start();
  }

  void _handleOption(String featureId, BeeHealthValue value) {
    setState(() {
      _progress = _engine.recordAnswer(featureId, value);
    });
    if (_progress.isDone && _progress.prediction != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BeeHealthResultScreen(
            hive: widget.hive,
            prediction: _progress.prediction!,
            answers: _engine.answers,
            questionsAsked: _engine.askedCount,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final q = _progress.question;
    if (q == null || _progress.isDone) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('bh.title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.orangeSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.hive.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.orangeDark,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.greenSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_engine.askedCount}/8',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const DiseaseReferenceGallery(),
              if (q.kind == QuestionKind.feature) ...[
                const SizedBox(height: 14),
                SymptomIllustration(featureId: q.featureId),
                const SizedBox(height: 18),
              ] else ...[
                const SizedBox(height: 18),
              ],
              Text(
                store.tr(q.promptKey),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                store.tr('bh.honesty'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              q.kind == QuestionKind.starter
                  ? _StarterOptions(
                      onSelect: (fid) {
                        if (fid == '__weak' || fid == '__not_sure') {
                          _handleOption(fid, BeeHealthValue.notSure);
                        } else {
                          _handleOption(fid, BeeHealthValue.yes);
                        }
                      },
                    )
                  : _FeatureOptions(
                      question: q,
                      onValue: (v) => _handleOption(q.featureId, v),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarterOptions extends StatelessWidget {
  const _StarterOptions({required this.onSelect});
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final options = <_Option>[
      _Option(
        store.tr('bh.option.crawling'),
        Icons.bug_report_rounded,
        'adult_crawling_unable_to_fly',
      ),
      _Option(store.tr('bh.option.wings'), Icons.waves_rounded, 'adult_k_wing'),
      _Option(
        store.tr('bh.option.brood'),
        Icons.egg_rounded,
        'brood_larvae_yellow_curled',
      ),
      _Option(
        store.tr('bh.option.droppings'),
        Icons.water_drop_rounded,
        'adult_yellow_fecal_spots',
      ),
      _Option(
        store.tr('bh.option.weak'),
        Icons.sentiment_dissatisfied_rounded,
        '__weak',
      ),
      _Option(
        store.tr('bh.option.notsure'),
        Icons.help_outline_rounded,
        '__not_sure',
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Material(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(options[i].featureId),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Icon(options[i].icon, color: AppTheme.orangeDark, size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        options[i].label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.inkFaint,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Option {
  const _Option(this.label, this.icon, this.featureId);
  final String label;
  final IconData icon;
  final String featureId;
}

class _FeatureOptions extends StatelessWidget {
  const _FeatureOptions({required this.question, required this.onValue});
  final BeeHealthQuestion question;
  final ValueChanged<BeeHealthValue> onValue;
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final labels = [
      (store.tr('bh.opt.yes'), BeeHealthValue.yes, AppTheme.green),
      (store.tr('bh.opt.no'), BeeHealthValue.no, AppTheme.grey),
      (store.tr('bh.opt.notsure'), BeeHealthValue.notSure, AppTheme.inkFaint),
    ];
    return Column(
      children: [
        for (final (label, value, color) in labels)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onValue(value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color, width: 1.6),
                    ),
                    constraints: const BoxConstraints(minHeight: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          switch (value) {
                            BeeHealthValue.yes =>
                              Icons.check_circle_outline_rounded,
                            BeeHealthValue.no =>
                              Icons.cancel_outlined,
                            BeeHealthValue.notSure =>
                              Icons.help_outline_rounded,
                          },
                          color: color,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: color,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
