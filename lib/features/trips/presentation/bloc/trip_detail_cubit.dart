import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/permissions/permissions.dart';
import '../../domain/entities/trip.dart';
import '../../domain/repositories/trips_repository.dart';
import '../../domain/usecases/trip_rules.dart';

enum DetailStatus { loading, ready, notFound, failure }

/// Outcome of an action, returned to the dialog that started it.
class ActionOutcome extends Equatable {
  const ActionOutcome.success(this.message)
      : ok = true,
        conflict = false,
        fieldErrors = const {};
  const ActionOutcome.failure(this.message, {this.conflict = false, this.fieldErrors = const {}})
      : ok = false;

  final bool ok;
  final String message;

  /// 409 INVALID_STATE: the trip changed under us. The dialog closes and the
  /// page explains what happened.
  final bool conflict;
  final Map<String, String> fieldErrors;

  @override
  List<Object?> get props => [ok, message, conflict, fieldErrors];
}

class DriverOptions extends Equatable {
  const DriverOptions({this.loading = false, this.drivers = const [], this.error});

  final bool loading;
  final List<AssignableDriver> drivers;
  final String? error;

  @override
  List<Object?> get props => [loading, drivers, error];
}

class TripDetailState extends Equatable {
  const TripDetailState({
    this.status = DetailStatus.loading,
    this.trip,
    this.actions = TripActions.none,
    this.error,
    this.banner,
    this.bannerIsConflict = false,
    this.busy = false,
    this.driverOptions = const DriverOptions(),
  });

  final DetailStatus status;
  final Trip? trip;
  final TripActions actions;
  final String? error;

  /// Message about the last action or a live change.
  final String? banner;
  final bool bannerIsConflict;
  final bool busy;
  final DriverOptions driverOptions;

  TripDetailState copyWith({
    DetailStatus? status,
    Trip? trip,
    TripActions? actions,
    String? Function()? error,
    String? Function()? banner,
    bool? bannerIsConflict,
    bool? busy,
    DriverOptions? driverOptions,
  }) =>
      TripDetailState(
        status: status ?? this.status,
        trip: trip ?? this.trip,
        actions: actions ?? this.actions,
        error: error != null ? error() : this.error,
        banner: banner != null ? banner() : this.banner,
        bannerIsConflict: bannerIsConflict ?? this.bannerIsConflict,
        busy: busy ?? this.busy,
        driverOptions: driverOptions ?? this.driverOptions,
      );

  @override
  List<Object?> get props =>
      [status, trip, actions, error, banner, bannerIsConflict, busy, driverOptions];
}

class TripDetailCubit extends Cubit<TripDetailState> {
  TripDetailCubit(this._repository, {required this.tripId, required Permissions permissions})
      : _permissions = permissions,
        super(const TripDetailState());

  final TripsRepository _repository;
  final String tripId;
  Permissions _permissions;
  StreamSubscription<TripChange>? _changes;

  /// Our own writes echo back over SSE; we do not announce those as
  /// "updated live". Only the change our action causes is skipped, once,
  /// within [_echoWindow]: anything else (a colleague, the simulator) still
  /// gets a banner.
  ({Set<String> changes, DateTime at})? _expectedEcho;
  static const _echoWindow = Duration(seconds: 3);
  static const _unexpectedError = 'Something went wrong. Please try again.';

