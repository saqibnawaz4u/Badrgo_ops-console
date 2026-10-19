import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../realtime/backoff.dart';
import '../domain/health_repository.dart';
import '../domain/maintenance_info.dart';

enum ConnectivityPhase {
  online,

  /// The API answered 503 MAINTENANCE.
  maintenance,

  /// No answer at all (offline, DNS, server restarting without a response).
  unreachable,
}

class ConnectivityState extends Equatable {
  const ConnectivityState({
    this.phase = ConnectivityPhase.online,
    this.info,
    this.since,
    this.nextCheckAt,
    this.checking = false,
    this.recoveries = 0,
  });

  final ConnectivityPhase phase;
  final MaintenanceInfo? info;

  /// When the outage started (server `since`, else when we noticed).
  final DateTime? since;
  final DateTime? nextCheckAt;
  final bool checking;

  /// Incremented each time we come back online. Pages listen for a change
  /// to refresh their data.
  final int recoveries;

  bool get isOnline => phase == ConnectivityPhase.online;

  ConnectivityState copyWith({
    ConnectivityPhase? phase,
    MaintenanceInfo? info,
    DateTime? since,
    DateTime? nextCheckAt,
    bool? checking,
    int? recoveries,
  }) =>
      ConnectivityState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        since: since ?? this.since,
        nextCheckAt: nextCheckAt ?? this.nextCheckAt,
        checking: checking ?? this.checking,
        recoveries: recoveries ?? this.recoveries,
      );

  @override
  List<Object?> get props => [phase, info, since, nextCheckAt, checking, recoveries];
}

/// Owns the maintenance / unreachable state and polls `/api/health` with
/// backoff until the API is back. Never signs the user out.
class ConnectivityCubit extends Cubit<ConnectivityState> {
  ConnectivityCubit(this._health) : super(const ConnectivityState());

  final HealthRepository _health;
  Timer? _timer;
  Backoff? _backoff;
  bool _probing = false;

  void reportMaintenance(MaintenanceInfo info) {
    final entering = state.phase != ConnectivityPhase.maintenance;
    emit(ConnectivityState(
      phase: ConnectivityPhase.maintenance,
      info: info,
      since: info.since ?? (entering ? DateTime.now() : state.since),
      nextCheckAt: state.nextCheckAt,
      recoveries: state.recoveries,
    ));
    if (entering) _startPolling(info.retryAfter);
  }

  /// A request failed without a response. Could be a blip, so check health
  /// once before showing anything.
  Future<void> reportNetworkFailure() async {
    if (!state.isOnline || _probing) return;
    _probing = true;
    final result = await _health.check();
    _probing = false;
    if (isClosed || !state.isOnline) return;
    switch (result) {
      case HealthUp():
        return;
      case HealthMaintenance(:final info):
        reportMaintenance(info);
      case HealthUnreachable():
        emit(ConnectivityState(
          phase: ConnectivityPhase.unreachable,
          since: DateTime.now(),
          recoveries: state.recoveries,
        ));
        _startPolling(null);
    }
  }

  Future<void> checkNow() async {
    _timer?.cancel();
    _backoff?.reset();
    await _check();
  }

  void _startPolling(Duration? retryAfter) {
    _timer?.cancel();
    _backoff = _backoffFrom(retryAfter);
    _schedule();
  }

  /// The server's Retry-After (clamped to 2–15 s) sets the next delay; the
  /// backoff grows from there.
  static Backoff _backoffFrom(Duration? retryAfter) {
    final first = retryAfter == null
        ? const Duration(seconds: 2)
        : Duration(seconds: retryAfter.inSeconds.clamp(2, 15));
    return Backoff(initial: first, max: const Duration(seconds: 30), factor: 1.6);
  }

  void _schedule() {
    final delay = _backoff!.next();
    emit(state.copyWith(nextCheckAt: DateTime.now().add(delay), checking: false));
    _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (isClosed || state.isOnline) return;
    emit(state.copyWith(checking: true));
    final result = await _health.check();
    if (isClosed || state.isOnline) return;
    switch (result) {
      case HealthUp():
        _timer?.cancel();
        emit(ConnectivityState(recoveries: state.recoveries + 1));
      case HealthMaintenance(:final info):
        emit(state.copyWith(
          phase: ConnectivityPhase.maintenance,
          info: info,
          since: info.since,
          checking: false,
        ));
        // A fresh Retry-After replaces the current backoff curve.
        if (info.retryAfter != null) _backoff = _backoffFrom(info.retryAfter);
        _schedule();
      case HealthUnreachable():
        emit(state.copyWith(checking: false));
        _schedule();
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
