import '../data/generated_bee_health_model.dart';

/// Offline Decision Tree interpreter.
/// Walks the exported arrays using `<= threshold → left, else right`.
/// Unasked features must be encoded as -1 (Not sure) — never as 0.
int predictConditionIndex(List<int> values) {
  var node = 0;
  while (kBeeHealthTreeFeature[node] != -1) {
    final f = kBeeHealthTreeFeature[node];
    final x = (f >= 0 && f < values.length) ? values[f] : -1;
    node = x <= kBeeHealthTreeThreshold[node]
        ? kBeeHealthTreeLeft[node]
        : kBeeHealthTreeRight[node];
  }
  return kBeeHealthTreeLeafClass[node];
}

double predictLeafPurity(List<int> values) {
  var node = 0;
  while (kBeeHealthTreeFeature[node] != -1) {
    final f = kBeeHealthTreeFeature[node];
    final x = (f >= 0 && f < values.length) ? values[f] : -1;
    node = x <= kBeeHealthTreeThreshold[node]
        ? kBeeHealthTreeLeft[node]
        : kBeeHealthTreeRight[node];
  }
  return kBeeHealthTreeLeafPurity[node];
}

/// Sanity check that the exported arrays have a consistent shape.
bool get isModelValid {
  final n = kBeeHealthTreeFeature.length;
  return n == kBeeHealthTreeThreshold.length &&
      n == kBeeHealthTreeLeft.length &&
      n == kBeeHealthTreeRight.length &&
      n == kBeeHealthTreeLeafClass.length &&
      n == kBeeHealthTreeLeafPurity.length;
}
