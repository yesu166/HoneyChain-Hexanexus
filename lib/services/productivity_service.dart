import 'dart:convert';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/api/api_exception.dart';
import 'local_store.dart';

/// Inputs of the already-trained HoneyChain productivity model.
///
/// This mirrors the request contract of the existing FastAPI model-serving
/// layer (`productivity_api.py`, `POST /predict-productivity`), which serves
/// the trained artifact `honey_productivity_model.joblib` (an
/// ExtraTreesRegressor: `apiary`, `total_brood`, `varroa_2`, `hygiene_2` →
/// total honey production in kg). Nothing here is computed locally.
class ProductivityInputs {
  const ProductivityInputs({
    required this.apiary,
    required this.totalBrood,
    required this.varroa2,
    required this.hygiene2,
  });

  final String apiary;
  final double totalBrood;
  final double varroa2;
  final double hygiene2;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiary': apiary,
        'total_brood': totalBrood,
        'varroa_2': varroa2,
        'hygiene_2': hygiene2,
      };
}

/// A single prediction returned by the model service.
class ProductivityResult {
  const ProductivityResult({
    required this.predictedHoneyYieldKg,
    this.model = '',
  });

  final double predictedHoneyYieldKg;

  /// Model name reported by the service (e.g. "HoneyChain Productivity MVP").
  final String model;

  factory ProductivityResult.fromJson(Map<String, dynamic> json) =>
      ProductivityResult(
        predictedHoneyYieldKg:
            (json['predicted_honey_yield_kg'] as num?)?.toDouble() ?? 0,
        model: json['model'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'predicted_honey_yield_kg': predictedHoneyYieldKg,
        'model': model,
      };
}

/// Colony measurements the trained model needs, as recorded by the beekeeper.
///
/// IMPORTANT — why every field is nullable: the local HoneyChain data model
/// stores none of the biological model inputs. `Hive` holds only identity and
/// location data (id, name, beekeeper, organization, location, honey type) and
/// `HiveReading` holds only telemetry (temperature, humidity, weight). There is
/// therefore **no** stored source for `total_brood`, `varroa_2` or `hygiene_2`.
///
/// This class never substitutes a default for a missing value: [missing] is the
/// honest list of what the model still needs, and [toInputs] returns null until
/// the beekeeper supplies it.
class ColonyMeasurements {
  const ColonyMeasurements({
    this.apiary,
    this.totalBrood,
    this.varroa2,
    this.hygiene2,
  });

  final String? apiary;
  final double? totalBrood;
  final double? varroa2;
  final double? hygiene2;

  /// Builds measurements from raw form text. Blank or unparsable entries stay
  /// null so they are reported as missing instead of being invented.
  factory ColonyMeasurements.fromText({
    String? apiary,
    String? totalBrood,
    String? varroa2,
    String? hygiene2,
  }) =>
      ColonyMeasurements(
        apiary: _text(apiary),
        totalBrood: _number(totalBrood),
        varroa2: _number(varroa2),
        hygiene2: _number(hygiene2),
      );

