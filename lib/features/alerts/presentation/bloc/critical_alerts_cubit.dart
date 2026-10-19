import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/permissions/permissions.dart';
import '../../domain/entities/alert.dart';
import '../../domain/repositories/alerts_repository.dart';

class CriticalAlertsState extends Equatable {
  const CriticalAlertsState({
    this.open = const [],
    this.hidden = const {},
    this.canAcknowledge = false,
    this.lastArrivalAt,
    this.message,
  });

  /// Unacknowledged critical alerts, newest first.
  final List<Alert> open;

  /// Ids the user hid from the banner (still open, still in the feed).
  final Set<String> hidden;
  final bool canAcknowledge;

  /// When the newest one arrived live: drives the attention animation.
  final DateTime? lastArrivalAt;
  final String? message;

  List<Alert> get visible => [for (final a in open) if (!hidden.contains(a.id)) a];

  CriticalAlertsState copyWith({
    List<Alert>? open,
    Set<String>? hidden,
    bool? canAcknowledge,
    DateTime? lastArrivalAt,
    String? Function()? message,
  }) =>
      CriticalAlertsState(
        open: open ?? this.open,
        hidden: hidden ?? this.hidden,
        canAcknowledge: canAcknowledge ?? this.canAcknowledge,
        lastArrivalAt: lastArrivalAt ?? this.lastArrivalAt,
        message: message != null ? message() : this.message,
      );

  @override
  List<Object?> get props => [open, hidden, canAcknowledge, lastArrivalAt, message];
}

/// App-wide watcher for critical (SOS) alerts. Lives in the signed-in
/// shell, so the banner shows on every page and is torn down on sign-out.
class CriticalAlertsCubit extends Cubit<CriticalAlertsState> {
  CriticalAlertsCubit(this._repository, {required Permissions permissions})
      : super(CriticalAlertsState(canAcknowledge: permissions.can(Permission.alertAcknowledge)));

  final AlertsRepository _repository;
  StreamSubscription<AlertChange>? _live;

  Future<void> start() async {
    _live ??= _repository.watchChanges().listen(_onLive);
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final page = await _repository.fetchAlerts(acknowledged: false, criticalOnly: true, first: 20);
      if (isClosed) return;
      emit(state.copyWith(open: page.alerts));
    } on ApiException {
      // Live frames still arrive; the banner fills in from those.
    }
  }

  void updatePermissions(Permissions permissions) =>
      emit(state.copyWith(canAcknowledge: permissions.can(Permission.alertAcknowledge)));

  void _onLive(AlertChange change) {
    final alert = change.alert;
    if (!alert.isCritical) return;
    final rest = [for (final a in state.open) if (a.id != alert.id) a];
    if (alert.isOpen) {
      emit(state.copyWith(open: [alert, ...rest], lastArrivalAt: change.isNew ? DateTime.now() : null));
    } else {
      emit(state.copyWith(open: rest));
    }
  }

  void hide(String id) => emit(state.copyWith(hidden: {...state.hidden, id}));

  Future<void> acknowledge(Alert alert) async {
    if (!state.canAcknowledge) return;
    try {
      await _repository.acknowledge(alert.id);
      if (isClosed) return;
      emit(state.copyWith(
        open: [for (final a in state.open) if (a.id != alert.id) a],
        message: () => 'SOS acknowledged.',
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      if (e.code == ApiErrorCode.invalidState || e.code == ApiErrorCode.conflict) {
        emit(state.copyWith(
          open: [for (final a in state.open) if (a.id != alert.id) a],
          message: () => 'Someone already acknowledged this SOS.',
        ));
      } else {
        emit(state.copyWith(message: () => e.message));
      }
    }
  }

  void clearMessage() => emit(state.copyWith(message: () => null));

  @override
  Future<void> close() async {
    await _live?.cancel();
    return super.close();
  }
}
