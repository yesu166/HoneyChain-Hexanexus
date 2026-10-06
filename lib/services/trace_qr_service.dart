import '../models/domain.dart';

/// The single canonical Honey Yatra QR payload contract for the whole app.
///
/// Every consumer-facing QR encodes one of this app's own schemes and nothing
/// else. Resolution against real records happens in the store, so this class
/// only owns the *format*: build, parse and validate.
///
///   `honeychain://trace/<productCode>`   -> traced product (canonical)
///   `honeychain://jar/<jarId>`           -> packed jar (legacy, compatible)
abstract final class TraceQrService {
  static const String scheme = 'honeychain://';
  static const String tracePath = 'trace';
  static const String jarPath = 'jar';

  static String buildForProduct(String productCode) =>
      '$scheme$tracePath/$productCode';

  static String buildForJar(String jarId) => '$scheme$jarPath/$jarId';

  /// A jar payload is accepted as-is; the trace (product) scheme is the
  /// canonical format all new codes must use.
  static bool isValid(String? raw) => parse(raw) != null;

  static TraceQrPayload? parse(String? raw) {
    if (raw == null) return null;
    final input = raw.trim();
    if (input.isEmpty || !input.toLowerCase().startsWith(scheme)) return null;
    final rest = input.substring(scheme.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    final type = rest.substring(0, slash).toLowerCase();
    final code = rest.substring(slash + 1).trim();
    if (code.isEmpty) return null;
    if (type != tracePath && type != jarPath) return null;
    return TraceQrPayload(type: type, code: code);
  }
}

class TraceQrPayload {
  const TraceQrPayload({required this.type, required this.code});

  /// 'trace' or 'jar'.
  final String type;
  final String code;

  bool get isTrace => type == TraceQrService.tracePath;
  bool get isJar => type == TraceQrService.jarPath;
}

/// Result of resolving a scanned or typed string against the store.
sealed class ScanResolution {
  const ScanResolution();
}

class ScanResolutionJar extends ScanResolution {
  const ScanResolutionJar(this.jar);
  final HoneyJar jar;
}

class ScanResolutionProduct extends ScanResolution {
  const ScanResolutionProduct(this.product);
  final ProductBatch product;
}

class ScanResolutionBatch extends ScanResolution {
  const ScanResolutionBatch(this.batch);
  final Batch batch;
}

class ScanResolutionUnknown extends ScanResolution {
  const ScanResolutionUnknown(this.reason);
  final String reason;
}