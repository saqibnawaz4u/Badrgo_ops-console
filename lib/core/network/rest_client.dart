import 'dart:convert';

import 'package:http/http.dart' as http;

import '../connectivity/domain/maintenance_info.dart';
import '../error/api_exception.dart';
import 'session_signals.dart';
import 'token_store.dart';

/// Thin JSON-over-HTTP client used for REST and as the transport under the
/// GraphQL client. It attaches the bearer token, turns error bodies into
/// [ApiException]s and raises [SessionSignals] for 401/403/503/network.
class RestClient {
  RestClient({
    required Uri baseUri,
    required http.Client httpClient,
    required TokenStore tokens,
    required SessionSignals signals,
    this.timeout = const Duration(seconds: 20),
  })  : _base = baseUri,
        _http = httpClient,
        _tokens = tokens,
        _signals = signals;

  final Uri _base;
  final http.Client _http;
  final TokenStore _tokens;
  final SessionSignals _signals;

  /// Covers sending and reading the whole body, so a hung request fails
  /// like any other network error instead of waiting forever.
  final Duration timeout;

  Uri resolve(String path, [Map<String, String?>? query]) {
    final cleaned = {
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return _base.replace(
      path: '${_base.path}$path',
      queryParameters: cleaned.isEmpty ? null : cleaned,
    );
  }

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, bool authenticated = true}) =>
      send('POST', path, body: body ?? const <String, dynamic>{}, authenticated: authenticated);

  Future<dynamic> patch(String path, {Object? body}) => send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => send('DELETE', path);

  /// [authenticated] = false is for sign-in: its 401 means "wrong password",
  /// not "session expired", so it must not trigger the global sign-out.
  Future<dynamic> send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    final token = authenticated ? _tokens.token : null;
    final request = http.Request(method, resolve(path, query))
      ..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await _http.send(request).then(http.Response.fromStream).timeout(timeout);
    } on Exception {
      // Includes the TimeoutException from [timeout].
      _signals.reportNetworkFailure();
      throw const ApiException.network();
    }
    return handleResponse(response, sentToken: token);
  }

  /// Shared by GraphQL, which reuses the HTTP status handling.
  dynamic handleResponse(http.Response response, {required String? sentToken}) {
    final decoded = _decode(response.body);
    final status = response.statusCode;
    if (status >= 200 && status < 300) return decoded;

    if (status == 503) {
      final retryHeader = int.tryParse(response.headers['retry-after'] ?? '');
      final info = MaintenanceInfo.fromJson(
        decoded is Map<String, dynamic> ? decoded : const {},
        retryAfter: retryHeader == null ? null : Duration(seconds: retryHeader),
      );
      _signals.reportMaintenance(info);
      throw ApiException(ApiErrorCode.maintenance, info.message, httpStatus: 503);
    }

    final error = ApiException.fromBody(decoded, httpStatus: status);
    reportAuthProblems(error, sentToken: sentToken);
    throw error;
  }

  /// Only report a 401 for the token that is still current, so a slow
  /// response from a previous session cannot sign the next user out.
  void reportAuthProblems(ApiException error, {required String? sentToken}) {
    if (sentToken == null || sentToken != _tokens.token) return;
    if (error.code == ApiErrorCode.unauthenticated) _signals.reportUnauthorized();
    if (error.code == ApiErrorCode.forbidden) _signals.reportForbidden();
  }

  String? get currentToken => _tokens.token;

  static Object? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
