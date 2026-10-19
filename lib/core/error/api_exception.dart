import 'package:equatable/equatable.dart';

/// Error codes shared by REST, GraphQL (`extensions.code`) and WebSocket
/// `error` frames. Anything else maps to [unknown].
enum ApiErrorCode {
  unauthenticated,
  forbidden,
  notFound,
  invalidState,
  validationFailed,
  conflict,
  maintenance,
  network,
  unknown;

  static ApiErrorCode fromServer(String? code, {int? httpStatus}) {
    switch (code) {
      case 'UNAUTHENTICATED':
      case 'INVALID_EMAIL_OR_PASSWORD':
        return ApiErrorCode.unauthenticated;
      case 'FORBIDDEN':
      case 'BANNED_USER':
        return ApiErrorCode.forbidden;
      case 'NOT_FOUND':
        return ApiErrorCode.notFound;
      case 'INVALID_STATE':
        return ApiErrorCode.invalidState;
      case 'VALIDATION_FAILED':
      case 'BAD_USER_INPUT':
        return ApiErrorCode.validationFailed;
      case 'CONFLICT':
        return ApiErrorCode.conflict;
      case 'MAINTENANCE':
        return ApiErrorCode.maintenance;
    }
    return switch (httpStatus) {
      401 => ApiErrorCode.unauthenticated,
      403 => ApiErrorCode.forbidden,
      404 => ApiErrorCode.notFound,
      409 => ApiErrorCode.invalidState,
      400 || 422 => ApiErrorCode.validationFailed,
      503 => ApiErrorCode.maintenance,
      _ => ApiErrorCode.unknown,
    };
  }
}

/// The one error type the data layer throws. Blocs switch on [code].
class ApiException extends Equatable implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.serverCode,
    this.httpStatus,
    this.details,
    this.fieldErrors = const {},
  });

  const ApiException.network([String message = 'Cannot reach the server.'])
      : this(ApiErrorCode.network, message);

  final ApiErrorCode code;
  final String message;

  /// The raw server code, e.g. `BANNED_USER`.
  final String? serverCode;
  final int? httpStatus;
  final Object? details;

  /// Field path → message, from `details.issues` on VALIDATION_FAILED.
  final Map<String, String> fieldErrors;

  /// Builds an exception from either error shape the API returns:
  /// `{ "error": { code, message, details } }` (our API) or
  /// `{ "code", "message" }` (Better Auth endpoints such as sign-in).
  factory ApiException.fromBody(Object? body, {int? httpStatus}) {
    String? code;
    String? message;
    Object? details;
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        code = error['code'] as String?;
        message = error['message'] as String?;
        details = error['details'];
      } else {
        code = body['code'] as String?;
        message = body['message'] as String?;
      }
    }
    final mapped = ApiErrorCode.fromServer(code, httpStatus: httpStatus);
    return ApiException(
      mapped,
      (message == null || message.isEmpty) ? _fallbackMessage(mapped) : message,
      serverCode: code,
      httpStatus: httpStatus,
      details: details,
      fieldErrors: _fieldErrors(details),
    );
  }

  static Map<String, String> _fieldErrors(Object? details) {
    if (details is! Map || details['issues'] is! List) return const {};
    final result = <String, String>{};
    for (final issue in details['issues'] as List) {
      if (issue is Map && issue['message'] is String) {
        final path = issue['path'];
        final key = path is List ? path.join('.') : '${path ?? ''}';
        result.putIfAbsent(key, () => issue['message'] as String);
      }
    }
    return result;
  }

  static String _fallbackMessage(ApiErrorCode code) => switch (code) {
        ApiErrorCode.unauthenticated => 'Your session has ended. Please sign in again.',
        ApiErrorCode.forbidden => 'You do not have permission to do that.',
        ApiErrorCode.notFound => 'Not found.',
        ApiErrorCode.invalidState => 'This changed in the meantime. Refresh and try again.',
        ApiErrorCode.validationFailed => 'Please check the highlighted fields.',
        ApiErrorCode.conflict => 'This conflicts with existing data.',
        ApiErrorCode.maintenance => 'The service is under maintenance.',
        ApiErrorCode.network => 'Cannot reach the server.',
        ApiErrorCode.unknown => 'Something went wrong.',
      };

  @override
  List<Object?> get props => [code, message, serverCode, httpStatus, fieldErrors];

  @override
  String toString() => 'ApiException($code, $message)';
}