  Future<void> start() async {
    _changes ??= _repository
        .watchChanges()
        .where((c) => c.trip.id == tripId)
        .listen(_onLiveChange);
    await load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) emit(state.copyWith(status: DetailStatus.loading, error: () => null));
    try {
      final trip = await _repository.fetchTrip(tripId);
      if (isClosed) return;
      if (trip == null) {
        emit(state.copyWith(status: DetailStatus.notFound));
        return;
      }
      emit(state.copyWith(
        status: DetailStatus.ready,
        trip: trip,
        actions: TripActions.resolve(trip, _permissions),
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      if (e.code == ApiErrorCode.notFound) {
        emit(state.copyWith(status: DetailStatus.notFound));
      } else if (!quiet || state.trip == null) {
        emit(state.copyWith(status: DetailStatus.failure, error: () => e.message));
      }
    }
  }

  /// Permissions changed (role switched by an admin): re-evaluate buttons.
  void updatePermissions(Permissions permissions) {
    _permissions = permissions;
    final trip = state.trip;
    if (trip != null) emit(state.copyWith(actions: TripActions.resolve(trip, permissions)));
  }

  Future<void> _onLiveChange(TripChange change) async {
    final before = state.trip?.status;
    final expected = _expectedEcho;
    final ownEcho = expected != null &&
        expected.changes.contains(change.change) &&
        DateTime.now().difference(expected.at) < _echoWindow;
    if (ownEcho) _expectedEcho = null;
    await load(quiet: true);
    if (isClosed || state.trip == null) return;
    if (ownEcho) return;
    final after = state.trip!.status;
    emit(state.copyWith(
      banner: () => before != after
          ? 'Updated live: this trip is now ${after.label.toLowerCase()} (${change.change}).'
          : 'Updated live (${change.change}).',
      bannerIsConflict: false,
    ));
  }

  void dismissBanner() => emit(state.copyWith(banner: () => null));

  Future<void> loadDriverOptions() async {
    emit(state.copyWith(driverOptions: const DriverOptions(loading: true)));
    try {
      final trip = state.trip;
      final drivers = await _repository.fetchAvailableDrivers(cityId: trip?.cityId);
      if (isClosed) return;
      emit(state.copyWith(
        driverOptions: DriverOptions(drivers: rankByDistance(drivers, trip?.pickup.location)),
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(driverOptions: DriverOptions(error: e.message)));
    }
  }

  String? validateReason(String? value) => TripInputRules.reason(value);

  String? validateRefundAmount(String? value) {
    final trip = state.trip;
    return trip == null ? null : TripInputRules.refundAmount(value, trip.refundable);
  }

  Future<ActionOutcome> assign(AssignableDriver driver) => _run(
        () => _repository.assignDriver(tripId: tripId, driverId: driver.id),
        success: 'Assigned to ${driver.name}.',
        echoes: const {'assigned', 'reassigned'},
      );

  Future<ActionOutcome> cancel(String reason) => _run(
        () => _repository.cancelTrip(tripId: tripId, reason: reason),
        success: 'Trip cancelled.',
        echoes: const {'cancelled'},
      );

  Future<ActionOutcome> refund(String amountText, String reason) {
    final amountError = validateRefundAmount(amountText);
    final reasonError = validateReason(reason);
    if (amountError != null || reasonError != null) {
      return Future.value(ActionOutcome.failure('Please check the form.', fieldErrors: {
        'amount': ?amountError,
        'reason': ?reasonError,
      }));
    }
    final amount = double.parse(amountText.trim().replaceAll(',', '.'));
    final currency = state.trip?.fare.currency ?? '';
    return _run(
      () => _repository.refundTrip(tripId: tripId, amount: amount, reason: reason),
      success: 'Refunded ${amount.toStringAsFixed(2)} $currency.',
      echoes: const {'refunded'},
      // "Refund must be more than 0 and at most 12.40 QAR" has no field path.
      fallbackField: 'amount',
    );
  }

  /// [echoes]: the live `change` kinds this action produces.
  Future<ActionOutcome> _run(
    Future<void> Function() action, {
    required String success,
    required Set<String> echoes,
    String? fallbackField,
  }) async {
    if (state.busy) return const ActionOutcome.failure('Another action is still running.');
    emit(state.copyWith(busy: true, banner: () => null));
    // Set before the request: the echo can beat the REST response.
    _expectedEcho = (changes: echoes, at: DateTime.now());
    var written = false;
    try {
      await action();
      written = true;
      final expected = _expectedEcho;
      if (expected != null) _expectedEcho = (changes: expected.changes, at: DateTime.now());
      if (isClosed) return ActionOutcome.success(success);
      emit(state.copyWith(busy: false, banner: () => success, bannerIsConflict: false));
      await load(quiet: true);
      return ActionOutcome.success(success);
    } on ApiException catch (e) {
      _expectedEcho = null;
      if (isClosed) return ActionOutcome.failure(e.message);
      emit(state.copyWith(busy: false));
      switch (e.code) {
        case ApiErrorCode.validationFailed:
          final fieldErrors = e.fieldErrors.isEmpty && fallbackField != null
              ? {fallbackField: e.message}
              : e.fieldErrors;
          return ActionOutcome.failure(e.message, fieldErrors: fieldErrors);
        case ApiErrorCode.invalidState || ApiErrorCode.conflict:
          // The simulator (or a colleague) got there first. Explain and show
          // the trip as it is now.
          emit(state.copyWith(
            banner: () => '${e.message} The trip has been refreshed to show its current state.',
            bannerIsConflict: true,
          ));
          await load(quiet: true);
          return ActionOutcome.failure(e.message, conflict: true);
        case ApiErrorCode.notFound:
          emit(state.copyWith(status: DetailStatus.notFound));
          return ActionOutcome.failure(e.message, conflict: true);
        default:
          return ActionOutcome.failure(e.message);
      }
    } on Object {
      // Anything else (e.g. an unexpected response shape) must not leave the
      // buttons disabled. If the write itself went through, say so.
      if (!written) _expectedEcho = null;
      if (!isClosed) emit(state.copyWith(busy: false));
      return written ? ActionOutcome.success(success) : const ActionOutcome.failure(_unexpectedError);
    }
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
