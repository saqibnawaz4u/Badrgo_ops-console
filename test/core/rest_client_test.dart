import 'dart:async';

import 'package:badrgo_ops_console/core/connectivity/domain/maintenance_info.dart';
import 'package:badrgo_ops_console/core/error/api_exception.dart';
import 'package:badrgo_ops_console/core/network/rest_client.dart';
import 'package:badrgo_ops_console/core/network/session_signals.dart';
import 'package:badrgo_ops_console/core/network/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SessionSignals signals;
  late TokenStore tokens;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tokens = TokenStore(await SharedPreferences.getInstance());
    signals = SessionSignals();
  });

  tearDown(() => signals.dispose());

  RestClient client(MockClientHandler handler, {Duration timeout = const Duration(seconds: 20)}) => RestClient(
        baseUri: Uri.parse('https://api.test'),
        httpClient: MockClient(handler),
        tokens: tokens,
        signals: signals,
        timeout: timeout,
      );

  test('a hung request times out as a network failure', () async {
    var failures = 0;
    signals.networkFailure.listen((_) => failures++);
    final rest = client((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 50));

    await expectLater(
      rest.get('/api/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCode.network)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(failures, 1);
  });

  test('a 503 reports maintenance, even with an HTML body', () async {
    final reported = <MaintenanceInfo>[];
    signals.maintenance.listen(reported.add);
    final rest = client((_) async => http.Response('<html>down</html>', 503, headers: {'retry-after': '12'}));

    await expectLater(
      rest.get('/api/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCode.maintenance)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(reported.single.retryAfter, const Duration(seconds: 12));
  });
}
