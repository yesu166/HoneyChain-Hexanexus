import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_config.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/local_store.dart';
import 'package:honeychain/services/productivity_service.dart';

/// Contract tests for the productivity model service client.
///
/// The trained artifact (`honey_productivity_model.joblib`, an
/// ExtraTreesRegressor) is served by the existing FastAPI app
/// `productivity_api.py`. These tests pin the request/response contract of
/// `POST /predict-productivity` and prove that the client never invents a
/// yield when the service cannot answer.
void main() {
  ProductivityService serviceWith(MockClient mock) => ProductivityService(
        client: ApiClient(
          httpClient: mock,
          baseUrl: 'https://productivity.test.in',
        ),
      );

  const fullInputs = ProductivityInputs(
    apiary: 'Local Apiary',
    totalBrood: 5000,
    varroa2: 1.5,
    hygiene2: 90,
  );

  test('sends the four model inputs to the existing endpoint', () async {
    Map<String, dynamic>? sentBody;
    String? sentPath;
    String? sentMethod;

    final service = serviceWith(MockClient((request) async {
      sentPath = request.url.path;
      sentMethod = request.method;
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'predicted_honey_yield_kg': 32.28,
          'model': 'HoneyChain Productivity MVP',
        }),
        200,
      );
    }));

    final result = await service.predict(fullInputs);

    expect(sentMethod, 'POST');
    expect(sentPath, '/predict-productivity');
    // Exactly the four fields the model contract declares - nothing extra.
    expect(sentBody, <String, dynamic>{
      'apiary': 'Local Apiary',
      'total_brood': 5000.0,
      'varroa_2': 1.5,
      'hygiene_2': 90.0,
    });
    expect(result.predictedHoneyYieldKg, 32.28);
    expect(result.model, 'HoneyChain Productivity MVP');
  });

  test('parses a decimal kg response without rounding it', () async {
    final service = serviceWith(MockClient((_) async => http.Response(
          jsonEncode({
            'predicted_honey_yield_kg': 11.76,
            'model': 'HoneyChain Productivity MVP',
          }),
          200,
        )));

    final result = await service.predict(fullInputs);
    expect(result.predictedHoneyYieldKg, 11.76);
  });

  test('a failing model service throws instead of fabricating a yield',
      () async {
    final service = serviceWith(MockClient(
      (_) async => http.Response('{"detail":"model unavailable"}', 500),
    ));

    await expectLater(
      service.predict(fullInputs),
      throwsA(isA<ApiException>()),
    );
  });

  test('an unreachable model service surfaces a network ApiException',
      () async {
    final service = serviceWith(
      MockClient((_) async => throw http.ClientException('connection refused')),
    );

    await expectLater(
      service.predict(fullInputs),
      throwsA(isA<ApiException>()),
    );
  });

  test('missing colony measurements are listed, never defaulted', () {
    final partial = ColonyMeasurements.fromText(apiary: 'Local Apiary');

    expect(partial.missing, <String>['total_brood', 'varroa_2', 'hygiene_2']);
    expect(partial.isComplete, isFalse);
    // No payload at all - this is what keeps invented biology off the wire.
    expect(partial.toInputs(), isNull);
  });

  test('blank and non-numeric entries stay missing instead of defaulting', () {
    final measurements = ColonyMeasurements.fromText(
      apiary: '   ',
      totalBrood: 'abc',
      varroa2: '',
      hygiene2: '0',
    );

    expect(measurements.missing, <String>['apiary', 'total_brood', 'varroa_2']);
    expect(measurements.toInputs(), isNull);
    // A genuinely recorded zero is kept, not treated as missing.
    expect(measurements.hygiene2, 0);
  });

  test('complete measurements produce the exact model payload', () {
    final measurements = ColonyMeasurements.fromText(
      apiary: 'Local Apiary',
      totalBrood: '5000',
      varroa2: '1.5',
      hygiene2: '90',
    );

    expect(measurements.missing, isEmpty);
    expect(measurements.toInputs()!.toJson(), <String, dynamic>{
      'apiary': 'Local Apiary',
      'total_brood': 5000.0,
      'varroa_2': 1.5,
      'hygiene_2': 90.0,
    });
  });

  test('uses the shared backend host unless a dedicated one is compiled in',
      () {
    // No PRODUCTIVITY_API_BASE_URL dart-define is set for tests.
    expect(ProductivityService.hasDedicatedBaseUrl, isFalse);
    expect(ProductivityService.baseUrl, ApiConfig.normalizedBaseUrl);
    expect(ProductivityService.predictPath, '/predict-productivity');
  });

  test('measurements and the last model result survive a restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();

    await ProductivityCache.save(
      CachedProductivity(
        hiveId: 'hive-001',
        measurements: ColonyMeasurements.fromText(
          apiary: 'Local Apiary',
          totalBrood: '5000',
          varroa2: '1.5',
          hygiene2: '90',
        ),
        cachedAt: DateTime.utc(2026, 9, 21, 6),
        result: const ProductivityResult(
          predictedHoneyYieldKg: 32.28,
          model: 'HoneyChain Productivity MVP',
        ),
      ),
    );

    final restored = ProductivityCache.load('hive-001');
    expect(restored, isNotNull);
    expect(restored!.measurements.toInputs()!.toJson(), <String, dynamic>{
      'apiary': 'Local Apiary',
      'total_brood': 5000.0,
      'varroa_2': 1.5,
      'hygiene_2': 90.0,
    });
    // The restored number is the value the service returned earlier - it is
    // never recomputed on this device.
    expect(restored.result!.predictedHoneyYieldKg, 32.28);
    expect(restored.result!.model, 'HoneyChain Productivity MVP');
    expect(ProductivityCache.load('hive-unknown'), isNull);
  });

  test('a corrupted cache is ignored rather than crashing the screen',
      () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.init();
    // Explicitly write corruption AFTER init so the test is independent of the
    // SharedPreferences mock-leak between tests in this file.
    await LocalStore.instance.saveProductivityCache('not-json');
    expect(ProductivityCache.load('hive-001'), isNull);
  });
}
