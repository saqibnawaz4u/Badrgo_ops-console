import 'package:badrgo_ops_console/core/connectivity/domain/health_repository.dart';
import 'package:badrgo_ops_console/core/connectivity/domain/maintenance_info.dart';
import 'package:badrgo_ops_console/core/connectivity/presentation/connectivity_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedHealth implements HealthRepository {
  _FixedHealth(this.result);

  HealthResult result;

  @override
  Future<HealthResult> check() async => result;
}

void main() {
  test('a later Retry-After during maintenance sets the next poll delay', () async {
    final health = _FixedHealth(const HealthMaintenance(
      MaintenanceInfo(message: 'down', retryAfter: Duration(seconds: 15)),
    ));
    final cubit = ConnectivityCubit(health)..reportMaintenance(const MaintenanceInfo(message: 'down'));
    // No Retry-After at first: ~2 s.
    expect(cubit.state.nextCheckAt!.difference(DateTime.now()).inMilliseconds, lessThan(3000));

    await cubit.checkNow();

    final delay = cubit.state.nextCheckAt!.difference(DateTime.now());
    expect(cubit.state.phase, ConnectivityPhase.maintenance);
    // 15 s ± 20% jitter.
    expect(delay.inSeconds, inInclusiveRange(11, 18));
    await cubit.close();
  });

  test('a huge Retry-After is still clamped to 15 s', () async {
    final health = _FixedHealth(const HealthMaintenance(
      MaintenanceInfo(message: 'down', retryAfter: Duration(hours: 1)),
    ));
    final cubit = ConnectivityCubit(health)..reportMaintenance(const MaintenanceInfo(message: 'down'));

    await cubit.checkNow();

    expect(cubit.state.nextCheckAt!.difference(DateTime.now()).inSeconds, inInclusiveRange(11, 18));
    await cubit.close();
  });
}
