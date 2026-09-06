import '../models/bee_health_models.dart';
import 'bee_health_tree.dart' as tree;

class BeeHealthPredictionService {
  const BeeHealthPredictionService();

  BeeHealthPrediction predict({required Map<String, BeeHealthValue> answers}) {
    final values = List<int>.filled(8, -1);
    for (final entry in answers.entries) {
      final idx = BeeHealthFeature.indexOf(entry.key);
      if (idx >= 0) values[idx] = entry.value.code;
    }
    final idx = tree.predictConditionIndex(values);
    final purity = tree.predictLeafPurity(values);
    final condition = BeeCondition.byIndex(idx);
    return BeeHealthPrediction(
      condition: condition,
      leafPurity: purity,
      isUnknownCoerced: false,
    );
  }
}
