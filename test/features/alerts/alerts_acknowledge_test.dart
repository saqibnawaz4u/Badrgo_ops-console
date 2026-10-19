import 'dart:async';

import 'package:badrgo_ops_console/features/alerts/domain/entities/alert.dart';
import 'package:badrgo_ops_console/features/alerts/domain/repositories/alerts_repository.dart';
import 'package:badrgo_ops_console/features/alerts/presentation/bloc/alerts_feed_cubit.dart';
import 'package:badrgo_ops_console/features/alerts/presentation/bloc/critical_alerts_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/roles.dart';

class _MockAlertsRepository extends Mock implements AlertsRepository {}

Alert _alert(String id, {AlertSeverity severity = AlertSeverity.warning, DateTime? acknowledgedAt}) => Alert(
      id: id,
      type: AlertType.highDemand,
      severity: severity,
      message: 'Alert $id',
      createdAt: DateTime.utc(2026, 10, 19, 10),
      cityName: 'Doha',
      acknowledgedAt: acknowledgedAt,
      acknowledgedBy: acknowledgedAt == null ? null : 'usr_other',
    );

void main() {
  late _MockAlertsRepository repository;
  late StreamController<AlertChange> live;

  setUp(() {
    repository = _MockAlertsRepository();
    live = StreamController<AlertChange>.broadcast();
    when(() => repository.watchChanges()).thenAnswer((_) => live.stream);
    when(() => repository.acknowledge(any())).thenAnswer((_) async {});
  });

  tearDown(() => live.close());

  void serve(List<Alert> alerts, {required int totalCount, bool? acknowledged}) =>
      when(() => repository.fetchAlerts(acknowledged: acknowledged)).thenAnswer(
        (_) async => AlertPage(alerts: alerts, endCursor: null, hasNextPage: false, totalCount: totalCount),
      );

  Future<AlertsFeedCubit> startedFeed() async {
    final cubit = AlertsFeedCubit(repository, permissions: permissionsFor('dispatcher'));
    await cubit.start();
    return cubit;
  }

  group('AlertsFeedCubit.acknowledge', () {
    test('under Open, removes the row and decrements once; the SSE echo is a no-op', () async {
      serve([_alert('a1'), _alert('a2')], totalCount: 5, acknowledged: false);
      final cubit = await startedFeed();

      await cubit.acknowledge(cubit.state.items.first);
      expect(cubit.state.items.map((a) => a.id), ['a2']);
      expect(cubit.state.totalCount, 4);
      expect(cubit.state.acknowledging, isEmpty);

      live.add(AlertChange(_alert('a1', acknowledgedAt: DateTime.utc(2026, 10, 19, 11)), isNew: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.map((a) => a.id), ['a2']);
      expect(cubit.state.totalCount, 4);
      await cubit.close();
    });

    test('under Open, a colleague acknowledging over SSE removes the row and decrements', () async {
      serve([_alert('a1'), _alert('a2')], totalCount: 5, acknowledged: false);
      final cubit = await startedFeed();

      live.add(AlertChange(_alert('a2', acknowledgedAt: DateTime.utc(2026, 10, 19, 11)), isNew: false));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.items.map((a) => a.id), ['a1']);
      expect(cubit.state.totalCount, 4);
      verifyNever(() => repository.acknowledge(any()));
      await cubit.close();
    });

    test('under Open, an SSE echo that beats the REST answer still decrements only once', () async {
      serve([_alert('a1'), _alert('a2')], totalCount: 2, acknowledged: false);
      final rest = Completer<void>();
      when(() => repository.acknowledge('a1')).thenAnswer((_) => rest.future);
      final cubit = await startedFeed();

      final ack = cubit.acknowledge(cubit.state.items.first);
      live.add(AlertChange(_alert('a1', acknowledgedAt: DateTime.utc(2026, 10, 19, 11)), isNew: false));
      await Future<void>.delayed(Duration.zero);
      // The SSE frame already takes the row out of "Open".
      expect(cubit.state.items.map((a) => a.id), ['a2']);
      expect(cubit.state.totalCount, 1);
      rest.complete();
      await ack;

      expect(cubit.state.items.map((a) => a.id), ['a2']);
      expect(cubit.state.totalCount, 1);
      await cubit.close();
    });

    test('under All, marks the row acknowledged right away and keeps the count', () async {
      serve([_alert('a1')], totalCount: 1, acknowledged: false);
      serve([_alert('a1')], totalCount: 1);
      final cubit = await startedFeed();
      await cubit.setOpenOnly(false);

      await cubit.acknowledge(cubit.state.items.first);
      expect(cubit.state.items.single.isOpen, isFalse);
      expect(cubit.state.totalCount, 1);

      final server = _alert('a1', acknowledgedAt: DateTime.utc(2026, 10, 19, 11));
      live.add(AlertChange(server, isNew: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.single.acknowledgedAt, server.acknowledgedAt);
      expect(cubit.state.items.single.acknowledgedBy, 'usr_other');
      expect(cubit.state.totalCount, 1);
      await cubit.close();
    });
  });

  test('CriticalAlertsCubit drops the SOS on acknowledge and ignores the SSE echo', () async {
    final sos = _alert('s1', severity: AlertSeverity.critical);
    when(() => repository.fetchAlerts(acknowledged: false, criticalOnly: true, first: 20)).thenAnswer(
      (_) async => AlertPage(alerts: [sos], endCursor: null, hasNextPage: false, totalCount: 1),
    );
    final cubit = CriticalAlertsCubit(repository, permissions: permissionsFor('dispatcher'));
    await cubit.start();
    expect(cubit.state.open, [sos]);

    await cubit.acknowledge(sos);
    expect(cubit.state.open, isEmpty);

    live.add(AlertChange(_alert('s1', severity: AlertSeverity.critical, acknowledgedAt: DateTime.now()), isNew: false));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.open, isEmpty);
    await cubit.close();
  });
}
