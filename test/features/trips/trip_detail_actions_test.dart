import 'package:badrgo_ops_console/core/connectivity/presentation/connectivity_cubit.dart';
import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';
import 'package:badrgo_ops_console/features/trips/domain/repositories/trips_repository.dart';
import 'package:badrgo_ops_console/features/trips/presentation/trip_detail_page.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/roles.dart';
import '../../fixtures/trips.dart';

class _MockTripsRepository extends Mock implements TripsRepository {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _MockConnectivityCubit extends MockCubit<ConnectivityState> implements ConnectivityCubit {}

void main() {
  late _MockTripsRepository trips;

  setUp(() {
    trips = _MockTripsRepository();
    when(() => trips.watchChanges()).thenAnswer((_) => const Stream.empty());
  });

  /// Renders the real trip detail page for [role], with [trip] served by
  /// the repository.
  Future<void> pumpDetail(WidgetTester tester, {required String role, required Trip trip}) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    when(() => trips.fetchTrip(trip.id)).thenAnswer((_) async => trip);
    final auth = _MockAuthBloc();
    when(() => auth.state).thenReturn(AuthState.authenticated(userFor(role), 'token'));
    final connectivity = _MockConnectivityCubit();
    when(() => connectivity.state).thenReturn(const ConnectivityState());

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider<TripsRepository>.value(value: trips)],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<ConnectivityCubit>.value(value: connectivity),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: TripDetailPage(tripId: trip.id))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('waiting trip', () {
    final waiting = tripWith(status: TripStatus.requested);

    testWidgets('dispatcher sees Assign driver and Cancel trip', (tester) async {
      await pumpDetail(tester, role: 'dispatcher', trip: waiting);

      expect(find.text('Assign driver'), findsOneWidget);
      expect(find.text('Cancel trip'), findsOneWidget);
      expect(find.text('Refund'), findsNothing);
    });

    testWidgets('support is not offered Assign driver', (tester) async {
      await pumpDetail(tester, role: 'support', trip: waiting);

      expect(find.text('Rider One'), findsOneWidget, reason: 'the trip itself is shown');
      expect(find.text('Assign driver'), findsNothing);
      expect(find.text('Cancel trip'), findsNothing);
    });

    testWidgets('viewer sees the trip but no action buttons at all', (tester) async {
      await pumpDetail(tester, role: 'viewer', trip: waiting);

      expect(find.text('Rider One'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('completed trip', () {
    final completed = tripWith(status: TripStatus.completed, fare: 30, refunded: 5);

    testWidgets('support sees Refund', (tester) async {
      await pumpDetail(tester, role: 'support', trip: completed);

      expect(find.text('Refund'), findsOneWidget);
    });

    testWidgets('dispatcher does not see Refund', (tester) async {
      await pumpDetail(tester, role: 'dispatcher', trip: completed);

      expect(find.text('Refund'), findsNothing);
      expect(find.text('Cancel trip'), findsNothing, reason: 'a completed trip cannot be cancelled');
    });
  });

  testWidgets('a trip from another city shows "not found", not a crash', (tester) async {
    when(() => trips.fetchTrip('trp_other_city')).thenAnswer((_) async => null);
    final auth = _MockAuthBloc();
    when(() => auth.state).thenReturn(AuthState.authenticated(userFor('dispatcher'), 'token'));
    final connectivity = _MockConnectivityCubit();
    when(() => connectivity.state).thenReturn(const ConnectivityState());

    await tester.pumpWidget(
      RepositoryProvider<TripsRepository>.value(
        value: trips,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<ConnectivityCubit>.value(value: connectivity),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: TripDetailPage(tripId: 'trp_other_city'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip not found'), findsOneWidget);
  });
}
