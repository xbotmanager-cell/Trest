enum AiErrorKind {
  missingCredentials,
  unauthorized,
  rateLimited,
  timeout,
  network,
  badRequest,
  serverError,
  cancelled,
  unknown,
}

class AiException implements Exception {
  const AiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.providerId,
    this.retryable = false,
  });

  final AiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? providerId;
  final bool retryable;

  @override
  String toString() =>
      'AiException(${kind.name}, status=$statusCode): $message';
}
