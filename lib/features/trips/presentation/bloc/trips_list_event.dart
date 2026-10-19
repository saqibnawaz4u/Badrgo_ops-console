part of 'trips_list_bloc.dart';

sealed class TripsListEvent {
  const TripsListEvent();
}

class TripsStarted extends TripsListEvent {
  const TripsStarted();
}

class TripsFilterChanged extends TripsListEvent {
  const TripsFilterChanged(this.filter);
  final TripFilter filter;
}

/// Raw text from the search box; debounced in the bloc.
class TripsSearchChanged extends TripsListEvent {
  const TripsSearchChanged(this.query);
  final String query;
}

class TripsLoadMoreRequested extends TripsListEvent {
  const TripsLoadMoreRequested();
}

class TripsRefreshRequested extends TripsListEvent {
  const TripsRefreshRequested();
}

class _TripChanged extends TripsListEvent {
  const _TripChanged(this.change);
  final TripChange change;
}

class _TripsHydrated extends TripsListEvent {
  const _TripsHydrated(this.trips, this.awaitingMatch, this.generation);
  final List<Trip> trips;
  final Set<String> awaitingMatch;
  final int generation;
}

class _MarksSwept extends TripsListEvent {
  const _MarksSwept();
}
