import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_config.dart';
import '../core/supabase/supabase_config.dart';
import 'connectivity_service.dart';

/// Real network + backend reachability check for mobile and desktop.
///
/// Uses connectivity_plus for real-time presence changes and a lightweight
/// probe of the backend health endpoint (plain HTTP, no SDK needed). "Wi-Fi
/// connected" is NOT treated as "backend reachable" — the badge only shows
/// online when the configured backend actually answered.
class ConnectivityServiceImpl extends ConnectivityService {
  ConnectivityServiceImpl({
    FutureOr<HttpClient> Function(Uri uri)? httpClientFactory,
    this.probeInterval,
  })  : _httpClientFactory = httpClientFactory ??
            ((Uri uri) => HttpClient()
              ..connectionTimeout = const Duration(seconds: 4)) {
    _subscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  final FutureOr<HttpClient> Function(Uri uri) _httpClientFactory;

  static const Duration _defaultProbeInterval = Duration(seconds: 30);
  final Duration? probeInterval;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;

  static Uri get _healthUri {
    // 1) The canonical backend (FastAPI). Wi-Fi axioms nothing: we probe
    //    /api/v1/health so the badge reflects *backend* reachability.
    if (ApiConfig.isConfigured) {
      return Uri.parse('${ApiConfig.normalizedBaseUrl}/api/v1/health');
    }
    // 2) Transitional Supabase-direct mode probes Supabase's health endpoint.
    final base = SupabaseConfig.url;
    if (base.isNotEmpty) {
      return Uri.parse('$base/auth/v1/health');
    }
    // 3) No backend compiled in: fall back to a plain reachability check so
    //    the badge still works before deployment.
    return Uri.parse('https://example.com');
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (!_hasNetwork(results)) {
      _stopTimer();
      setStatus(ConnectivityStatus.offline);
    } else {
      refresh();
    }
  }

  @override
  Future<void> refresh() async {
    final results = await Connectivity().checkConnectivity();
    if (!_hasNetwork(results)) {
      _stopTimer();
      setStatus(ConnectivityStatus.offline);
      return;
    }
    await _probe();
  }

  Future<void> _probe() async {
    setStatus(ConnectivityStatus.checking);
    HttpClient? client;
    try {
      final uri = _healthUri;
      final created = _httpClientFactory(uri);
      client = created is HttpClient ? created : await created;
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
            probeInterval ?? _defaultProbeInterval,
          );
      setStatus(
        response.statusCode < 400
            ? ConnectivityStatus.online
            : ConnectivityStatus.serviceError,
      );
    } on TimeoutException {
      setStatus(ConnectivityStatus.serviceError);
    } on SocketException {
      setStatus(ConnectivityStatus.serviceError);
    } on HttpException {
      setStatus(ConnectivityStatus.serviceError);
    } on ArgumentError {
      setStatus(ConnectivityStatus.serviceError);
    } catch (e) {
      debugPrint('Connectivity probe failed: $e');
      setStatus(ConnectivityStatus.serviceError);
    } finally {
      client?.close();
    }
    _startTimer();
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(
      probeInterval ?? _defaultProbeInterval,
      (_) => _probe(),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}