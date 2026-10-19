import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../domain/entities/trip.dart';
import '../../domain/entities/trip_filter.dart';
import '../../domain/repositories/trips_repository.dart';
import '../../domain/usecases/trip_list_merger.dart';

part 'trips_list_event.dart';
part 'trips_list_state.dart';

class TripsListBloc extends Bloc<TripsListEvent, TripsListState> {
  TripsListBloc(
    this._repository, {
    this.pageSize = 25,
    this.markDuration = const Duration(seconds: 8),
    this.hydrateDelay = const Duration(milliseconds: 400),
    this.searchDelay = const Duration(milliseconds: 350),
    this.hydrateRetryDelay = const Duration(seconds: 2),
  }) : super(const TripsListState()) {
    on<TripsStarted>(_onStarted);
    on<TripsFilterChanged>(_onFilterChanged);
    on<TripsSearchChanged>(_onSearchChanged);
    on<TripsLoadMoreRequested>(_onLoadMore);
    on<TripsRefreshRequested>((event, emit) => _reload(emit));
    on<_TripChanged>(_onTripChanged);
    on<_TripsHydrated>(_onHydrated);
    on<_MarksSwept>(_onMarksSwept);
  }

  final TripsRepository _repository;
  final int pageSize;
  final Duration markDuration;
  final Duration hydrateDelay;
  final Duration searchDelay;
  final Duration hydrateRetryDelay;

  StreamSubscription<TripChange>? _changes;
  Timer? _searchTimer;
  Timer? _hydrateTimer;
  Timer? _sweepTimer;
  final _retryTimers = <Timer>{};
  final _toHydrate = <String>{};
  final _awaitingMatch = <String>{};

  /// Live changes that arrived while a page was loading; applied once it lands.
  final _pendingChanges = <TripChange>[];

  /// Bumped on every reload so a slow, stale page cannot overwrite a newer one.
  int _loadGeneration = 0;

  Future<void> _onStarted(TripsStarted event, Emitter<TripsListState> emit) async {
    _changes ??= _repository.watchChanges().listen((c) => add(_TripChanged(c)));
    await _reload(emit);
  }

  Future<void> _onFilterChanged(TripsFilterChanged event, Emitter<TripsListState> emit) async {
    // A search still waiting on its debounce must not re-apply over "Clear
    // all" or a newer filter.
    _searchTimer?.cancel();
    _searchTimer = null;
    if (event.filter == state.filter) return;
    emit(state.copyWith(filter: event.filter));
    await _reload(emit);
  }

  void _onSearchChanged(TripsSearchChanged event, Emitter<TripsListState> emit) {
    _searchTimer?.cancel();
    _searchTimer = Timer(searchDelay, () {
      if (!isClosed) add(TripsFilterChanged(state.filter.copyWith(search: event.query)));
    });
  }

  Future<void> _reload(Emitter<TripsListState> emit) async {
    final generation = ++_loadGeneration;
    _toHydrate.clear();
    _awaitingMatch.clear();
    _cancelHydrationRetries();
    // Changes buffered for an older load came before this fetch; it has them.
    _pendingChanges.clear();
    emit(state.copyWith(status: ListStatus.loading, error: () => null, loadMoreError: () => null));
    try {
      final page = await _repository.fetchTrips(filter: state.filter, first: pageSize);
      if (generation != _loadGeneration) return;
      emit(state.copyWith(
        status: ListStatus.ready,
        items: page.trips,
        endCursor: () => page.endCursor,
        hasNextPage: page.hasNextPage,
        totalCount: page.totalCount,
        marks: const {},
      ));
      // The page may have been read before these happened. Re-applying one it
      // already has is harmless: the row is merged in place, not added twice.
      final pending = [..._pendingChanges];
      _pendingChanges.clear();
      for (final change in pending) {
        _applyChange(change, emit);
      }
    } on ApiException catch (e) {
      if (generation != _loadGeneration) return;
      _pendingChanges.clear();
      emit(state.copyWith(status: ListStatus.failure, error: () => e.message));
    }
  }

  Future<void> _onLoadMore(TripsLoadMoreRequested event, Emitter<TripsListState> emit) async {
    if (state.status != ListStatus.ready || state.loadingMore || !state.hasNextPage) return;
    final generation = _loadGeneration;
    emit(state.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final page = await _repository.fetchTrips(
        filter: state.filter,
        after: state.endCursor,
        first: pageSize,
      );
      if (generation != _loadGeneration) return;
      emit(state.copyWith(
        items: TripListMerger.appendPage(state.items, page.trips),
        endCursor: () => page.endCursor,
        hasNextPage: page.hasNextPage,
        loadingMore: false,
      ));
    } on ApiException catch (e) {
      if (generation != _loadGeneration) return;
      emit(state.copyWith(loadingMore: false, loadMoreError: () => e.message));
    }
  }

