import 'dart:async';

import 'package:badrgo_ops_console/core/connectivity/presentation/connectivity_cubit.dart';
import 'package:badrgo_ops_console/core/domain/shared_entities.dart';
import 'package:badrgo_ops_console/core/error/api_exception.dart';
import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/core/realtime/live_status_cubit.dart';
import 'package:badrgo_ops_console/core/realtime/realtime_status.dart';
import 'package:badrgo_ops_console/features/dashboard/domain/entities/kpis.dart';
import 'package:badrgo_ops_console/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:badrgo_ops_console/features/dashboard/presentation/bloc/dashboard_cubit.dart';
import 'package:badrgo_ops_console/features/dashboard/presentation/dashboard_page.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDashboardRepository extends Mock implements DashboardRepository {}

class _MockConnectivityCubit extends MockCubit<ConnectivityState> implements ConnectivityCubit {}

class _MockLiveStatusCubit extends MockCubit<LiveStatusState> implements LiveStatusCubit {}

const _failure = ApiException(ApiErrorCode.unknown, 'Server error.');

Kpis _kpis(KpiRange range, {int total = 1}) => Kpis(
      range: range,
      generatedAt: DateTime.utc(2026, 10, 19, 12),
      trips: const TripCounts(
        requested: 0,
        assigned: 0,
        inProgress: 0,
        completed: 0,
        cancelled: 0,
        active: 0,
        cancellationRate: 0,
      ),
      revenue: const [Money(0, 'QAR')],
      averageFare: const [Money(0, 'QAR')],
      refunds: const [],
      drivers: const DriverCounts(available: 0, onTrip: 0, offline: 0, total: 0),
      openAlerts: 0,
      series: [SeriesPoint(bucket: DateTime.utc(2026, 10, 19), total: total, completed: 0, cancelled: 0)],
      topDrivers: const [],
    );

void main() {
  late _MockDashboardRepository repository;
  final day = _kpis(KpiRange.last24h, total: 24);
  final week = _kpis(KpiRange.last7d, total: 7);

  setUp(() {
    repository = _MockDashboardRepository();
    when(() => repository.watchKpis()).thenAnswer((_) => const Stream.empty());
    when(() => repository.fetchKpis(KpiRange.last24h)).thenAnswer((_) async => day);
  });

  group('DashboardCubit chart range', () {
    test('a 7d answer that lands after switching back to 24h is dropped and clears the spinner', () async {
      final pending = Completer<Kpis>();
      when(() => repository.fetchKpis(KpiRange.last7d)).thenAnswer((_) => pending.future);
      final cubit = DashboardCubit(repository);
      await cubit.load();

      final toWeek = cubit.selectRange(KpiRange.last7d);
      expect(cubit.state.chartLoading, isTrue);
      await cubit.selectRange(KpiRange.last24h);
      pending.complete(week);
      await toWeek;

      expect(cubit.state.chartRange, KpiRange.last24h);
      expect(cubit.state.series, day.series);
      expect(cubit.state.chartLoading, isFalse);
      await cubit.close();
    });

    test('a 7d error that lands after switching back to 24h is not shown on the 24h chart', () async {
      final pending = Completer<Kpis>();
      when(() => repository.fetchKpis(KpiRange.last7d)).thenAnswer((_) => pending.future);
      final cubit = DashboardCubit(repository);
      await cubit.load();

      final toWeek = cubit.selectRange(KpiRange.last7d);
      await cubit.selectRange(KpiRange.last24h);
      pending.completeError(_failure);
      await toWeek;

      expect(cubit.state.chartError, isNull);
      expect(cubit.state.chartLoading, isFalse);
      expect(cubit.state.series, day.series);
      await cubit.close();
    });

    test('retryChart refetches the selected range after an error', () async {
      var calls = 0;
      when(() => repository.fetchKpis(KpiRange.last7d)).thenAnswer((_) async {
        if (calls++ == 0) throw _failure;
        return week;
      });
      final cubit = DashboardCubit(repository);
      await cubit.load();
      await cubit.selectRange(KpiRange.last7d);
      expect(cubit.state.chartError, 'Server error.');

      await cubit.retryChart();

      expect(cubit.state.chartError, isNull);
      expect(cubit.state.series, week.series);
      verify(() => repository.fetchKpis(KpiRange.last7d)).called(2);
      await cubit.close();
    });
  });

  group('DashboardPage', () {
    late StreamController<Kpis> ticks;
    late _MockLiveStatusCubit liveStatus;

    setUp(() {
      ticks = StreamController<Kpis>.broadcast();
      when(() => repository.watchKpis()).thenAnswer((_) => ticks.stream);
      liveStatus = _MockLiveStatusCubit();
    });

    tearDown(() => ticks.close());

    Future<void> pump(WidgetTester tester, {required Stream<LiveStatusState> status, required LiveStatusState initial}) {
      whenListen(liveStatus, status, initialState: initial);
      final connectivity = _MockConnectivityCubit();
      when(() => connectivity.state).thenReturn(const ConnectivityState());
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [RepositoryProvider<DashboardRepository>.value(value: repository)],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConnectivityCubit>.value(value: connectivity),
              BlocProvider<LiveStatusCubit>.value(value: liveStatus),
            ],
            child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: DashboardPage())),
          ),
        ),
      );
    }

    testWidgets('the stamp says Live only while the SSE connection is open', (tester) async {
      const open = LiveStatusState(events: RealtimeStatus(RealtimePhase.open));
      final status = StreamController<LiveStatusState>();
      addTearDown(status.close);
      await pump(tester, status: status.stream, initial: open);
      await tester.pumpAndSettle();
      expect(find.textContaining('Snapshot from'), findsOneWidget);

      ticks.add(day);
      await tester.pumpAndSettle();
      expect(find.textContaining('Live · updated'), findsOneWidget);

      status.add(const LiveStatusState(events: RealtimeStatus(RealtimePhase.reconnecting, attempt: 1)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Snapshot from'), findsOneWidget);
      expect(find.textContaining('Live · updated'), findsNothing);
    });

    testWidgets('a failed refresh with tiles on screen shows a notice with retry', (tester) async {
      await pump(tester, status: const Stream.empty(), initial: const LiveStatusState());
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);

      when(() => repository.fetchKpis(KpiRange.last24h)).thenAnswer((_) async => throw _failure);
      final cubit = BlocProvider.of<DashboardCubit>(tester.element(find.text('Dashboard')));
      await cubit.load();
      await tester.pumpAndSettle();

      expect(find.textContaining('Refresh failed: Server error.'), findsOneWidget);
      expect(find.text('Active trips'), findsOneWidget);

      when(() => repository.fetchKpis(KpiRange.last24h)).thenAnswer((_) async => day);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refresh failed'), findsNothing);
    });
  });
}
