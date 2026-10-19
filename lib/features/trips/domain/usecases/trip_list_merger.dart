import '../entities/trip.dart';
import '../entities/trip_filter.dart';

enum RowMark { created, updated }

class TripListUpdate {
  const TripListUpdate({
    required this.items,
    this.totalDelta = 0,
    this.marks = const {},
    this.toHydrate = const [],
    this.awaitingMatch = const [],
    this.removed = const [],
  });

  final List<Trip> items;
  final int totalDelta;

  /// Rows to highlight.
  final Map<String, RowMark> marks;

  /// Ids whose rider/driver names should be fetched with GraphQL.
  final List<String> toHydrate;

  /// New trips we could not place yet (search on rider name): decide after
  /// hydration.
  final List<String> awaitingMatch;

  /// Rows taken out because they no longer match the filter.
  final List<String> removed;
}

/// Applies live SSE changes to a loaded, filtered, newest-first list
/// without reloading it. Pure functions, so they are easy to test.
class TripListMerger {
  const TripListMerger._();

  static TripListUpdate applyChange({
    required List<Trip> items,
    required TripChange change,
    required TripFilter filter,
  }) {
    final index = items.indexWhere((t) => t.id == change.trip.id);
    if (index >= 0) {
      final merged = items[index].mergeLive(change.trip);
      // A "Requested" list should not keep a trip that was just assigned.
      // `unknown` (search on a name we lack) keeps the row as it is.
      if (filter.matches(merged) == FilterMatch.no) {
        return TripListUpdate(items: [...items]..removeAt(index), totalDelta: -1, removed: [merged.id]);
      }
      return TripListUpdate(
        items: [...items]..[index] = merged,
        marks: {merged.id: RowMark.updated},
        toHydrate: merged.needsHydration ? [merged.id] : const [],
      );
    }

    // Updates for rows we have not loaded are ignored: inserting them would
    // shuffle a list the user is reading.
    if (!change.isNew) return TripListUpdate(items: items);

    switch (filter.matches(change.trip)) {
      case FilterMatch.yes:
        return TripListUpdate(
          items: insertNewestFirst(items, change.trip),
          totalDelta: 1,
          marks: {change.trip.id: RowMark.created},
          toHydrate: change.trip.needsHydration ? [change.trip.id] : const [],
        );
      case FilterMatch.unknown:
        return TripListUpdate(
          items: items,
          toHydrate: [change.trip.id],
          awaitingMatch: [change.trip.id],
        );
      case FilterMatch.no:
        return TripListUpdate(items: items);
    }
  }

  /// Merges GraphQL results for rows that were missing names. New trips that
  /// were [awaitingMatch] are inserted only if they now match the filter.
  static TripListUpdate applyHydrated({
    required List<Trip> items,
    required List<Trip> hydrated,
    required Set<String> awaitingMatch,
    required TripFilter filter,
  }) {
    var result = [...items];
    var totalDelta = 0;
    final marks = <String, RowMark>{};
    for (final trip in hydrated) {
      final index = result.indexWhere((t) => t.id == trip.id);
      if (index >= 0) {
        result[index] = trip;
      } else if (awaitingMatch.contains(trip.id) && filter.matches(trip) == FilterMatch.yes) {
        result = insertNewestFirst(result, trip);
        totalDelta++;
        marks[trip.id] = RowMark.created;
      }
    }
    return TripListUpdate(items: result, totalDelta: totalDelta, marks: marks);
  }

  /// Appends a page, skipping rows we already have. Cursors are offsets, so
  /// live inserts shift later pages and would otherwise duplicate rows.
  static List<Trip> appendPage(List<Trip> items, List<Trip> page) {
    final known = {for (final t in items) t.id};
    return [...items, ...page.where((t) => !known.contains(t.id))];
  }

  static List<Trip> insertNewestFirst(List<Trip> items, Trip trip) {
    final at = items.indexWhere((t) => t.requestedAt.isBefore(trip.requestedAt));
    return [...items]..insert(at < 0 ? items.length : at, trip);
  }
}