  void _onTripChanged(_TripChanged event, Emitter<TripsListState> emit) {
    // A (re)load in flight may have read the server before this change.
    if (state.status == ListStatus.loading) {
      _pendingChanges.add(event.change);
      return;
    }
    if (state.status != ListStatus.ready) return;
    _applyChange(event.change, emit);
  }

  void _applyChange(TripChange change, Emitter<TripsListState> emit) {
    final update = TripListMerger.applyChange(
      items: state.items,
      change: change,
      filter: state.filter,
    );
    _emitUpdate(update, emit);
    _awaitingMatch.addAll(update.awaitingMatch);
    _queueHydration(update.toHydrate);
  }

  void _onHydrated(_TripsHydrated event, Emitter<TripsListState> emit) {
    if (event.generation != _loadGeneration || state.status != ListStatus.ready) return;
    final update = TripListMerger.applyHydrated(
      items: state.items,
      hydrated: event.trips,
      awaitingMatch: event.awaitingMatch,
      filter: state.filter,
    );
    _emitUpdate(update, emit);
  }

  void _emitUpdate(TripListUpdate update, Emitter<TripsListState> emit) {
    final now = DateTime.now();
    final marks = {
      ...state.marks,
      for (final e in update.marks.entries)
        // A brand-new row stays "new" even if it changes again right away.
        e.key: state.marks[e.key]?.kind == RowMark.created
            ? RowMarkInfo(RowMark.created, now)
            : RowMarkInfo(e.value, now),
    }..removeWhere((id, _) => update.removed.contains(id));
    final total = state.totalCount + update.totalDelta;
    emit(state.copyWith(
      items: update.items,
      totalCount: total < 0 ? 0 : total,
      marks: marks,
    ));
    if (marks.isNotEmpty) _ensureSweeper();
  }

  /// Batches name lookups: several SSE frames in quick succession become a
  /// single aliased GraphQL request.
  void _queueHydration(List<String> ids) {
    if (ids.isEmpty) return;
    _toHydrate.addAll(ids);
    _hydrateTimer ??= Timer(hydrateDelay, _hydrate);
  }

  Future<void> _hydrate() async {
    _hydrateTimer = null;
    final generation = _loadGeneration;
    final ids = _toHydrate.take(20).toList();
    _toHydrate.removeAll(ids);
    final awaiting = _awaitingMatch.intersection(ids.toSet());
    _awaitingMatch.removeAll(awaiting);
    await _fetchNames(ids, awaiting, generation, canRetry: true);
    if (_toHydrate.isNotEmpty && !isClosed) _hydrateTimer ??= Timer(hydrateDelay, _hydrate);
  }

  Future<void> _fetchNames(List<String> ids, Set<String> awaiting, int generation, {required bool canRetry}) async {
    try {
      final trips = await _repository.fetchTripsByIds(ids);
      if (!isClosed) add(_TripsHydrated(trips, awaiting, generation));
    } on ApiException {
      // Try the same batch once more, so new trips waiting on a name match
      // are not lost to a blip. After that, rows already in the list keep
      // showing ids (the next reload fixes it) and unplaced new trips drop.
      if (!canRetry || isClosed || generation != _loadGeneration) return;
      late final Timer timer;
      timer = Timer(hydrateRetryDelay, () {
        _retryTimers.remove(timer);
        if (!isClosed && generation == _loadGeneration) _fetchNames(ids, awaiting, generation, canRetry: false);
      });
      _retryTimers.add(timer);
    } on Object {
      // Unexpected payload (e.g. bad JSON): a retry would fail the same way,
      // so rows simply keep showing ids.
    }
  }

  void _cancelHydrationRetries() {
    for (final timer in _retryTimers) {
      timer.cancel();
    }
    _retryTimers.clear();
  }

  void _ensureSweeper() {
    _sweepTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) add(const _MarksSwept());
    });
  }

  void _onMarksSwept(_MarksSwept event, Emitter<TripsListState> emit) {
    final cutoff = DateTime.now().subtract(markDuration);
    final marks = {
      for (final e in state.marks.entries)
        if (e.value.at.isAfter(cutoff)) e.key: e.value,
    };
    if (marks.length != state.marks.length) emit(state.copyWith(marks: marks));
    if (marks.isEmpty) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
  }

  @override
  Future<void> close() async {
    _searchTimer?.cancel();
    _hydrateTimer?.cancel();
    _sweepTimer?.cancel();
    _cancelHydrationRetries();
    await _changes?.cancel();
    return super.close();
  }
}
