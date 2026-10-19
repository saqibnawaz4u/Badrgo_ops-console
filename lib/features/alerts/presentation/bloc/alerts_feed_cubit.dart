import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/permissions/permissions.dart';
import '../../domain/entities/alert.dart';
import '../../domain/repositories/alerts_repository.dart';

enum AlertsStatus { loading, ready, failure }

class AlertsFeedState extends Equatable {
  const AlertsFeedState({
    this.status = AlertsStatus.loading,
    this.openOnly = true,
    this.items = const [],
    this.endCursor,
    this.hasNextPage = false,
    this.totalCount = 0,
    this.loadingMore = false,
    this.error,
    this.canAcknowledge = false,
    this.acknowledging = const {},
    this.freshIds = const {},
    this.message,
  });

  final AlertsStatus status;
  final bool openOnly;
  final List<Alert> items;
  final String? endCursor;
  final bool hasNextPage;
  final int totalCount;
  final bool loadingMore;
  final String? error;
  final bool canAcknowledge;
  final Set<String> acknowledging;

  /// Alerts that arrived live since the page opened.
  final Set<String> freshIds;

  /// One-off feedback for a snackbar.
  final String? message;

  AlertsFeedState copyWith({
    AlertsStatus? status,
    bool? openOnly,
    List<Alert>? items,
    String? Function()? endCursor,
    bool? hasNextPage,
    int? totalCount,
    bool? loadingMore,
    String? Function()? error,
    bool? canAcknowledge,
    Set<String>? acknowledging,
    Set<String>? freshIds,
    String? Function()? message,
  }) =>
      AlertsFeedState(
        status: status ?? this.status,
        openOnly: openOnly ?? this.openOnly,
        items: items ?? this.items,
        endCursor: endCursor != null ? endCursor() : this.endCursor,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        totalCount: totalCount ?? this.totalCount,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error != null ? error() : this.error,
        canAcknowledge: canAcknowledge ?? this.canAcknowledge,
        acknowledging: acknowledging ?? this.acknowledging,
        freshIds: freshIds ?? this.freshIds,
        message: message != null ? message() : this.message,
      );

  @override
  List<Object?> get props => [
        status, openOnly, items, endCursor, hasNextPage, totalCount, loadingMore, error,
        canAcknowledge, acknowledging, freshIds, message,
      ];
}

class AlertsFeedCubit extends Cubit<AlertsFeedState> {
  AlertsFeedCubit(this._repository, {required Permissions permissions})
      : super(AlertsFeedState(canAcknowledge: permissions.can(Permission.alertAcknowledge)));

  final AlertsRepository _repository;
  StreamSubscription<AlertChange>? _live;
  int _generation = 0;

  Future<void> start() async {
    _live ??= _repository.watchChanges().listen(_onLive);
    await load();
  }

  void updatePermissions(Permissions permissions) =>
      emit(state.copyWith(canAcknowledge: permissions.can(Permission.alertAcknowledge)));

  Future<void> setOpenOnly(bool openOnly) async {
    if (openOnly == state.openOnly) return;
    emit(state.copyWith(openOnly: openOnly));
    await load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    emit(state.copyWith(status: AlertsStatus.loading, error: () => null));
    try {
      final page = await _repository.fetchAlerts(acknowledged: state.openOnly ? false : null);
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(
        status: AlertsStatus.ready,
        items: page.alerts,
        endCursor: () => page.endCursor,
        hasNextPage: page.hasNextPage,
        totalCount: page.totalCount,
      ));
    } on ApiException catch (e) {
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(status: AlertsStatus.failure, error: () => e.message));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasNextPage || state.status != AlertsStatus.ready) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.fetchAlerts(
        acknowledged: state.openOnly ? false : null,
        after: state.endCursor,
      );
      if (isClosed || generation != _generation) return;
      final known = {for (final a in state.items) a.id};
      emit(state.copyWith(
        items: [...state.items, ...page.alerts.where((a) => !known.contains(a.id))],
        endCursor: () => page.endCursor,
        hasNextPage: page.hasNextPage,
        loadingMore: false,
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadingMore: false, message: () => e.message));
    }
  }

  void _onLive(AlertChange change) {
    if (state.status != AlertsStatus.ready) return;
    final index = state.items.indexWhere((a) => a.id == change.alert.id);
    if (index >= 0) {
      final merged = state.items[index].mergeLive(change.alert);
      if (state.openOnly && !merged.isOpen) {
        // Acknowledged by someone (us or a colleague): it no longer belongs
        // under "Open". Our own pending acknowledge then finds no row, so the
        // count drops only once.
        emit(state.copyWith(
          items: [...state.items]..removeAt(index),
          totalCount: state.totalCount > 0 ? state.totalCount - 1 : 0,
        ));
        return;
      }
      emit(state.copyWith(items: [...state.items]..[index] = merged));
    } else if (change.isNew) {
      emit(state.copyWith(
        items: [change.alert, ...state.items],
        totalCount: state.totalCount + 1,
        freshIds: {...state.freshIds, change.alert.id},
      ));
    }
  }

  Future<void> acknowledge(Alert alert) async {
    if (!state.canAcknowledge || state.acknowledging.contains(alert.id)) return;
    emit(state.copyWith(acknowledging: {...state.acknowledging, alert.id}));
    try {
      await _repository.acknowledge(alert.id);
      if (isClosed) return;
      emit(_withAcknowledged(alert.id).copyWith(message: () => 'Alert acknowledged.'));
    } on ApiException catch (e) {
      if (isClosed) return;
      final text = e.code == ApiErrorCode.invalidState || e.code == ApiErrorCode.conflict
          ? 'Someone already acknowledged this alert.'
          : e.message;
      emit(state.copyWith(message: () => text));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(acknowledging: {...state.acknowledging}..remove(alert.id)));
      }
    }
  }

  /// Applies our own acknowledge without waiting for SSE. Under "Open" the
  /// row leaves the list; the later `alert.acknowledged` frame then finds
  /// nothing to update, so the count drops only once.
  AlertsFeedState _withAcknowledged(String id) {
    final index = state.items.indexWhere((a) => a.id == id);
    if (index < 0) return state;
    if (state.openOnly) {
      return state.copyWith(
        items: [...state.items]..removeAt(index),
        totalCount: state.totalCount > 0 ? state.totalCount - 1 : 0,
      );
    }
    return state.copyWith(items: [...state.items]..[index] = state.items[index].markAcknowledged(DateTime.now()));
  }

  void clearMessage() => emit(state.copyWith(message: () => null));

  @override
  Future<void> close() async {
    await _live?.cancel();
    return super.close();
  }
}
