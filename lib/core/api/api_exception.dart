/// Failure kinds surfaced by the [ApiClient], mapped to user-friendly copy.
enum ApiExceptionKind {
  network,
  timeout,
  auth,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiExceptionKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(${kind.name}, $statusCode): $message';

  /// Short, human-safe description for snack bars / error cards.
  String get friendly => switch (kind) {
        ApiExceptionKind.network =>
          'No network connection. Your data is saved and will sync later.',
        ApiExceptionKind.timeout =>
          'The server is taking too long. Please try again.',
        ApiExceptionKind.auth =>
          'Session expired. Please sign in again.',
        ApiExceptionKind.forbidden =>
          'You do not have permission for this action.',
        ApiExceptionKind.notFound => 'Not found on the server.',
        ApiExceptionKind.conflict =>
          'The server already has this record (kept the original).',
        ApiExceptionKind.validation => message.isEmpty
            ? 'The request was not valid.'
            : message,
        ApiExceptionKind.server =>
          'The server had a problem. Please try again later.',
        ApiExceptionKind.unknown =>
          message.isEmpty ? 'Something went wrong.' : message,
      };
}