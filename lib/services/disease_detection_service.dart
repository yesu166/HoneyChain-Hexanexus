import 'dart:typed_data';

import '../data/honeychain_store.dart';
import '../models/disease.dart';

/// An image to be screened (a photo of the brood/frame area of a hive).
class DiseaseImage {
  const DiseaseImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Abstraction over the hive disease screening model.
///
/// The UI only ever sees a [DiseaseScreeningResult]; it never talks to a
/// particular ML runtime. A demo implementation is used today and can be
/// swapped for a real on-device TensorFlow Lite / ONNX model later without
/// touching the UI.
abstract class DiseaseDetectionService {
  Future<DiseaseScreeningResult> screenImage(DiseaseImage image);
}

/// Qualitative indicator/action content produced for a possible-disease result.
class PossibleDiseaseContent {
  PossibleDiseaseContent._();

  static const indicators = [
    'Abnormal brood appearance',
    'Possible visual signs requiring inspection',
  ];

  static const actions = [
    'Inspect the affected frame',
    'Check surrounding brood',
    'Take another photo if needed',
    'Follow appropriate confirmation procedures',
  ];
}

/// Offline demo screening service. It simulates the future on-device model by
/// returning a qualitative result controlled through the store's demo
/// outcome (also used by the Profile simulation panel and widget tests).
class DemoDiseaseDetectionService implements DiseaseDetectionService {
  @override
  Future<DiseaseScreeningResult> screenImage(DiseaseImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final store = HoneyChainStore.instance;
    return switch (store.demoScreeningOutcome) {
      DiseaseScreenOutcome.possibleDisease => DiseaseScreeningResult(
          outcome: DiseaseScreenOutcome.possibleDisease,
          condition: DiseaseClassCatalog.byId('efb'),
          indicators: PossibleDiseaseContent.indicators,
          actions: PossibleDiseaseContent.actions,
        ),
      DiseaseScreenOutcome.unableToAssess => const DiseaseScreeningResult(
          outcome: DiseaseScreenOutcome.unableToAssess,
        ),
      DiseaseScreenOutcome.noObviousSigns => const DiseaseScreeningResult(
          outcome: DiseaseScreenOutcome.noObviousSigns,
        ),
    };
  }
}