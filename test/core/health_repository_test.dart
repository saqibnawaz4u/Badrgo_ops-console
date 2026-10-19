import 'package:badrgo_ops_console/core/connectivity/data/health_repository_impl.dart';
import 'package:badrgo_ops_console/core/connectivity/domain/health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  HealthRepositoryImpl repo(http.Response response) => HealthRepositoryImpl(
        baseUri: Uri.parse('https://api.test'),
        httpClient: MockClient((_) async => response),
      );

  test('a 503 with a non-JSON body is still maintenance', () async {
    final result = await repo(http.Response('<html>Bad gateway</html>', 503, headers: {'retry-after': '7'})).check();

    expect(result, isA<HealthMaintenance>());
    final info = (result as HealthMaintenance).info;
    expect(info.retryAfter, const Duration(seconds: 7));
    expect(info.message, 'The service is under maintenance.');
  });

  test('a 503 JSON body is parsed', () async {
    final result = await repo(http.Response(
      '{"status":"maintenance","reason":"planned","retryAfterSeconds":30}',
      503,
    )).check();

    final info = (result as HealthMaintenance).info;
    expect(info.isPlanned, isTrue);
    expect(info.retryAfter, const Duration(seconds: 30));
  });

  test('other errors are unreachable', () async {
    expect(await repo(http.Response('', 502)).check(), isA<HealthUnreachable>());
  });
}
