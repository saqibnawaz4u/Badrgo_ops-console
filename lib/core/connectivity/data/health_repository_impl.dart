import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/health_repository.dart';
import '../domain/maintenance_info.dart';

/// Talks to `/api/health` with a plain HTTP client on purpose: it is the
/// probe that decides whether we are in maintenance, so it must not feed
/// back into the global session signals.
class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl({required Uri baseUri, required http.Client httpClient})
      : _uri = baseUri.replace(path: '${baseUri.path}/api/health'),
        _http = httpClient;

  final Uri _uri;
  final http.Client _http;

  @override
  Future<HealthResult> check() async {
    try {
      final response = await _http.get(_uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return const HealthUp();
      if (response.statusCode == 503) {
        // A proxy's HTML 503 page still means "down on purpose", not offline.
        final body = _tryDecode(response.body);
        final retry = int.tryParse(response.headers['retry-after'] ?? '');
        return HealthMaintenance(MaintenanceInfo.fromJson(
          body is Map<String, dynamic> ? body : const {},
          retryAfter: retry == null ? null : Duration(seconds: retry),
        ));
      }
      return const HealthUnreachable();
    } on Object {
      return const HealthUnreachable();
    }
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
