import '../error/api_exception.dart';
import 'rest_client.dart';

/// Minimal GraphQL client: one POST to `/graphql`. Reads only, writes go
/// through REST. Errors carry `extensions.code`, and UNAUTHENTICATED comes
/// back with HTTP 200, so we map it here and raise the same signals as REST.
class GraphQLClient {
  GraphQLClient(this._rest);

  final RestClient _rest;

  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
  }) async {
    final sentToken = _rest.currentToken;
    final body = await _rest.post('/graphql', body: {
      'query': document,
      if (variables.isNotEmpty) 'variables': variables,
    });
    if (body is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorCode.unknown, 'Unexpected GraphQL response.');
    }
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final error = _toException(errors.first);
      _rest.reportAuthProblems(error, sentToken: sentToken);
      throw error;
    }
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  static ApiException _toException(Object? error) {
    if (error is! Map) {
      return const ApiException(ApiErrorCode.unknown, 'GraphQL request failed.');
    }
    final extensions = error['extensions'];
    final code = extensions is Map ? extensions['code'] as String? : null;
    return ApiException(
      ApiErrorCode.fromServer(code),
      (error['message'] as String?) ?? 'GraphQL request failed.',
      serverCode: code,
      details: extensions,
    );
  }
}
