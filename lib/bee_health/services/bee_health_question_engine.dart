import '../models/bee_health_models.dart';
import 'bee_health_prediction_service.dart';

enum QuestionKind { starter, feature }

class BeeHealthQuestion {
  const BeeHealthQuestion({required this.kind, required this.featureId, required this.promptKey, required this.optionKeys});
  final QuestionKind kind;
  final String featureId;
  final String promptKey;
  final List<String> optionKeys;
}

class BeeHealthProgress {
  const BeeHealthProgress.ask(this.question,
      {required this.askedCount, required this.notSureCount})
      : prediction = null,
        isDone = false;
  const BeeHealthProgress.done(this.prediction,
      {required this.askedCount, required this.notSureCount})
      : question = null,
        isDone = true;
  final BeeHealthQuestion? question;
  final BeeHealthPrediction? prediction;
  final bool isDone;
  final int askedCount;
  final int notSureCount;
}

class BeeHealthQuestionEngine {
  BeeHealthQuestionEngine._({required this.predictionService});
  factory BeeHealthQuestionEngine({BeeHealthPredictionService? predictionService}) => BeeHealthQuestionEngine._(predictionService: predictionService ?? const BeeHealthPredictionService());
  final BeeHealthPredictionService predictionService;

  final _answers = <String, BeeHealthValue>{};
  int _notSureCount = 0;
  int _askedCount = 0;
  bool _started = false;

  static const _starterOptionFeatures = <String>[
    BeeHealthFeature.kCrawling,
    BeeHealthFeature.kWing,
    BeeHealthFeature.kLarvae,
    BeeHealthFeature.kFecal,
  ];

  Map<String, BeeHealthValue> get answers => Map.unmodifiable(_answers);
  int get notSureCount => _notSureCount;
  int get askedCount => _askedCount;

  BeeHealthProgress start() {
    _started = true;
    final starterOptions = [
      ..._starterOptionFeatures,
      '__weak',
      '__not_sure',
    ];
    return BeeHealthProgress.ask(
      BeeHealthQuestion(kind: QuestionKind.starter, featureId: '', promptKey: 'bh.question.title', optionKeys: starterOptions),
      askedCount: _askedCount,
      notSureCount: _notSureCount,
    );
  }

  BeeHealthProgress recordAnswer(String featureId, BeeHealthValue value) {
    if (_started && !_answers.containsKey(featureId) && featureId.isNotEmpty) {
      _answers[featureId] = value;
      _askedCount++;
      if (value == BeeHealthValue.notSure) _notSureCount++;
    }
    return decide();
  }

  /// Starter (first-screen) choices. Real features are recorded as Yes;
  /// `__weak` just continues; `__not_sure` counts as uncertainty but is
  /// deliberately kept out of the model answer map.
  BeeHealthProgress recordStarterChoice(String choice) {
    if (!_started) return decide();
    if (choice == '__weak') return decide();
    if (choice == '__not_sure') {
      _notSureCount++;
      return decide();
    }
    if (_starterOptionFeatures.contains(choice)) {
      return recordAnswer(choice, BeeHealthValue.yes);
    }
    return decide();
  }

  BeeHealthProgress decide() {
    final next = _nextQuestion();
    if (next != null) return BeeHealthProgress.ask(next, askedCount: _askedCount, notSureCount: _notSureCount);
    final prediction = predictionService.predict(answers: _answers);
    return BeeHealthProgress.done(prediction, askedCount: _askedCount, notSureCount: _notSureCount);
  }

  BeeHealthQuestion? _nextQuestion() {
    if (_answers.length >= 8) return null;

    // Rule: if larvae or spotted is Yes, ask sour (EFB drill)
    if ((_answers[BeeHealthFeature.kLarvae] == BeeHealthValue.yes || _answers[BeeHealthFeature.kSpotted] == BeeHealthValue.yes) && !_answers.containsKey(BeeHealthFeature.kSour)) {
      return _featureQ(BeeHealthFeature.kSour);
    }
    if (_answers[BeeHealthFeature.kLarvae] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kSpotted)) {
      return _featureQ(BeeHealthFeature.kSpotted);
    }

    // Acarine drill
    if (_answers[BeeHealthFeature.kCrawling] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kWing)) return _featureQ(BeeHealthFeature.kWing);
    if (_answers[BeeHealthFeature.kWing] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kCrawling)) return _featureQ(BeeHealthFeature.kCrawling);
    if (_answers[BeeHealthFeature.kWing] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kScattered)) return _featureQ(BeeHealthFeature.kScattered);

    // Nosema drill
    if (_answers[BeeHealthFeature.kFecal] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kSwollen)) return _featureQ(BeeHealthFeature.kSwollen);
    if (_answers[BeeHealthFeature.kFecal] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kCrawling)) return _featureQ(BeeHealthFeature.kCrawling);
    if (_answers[BeeHealthFeature.kSwollen] == BeeHealthValue.yes && !_answers.containsKey(BeeHealthFeature.kFecal)) return _featureQ(BeeHealthFeature.kFecal);

    // General sweep
    const sweep = <String>[
      BeeHealthFeature.kLarvae,
      BeeHealthFeature.kSpotted,
      BeeHealthFeature.kCrawling,
      BeeHealthFeature.kWing,
      BeeHealthFeature.kFecal,
      BeeHealthFeature.kSwollen,
    ];
    for (final f in sweep) {
      if (!_answers.containsKey(f)) return _featureQ(f);
    }
    if (!_answers.containsKey(BeeHealthFeature.kSour)) return _featureQ(BeeHealthFeature.kSour);
    return null;
  }

  BeeHealthQuestion _featureQ(String featureId) => BeeHealthQuestion(
    kind: QuestionKind.feature,
    featureId: featureId,
    promptKey: 'bh.q.$featureId',
    optionKeys: const ['bh.opt.yes', 'bh.opt.no', 'bh.opt.notsure'],
  );

  void reset() { _answers.clear(); _notSureCount = 0; _askedCount = 0; _started = false; }
}
