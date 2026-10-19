import 'dart:async';

import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';
import 'package:badrgo_ops_console/features/trips/domain/repositories/trips_repository.dart';
import 'package:badrgo_ops_console/features/trips/presentation/bloc/trip_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/roles.dart';
import '../../fixtures/trips.dart';

class _MockTripsRepository extends Mock implements TripsRepository {}

void main() {
  const driver = AssignableDriver(id: 'drv_1', name: 'Driver One');
  final trip = tripWith(status: TripStatus.requested);

  late _MockTripsRepository repo;
  late StreamController<TripChange> changes;
  late TripDetailCubit cubit;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 1));

  setUp(() async {
    repo = _MockTripsRepository();
    changes = StreamController<TripChange>.broadcast();
    when(() => repo.watchChanges()).thenAnswer((_) => changes.stream);
    when(() => repo.fetchTrip(trip.id)).thenAnswer((_) async => trip);
    when(() => repo.assignDriver(tripId: trip.id, driverId: driver.id)).thenAnswer((_) async {});
    cubit = TripDetailCubit(repo, tripId: trip.id, permissions: permissionsFor('dispatcher'));
    await cubit.start();
  });

  tearDown(() async {
    await cubit.close();
    await changes.close();
  });

  TripChange live(String change, TripStatus status) =>
      TripChange(isNew: false, change: change, trip: tripWith(status: status, driverId: driver.id));

  group('own-write echo', () {
    test('the echo of our own assign gets no "updated live" banner', () async {
      await cubit.assign(driver);
      changes.add(live('assigned', TripStatus.assigned));
      await settle();

      expect(cubit.state.banner, 'Assigned to Driver One.');
    });

    test('a different change inside the window still shows the banner', () async {
      await cubit.assign(driver);
      changes.add(live('cancelled', TripStatus.cancelled));
      await settle();

      expect(cubit.state.banner, startsWith('Updated live'));
    });

    test('only one echo is swallowed: a second "assigned" is someone else', () async {
      await cubit.assign(driver);
      changes.add(live('assigned', TripStatus.assigned));
      await settle();
      changes.add(live('assigned', TripStatus.assigned));
      await settle();

      expect(cubit.state.banner, startsWith('Updated live'));
    });
  });

  test('an unexpected error resets busy and returns a generic message', () async {
    when(() => repo.assignDriver(tripId: trip.id, driverId: driver.id)).thenAnswer((_) async => throw TypeError());

    final outcome = await cubit.assign(driver);

    expect(outcome.ok, isFalse);
    expect(outcome.message, 'Something went wrong. Please try again.');
    expect(cubit.state.busy, isFalse);
  });
}
