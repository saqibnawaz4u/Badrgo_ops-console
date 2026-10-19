import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip_filter.dart';
import 'package:badrgo_ops_console/features/trips/domain/usecases/trip_list_merger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/trips.dart';

void main() {
  DateTime at(int hour) => DateTime.utc(2026, 10, 19, hour);

  // Loaded list, newest first.
  final loaded = [
    tripWith(id: 'trp_c', requestedAt: at(12)),
    tripWith(id: 'trp_b', requestedAt: at(11)),
    tripWith(id: 'trp_a', requestedAt: at(10)),
  ];

  List<String> ids(List<Trip> trips) => trips.map((t) => t.id).toList();

  group('trip.created', () {
    test('inserts newest-first, counts it and marks it new', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(isNew: true, change: 'created', trip: tripWith(id: 'trp_new', requestedAt: at(13))),
        filter: const TripFilter(),
      );

      expect(ids(update.items), ['trp_new', 'trp_c', 'trp_b', 'trp_a']);
      expect(update.totalDelta, 1);
      expect(update.marks, {'trp_new': RowMark.created});
    });

    test('is dropped when it does not match the status filter', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(isNew: true, change: 'created', trip: tripWith(id: 'trp_new')),
        filter: const TripFilter(statuses: {TripStatus.completed}),
      );

      expect(update.items, same(loaded));
      expect(update.totalDelta, 0);
    });

    test('with a search on rider name, waits for names before deciding', () {
      final bare = tripWith(id: 'trp_new', requestedAt: at(13), withRiderName: false);
      const filter = TripFilter(search: 'rider one');

      final first = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(isNew: true, change: 'created', trip: bare),
        filter: filter,
      );
      expect(first.items, same(loaded), reason: 'not inserted yet');
      expect(first.awaitingMatch, ['trp_new']);
      expect(first.toHydrate, ['trp_new']);

      final second = TripListMerger.applyHydrated(
        items: loaded,
        hydrated: [tripWith(id: 'trp_new', requestedAt: at(13))],
        awaitingMatch: {'trp_new'},
        filter: filter,
      );
      expect(ids(second.items).first, 'trp_new');
      expect(second.marks, {'trp_new': RowMark.created});
    });
  });

  group('trip.updated', () {
    test('updates the row in place and marks it changed, without reordering', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(
          isNew: false,
          change: 'completed',
          trip: tripWith(id: 'trp_b', status: TripStatus.completed, requestedAt: at(11)),
        ),
        filter: const TripFilter(),
      );

      expect(ids(update.items), ids(loaded));
      expect(update.items[1].status, TripStatus.completed);
      expect(update.marks, {'trp_b': RowMark.updated});
      expect(update.totalDelta, 0);
    });

    test('keeps the rider name GraphQL loaded when the SSE payload has only ids', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(
          isNew: false,
          change: 'started',
          trip: tripWith(id: 'trp_c', status: TripStatus.inProgress, requestedAt: at(12), withRiderName: false),
        ),
        filter: const TripFilter(),
      );

      expect(update.items.first.rider?.name, 'Rider One');
    });

    test('a newly assigned driver is fetched, since SSE carries only the id', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(
          isNew: false,
          change: 'assigned',
          trip: tripWith(id: 'trp_a', status: TripStatus.assigned, driverId: 'drv_9', requestedAt: at(10)),
        ),
        filter: const TripFilter(),
      );

      expect(update.toHydrate, ['trp_a']);
    });

    test('a row that no longer matches the status filter is removed and uncounted', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(
          isNew: false,
          change: 'assigned',
          trip: tripWith(id: 'trp_b', status: TripStatus.assigned, driverId: 'drv_9', requestedAt: at(11)),
        ),
        filter: const TripFilter(statuses: {TripStatus.requested}),
      );

      expect(ids(update.items), ['trp_c', 'trp_a']);
      expect(update.totalDelta, -1);
      expect(update.removed, ['trp_b']);
      expect(update.marks, isEmpty);
      expect(update.toHydrate, isEmpty);
    });

    test('a row is kept while a search match cannot be decided yet', () {
      final bare = [tripWith(id: 'trp_b', requestedAt: at(11), withRiderName: false)];
      final update = TripListMerger.applyChange(
        items: bare,
        change: TripChange(
          isNew: false,
          change: 'started',
          trip: tripWith(id: 'trp_b', status: TripStatus.inProgress, requestedAt: at(11), withRiderName: false),
        ),
        filter: const TripFilter(search: 'rider one'),
      );

      expect(ids(update.items), ['trp_b']);
      expect(update.totalDelta, 0);
      expect(update.marks, {'trp_b': RowMark.updated});
    });

    test('updates for rows not on screen are ignored, so the list does not jump', () {
      final update = TripListMerger.applyChange(
        items: loaded,
        change: TripChange(isNew: false, change: 'completed', trip: tripWith(id: 'trp_elsewhere')),
        filter: const TripFilter(),
      );

      expect(update.items, same(loaded));
      expect(update.marks, isEmpty);
    });
  });

  test('appending the next page skips rows that live inserts already pushed down', () {
    final next = [tripWith(id: 'trp_a', requestedAt: at(10)), tripWith(id: 'trp_0', requestedAt: at(9))];

    expect(ids(TripListMerger.appendPage(loaded, next)), ['trp_c', 'trp_b', 'trp_a', 'trp_0']);
  });

  group('TripFilter date range', () {
    final filter = TripFilter(from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 19));

    test('"to" includes the whole last day', () {
      final lateThatDay = tripWith(requestedAt: DateTime(2026, 10, 19, 23, 59));
      expect(filter.matches(lateThatDay), FilterMatch.yes);
    });

    test('excludes trips outside the range', () {
      expect(filter.matches(tripWith(requestedAt: DateTime(2026, 10, 20, 0, 1))), FilterMatch.no);
      expect(filter.matches(tripWith(requestedAt: DateTime(2026, 10, 18, 23, 59))), FilterMatch.no);
    });
  });
}
