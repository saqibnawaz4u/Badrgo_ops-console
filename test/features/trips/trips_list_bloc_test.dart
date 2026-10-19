import 'dart:async';

import 'package:badrgo_ops_console/core/error/api_exception.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip_filter.dart';
import 'package:badrgo_ops_console/features/trips/domain/repositories/trips_repository.dart';
import 'package:badrgo_ops_console/features/trips/domain/usecases/trip_list_merger.dart';
import 'package:badrgo_ops_console/features/trips/presentation/bloc/trips_list_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/trips.dart';

class _MockTripsRepository extends Mock implements TripsRepository {}

void main() {
  DateTime at(int hour) => DateTime.utc(2026, 10, 19, hour);
  List<String> ids(List<Trip> trips) => trips.map((t) => t.id).toList();
  TripPage pageOf(List<Trip> trips) => TripPage(trips: trips, endCursor: null, hasNextPage: false, totalCount: trips.length);

  late _MockTripsRepository repo;
  late StreamController<TripChange> changes;

  setUpAll(() => registerFallbackValue(const TripFilter()));

  setUp(() {
    repo = _MockTripsRepository();
    changes = StreamController<TripChange>.broadcast();
    when(() => repo.watchChanges()).thenAnswer((_) => changes.stream);
  });

  tearDown(() => changes.close());

  void stubFetch(Future<TripPage> Function(TripFilter filter) answer) {
    when(() => repo.fetchTrips(
          filter: any(named: 'filter'),
          after: any(named: 'after'),
          first: any(named: 'first'),
        )).thenAnswer((inv) => answer(inv.namedArguments[#filter] as TripFilter));
  }

  TripsListBloc build() => TripsListBloc(
        repo,
        hydrateDelay: const Duration(milliseconds: 5),
        hydrateRetryDelay: const Duration(milliseconds: 20),
        searchDelay: const Duration(milliseconds: 30),
      );

  group('live changes during a load', () {
    final page = Completer<TripPage>();

    blocTest<TripsListBloc, TripsListState>(
      'are buffered and applied once the page arrives',
      setUp: () => stubFetch((_) => page.future),
      build: build,
      act: (bloc) async {
        bloc.add(const TripsStarted());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.status, ListStatus.loading);
        changes.add(TripChange(isNew: true, change: 'created', trip: tripWith(id: 'trp_new', requestedAt: at(13))));
        await Future<void>.delayed(Duration.zero);
        page.complete(pageOf([tripWith(id: 'trp_old', requestedAt: at(12))]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(ids(bloc.state.items), ['trp_new', 'trp_old']);
        expect(bloc.state.totalCount, 2);
        expect(bloc.state.marks['trp_new']?.kind, RowMark.created);
      },
    );
  });

  blocTest<TripsListBloc, TripsListState>(
    'a row that stops matching the filter is removed, uncounted and unmarked',
    setUp: () => stubFetch((_) async => pageOf([tripWith(id: 'trp_a', requestedAt: at(12))])),
    build: build,
    seed: () => const TripsListState(filter: TripFilter(statuses: {TripStatus.requested})),
    act: (bloc) async {
      bloc.add(const TripsStarted());
      await Future<void>.delayed(Duration.zero);
      // First a change that keeps it in the list, so it carries a mark.
      changes.add(TripChange(isNew: false, change: 'updated', trip: tripWith(id: 'trp_a', requestedAt: at(12))));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.marks.keys, ['trp_a']);
      changes.add(TripChange(
        isNew: false,
        change: 'assigned',
        trip: tripWith(id: 'trp_a', status: TripStatus.assigned, driverId: 'drv_1', requestedAt: at(12)),
      ));
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.totalCount, 0);
      expect(bloc.state.marks, isEmpty);
    },
  );

  blocTest<TripsListBloc, TripsListState>(
    '"Clear all" cancels a search still waiting on its debounce',
    setUp: () => stubFetch((_) async => pageOf(const [])),
    build: build,
    act: (bloc) async {
      bloc.add(const TripsStarted());
      bloc.add(const TripsFilterChanged(TripFilter(statuses: {TripStatus.requested})));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const TripsSearchChanged('stale'));
      bloc.add(const TripsFilterChanged(TripFilter()));
    },
    wait: const Duration(milliseconds: 80),
    verify: (bloc) {
      expect(bloc.state.filter, const TripFilter());
      verifyNever(() => repo.fetchTrips(
            filter: any(named: 'filter', that: predicate<TripFilter>((f) => f.search == 'stale')),
            after: any(named: 'after'),
            first: any(named: 'first'),
          ));
    },
  );

  group('name hydration', () {
    const filter = TripFilter(search: 'rider one');
    final bare = tripWith(id: 'trp_new', requestedAt: at(13), withRiderName: false);
    var calls = 0;

    blocTest<TripsListBloc, TripsListState>(
      'is retried once, so a new trip awaiting a name match is not lost',
      setUp: () {
        calls = 0;
        stubFetch((_) async => pageOf(const []));
        when(() => repo.fetchTripsByIds(any())).thenAnswer((_) async {
          if (calls++ == 0) throw const ApiException(ApiErrorCode.network, 'offline');
          return [tripWith(id: 'trp_new', requestedAt: at(13))];
        });
      },
      build: build,
      seed: () => const TripsListState(filter: filter),
      act: (bloc) async {
        bloc.add(const TripsStarted());
        await Future<void>.delayed(Duration.zero);
        changes.add(TripChange(isNew: true, change: 'created', trip: bare));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(calls, 2);
        expect(ids(bloc.state.items), ['trp_new']);
        expect(bloc.state.totalCount, 1);
      },
    );

    blocTest<TripsListBloc, TripsListState>(
      'an unexpected error is ignored and not retried',
      setUp: () {
        calls = 0;
        stubFetch((_) async => pageOf(const []));
        when(() => repo.fetchTripsByIds(any())).thenAnswer((_) async {
          calls++;
          throw TypeError();
        });
      },
      build: build,
      seed: () => const TripsListState(filter: filter),
      act: (bloc) async {
        bloc.add(const TripsStarted());
        await Future<void>.delayed(Duration.zero);
        changes.add(TripChange(isNew: true, change: 'created', trip: bare));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(calls, 1);
        expect(bloc.state.status, ListStatus.ready);
        expect(bloc.state.items, isEmpty);
      },
    );
  });
}