  static String? _text(String? raw) {
    final value = (raw ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static double? _number(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  /// Model input names that still have no recorded value, in the order of the
  /// model contract. Empty once the beekeeper has supplied everything.
  List<String> get missing => <String>[
        if (_text(apiary) == null) 'apiary',
        if (totalBrood == null) 'total_brood',
        if (varroa2 == null) 'varroa_2',
        if (hygiene2 == null) 'hygiene_2',
      ];

  bool get isComplete => missing.isEmpty;

  /// The request payload, or null while an input is missing.
  ///
  /// Returning null instead of a payload with placeholder numbers is what keeps
  /// the screen from sending invented biology to the model.
  ProductivityInputs? toInputs() => isComplete
      ? ProductivityInputs(
          apiary: _text(apiary)!,
          totalBrood: totalBrood!,
          varroa2: varroa2!,
          hygiene2: hygiene2!,
        )
      : null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiary': apiary,
        'totalBrood': totalBrood,
        'varroa2': varroa2,
        'hygiene2': hygiene2,
      };

  factory ColonyMeasurements.fromJson(Map<String, dynamic> json) =>
      ColonyMeasurements(
        apiary: json['apiary'] as String?,
        totalBrood: (json['totalBrood'] as num?)?.toDouble(),
        varroa2: (json['varroa2'] as num?)?.toDouble(),
        hygiene2: (json['hygiene2'] as num?)?.toDouble(),
      );
}

/// Measurements plus the last successful prediction for one hive, persisted
/// locally so the screen works offline across restarts.
class CachedProductivity {
  const CachedProductivity({
    required this.hiveId,
    required this.measurements,
    required this.cachedAt,
    this.result,
  });

  final String hiveId;
  final ColonyMeasurements measurements;
  final DateTime cachedAt;
  final ProductivityResult? result;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hiveId': hiveId,
        'measurements': measurements.toJson(),
        'cachedAt': cachedAt.toIso8601String(),
        'result': result?.toJson(),
      };

  factory CachedProductivity.fromJson(Map<String, dynamic> json) =>
      CachedProductivity(
        hiveId: json['hiveId'] as String? ?? '',
        measurements: ColonyMeasurements.fromJson(
          (json['measurements'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        ),
        cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
            DateTime.now(),
        result: json['result'] is Map
            ? ProductivityResult.fromJson(
                (json['result'] as Map).cast<String, dynamic>(),
              )
            : null,
      );
}

/// Offline-first, per-hive cache for productivity measurements and results.
class ProductivityCache {
  ProductivityCache._();

  static const String storageKey = 'honey.productivityCache';

  static Future<void> save(CachedProductivity entry) async {
    final all = _all();
    all[entry.hiveId] = entry.toJson();
    await LocalStore.instance.saveProductivityCache(jsonEncode(all));
  }

  static CachedProductivity? load(String hiveId) {
    final raw = _all()[hiveId];
    if (raw is! Map) return null;
    return CachedProductivity.fromJson(raw.cast<String, dynamic>());
  }

  static Map<String, dynamic> _all() {
    final raw = LocalStore.instance.loadProductivityCache();
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      // Corrupted cache — behave as if nothing was stored.
    }
    return <String, dynamic>{};
  }
}

/// Client for the existing HoneyChain productivity model service.
///
/// The trained artifact (`honey_productivity_model.joblib`) is served by the
/// existing FastAPI app `productivity_api.py`. This class only calls that
/// endpoint: it contains no model, no coefficients and no fallback number, so a
/// failure surfaces as a truthful error instead of a fabricated yield.
///
/// The service is hosted separately from the main HoneyChain backend, so the
/// host can be compiled in with
/// `--dart-define=PRODUCTIVITY_API_BASE_URL=http://10.0.2.2:8000`
/// (Android emulator → host machine). When that define is absent the shared
/// `--dart-define=API_BASE_URL` backend is used.
class ProductivityService {
  ProductivityService({this.client});

  /// Optional pre-configured client (used by tests and callers that already
  /// hold a base URL + token provider).
  final ApiClient? client;

  /// Dedicated host for the model service, compiled in at build time.
  static const String configuredBaseUrl =
      String.fromEnvironment('PRODUCTIVITY_API_BASE_URL');

  /// Path of the existing endpoint — unchanged from `productivity_api.py`.
  static const String predictPath = '/predict-productivity';

  /// Base URL actually used: the dedicated override when one was compiled in,
  /// otherwise the shared backend. A trailing slash is trimmed so path joining
  /// stays identical to [ApiConfig].
  static String get baseUrl {
    final override = configuredBaseUrl.trim();
    if (override.isEmpty) return ApiConfig.normalizedBaseUrl;
    return override.endsWith('/')
        ? override.substring(0, override.length - 1)
        : override;
  }

  /// True when a productivity endpoint host is available at all.
  static bool get isConfigured => baseUrl.isNotEmpty;

  /// True when the dedicated productivity host was compiled in.
  static bool get hasDedicatedBaseUrl => configuredBaseUrl.trim().isNotEmpty;

  /// Calls the model service and returns its prediction.
  ///
  /// Throws [ApiException] when the service is unconfigured, unreachable or
  /// returns a non-2xx response, so the UI can show a friendly error with a
  /// retry instead of a made-up value.
  Future<ProductivityResult> predict(ProductivityInputs inputs) async {
    final injected = client;
    if (injected != null) {
      final json = await injected.postJson(predictPath, body: inputs.toJson());
      return ProductivityResult.fromJson(json);
    }

    final endpoint = baseUrl;
    if (endpoint.isEmpty) {
      throw const ApiException(
        ApiExceptionKind.network,
        'Productivity service not configured',
      );
    }

    final owned = ApiClient(baseUrl: endpoint);
    try {
      final json = await owned.postJson(predictPath, body: inputs.toJson());
      return ProductivityResult.fromJson(json);
    } finally {
      owned.dispose();
    }
  }
}
