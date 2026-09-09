import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Canonical HTTP client for the FastAPI backend.
///
/// - Adds the bearer token when one is available ([tokenProvider]).
/// - Maps transport + status failures to a small set of [ApiExceptionKind]s so
///   the UI never shows raw stack traces.
/// - Always uses the compiled-in production base URL; never localhost.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.tokenProvider,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
  })  : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.normalizedBaseUrl {
    assert(this.baseUrl.isNotEmpty);
  }

  final http.Client _http;
  final String baseUrl;
  final Duration timeout;

  /// Returns the current JWT, or null when signed out.
  final String? Function()? tokenProvider;

  Future<Map<String, dynamic>> getJson(String path) =>
      _request('GET', path);

  /// GET that expects a JSON array. The transport wraps arrays in
  /// `{"data": [...]}`; this unwraps it and never throws on shape mismatch.
  Future<List<dynamic>> getListJson(String path) async {
    final body = await _request('GET', path);
    final data = body['data'];
    if (data is List) return data;
    return const <dynamic>[];
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _request('POST', path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response response;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(timeout),
        _ => await _http
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(timeout),
      };
    } on TimeoutException {
      throw const ApiException(ApiExceptionKind.timeout, '');
    } on SocketException {
      throw const ApiException(ApiExceptionKind.network, '');
    } on http.ClientException {
      throw const ApiException(ApiExceptionKind.network, '');
    } on HandshakeException {
      throw const ApiException(ApiExceptionKind.network, '');
    }

    return _decode(response);
  }

  String? get _token => tokenProvider?.call();

  Map<String, dynamic> _decode(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    }
    final detail = _extractDetail(response);
    throw ApiException(
      _kindFor(status),
      detail,
      statusCode: status,
    );
  }

  static String _extractDetail(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List) {
          return detail
              .map((e) => e is Map ? e['msg'] ?? '' : '$e')
              .where((s) => s.isNotEmpty)
              .join('; ');
        }
      }
    } on FormatException {
      // non-JSON body — fall through to status text
    }
    return response.reasonPhrase ?? '';
  }

  static ApiExceptionKind _kindFor(int status) => switch (status) {
        401 => ApiExceptionKind.auth,
        403 => ApiExceptionKind.forbidden,
        404 => ApiExceptionKind.notFound,
        409 => ApiExceptionKind.conflict,
        422 => ApiExceptionKind.validation,
        _ when status >= 500 => ApiExceptionKind.server,
        _ => ApiExceptionKind.unknown,
      };

  void dispose() => _http.close();
}