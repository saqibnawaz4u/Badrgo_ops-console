import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/realtime/realtime_status.dart';
import '../../domain/entities/driver.dart';
import '../../domain/repositories/live_map_repository.dart';

class SelectedDriver extends Equatable {
  const SelectedDriver({required this.id, this.loading = false, this.details, this.error});

  final String id;
  final bool loading;
  final DriverDetails? details;
  final String? error;

  @override
  List<Object?> get props => [id, loading, details, error];
}

class LiveMapState extends Equatable {
  const LiveMapState({
    this.drivers = const [],
    this.receivedFirstSnapshot = false,
    this.lastSnapshotAt,
    this.connection = RealtimeStatus.idle,
    this.hiddenStatuses = const {},
    this.selected,
    this.canMessage = false,
  });

  final List<DriverLocation> drivers;
  final bool receivedFirstSnapshot;
  final DateTime? lastSnapshotAt;
  final RealtimeStatus connection;
  final Set<DriverStatus> hiddenStatuses;
  final SelectedDriver? selected;
  final bool canMessage;

  List<DriverLocation> get visibleDrivers =>
      [for (final d in drivers) if (!hiddenStatuses.contains(d.status)) d];

  Map<DriverStatus, int> get counts => {
        for (final s in DriverStatus.values) s: drivers.where((d) => d.status == s).length,
      };

  LiveMapState copyWith({
    List<DriverLocation>? drivers,
    bool? receivedFirstSnapshot,
    DateTime? lastSnapshotAt,
    RealtimeStatus? connection,
    Set<DriverStatus>? hiddenStatuses,
    SelectedDriver? Function()? selected,
    bool? canMessage,
  }) =>
      LiveMapState(
        drivers: drivers ?? this.drivers,
        receivedFirstSnapshot: receivedFirstSnapshot ?? this.receivedFirstSnapshot,
        lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
        connection: connection ?? this.connection,
        hiddenStatuses: hiddenStatuses ?? this.hiddenStatuses,
        selected: selected != null ? selected() : this.selected,
        canMessage: canMessage ?? this.canMessage,
      );

  @override
  List<Object?> get props =>
      [drivers, receivedFirstSnapshot, lastSnapshotAt, connection, hiddenStatuses, selected, canMessage];
}

class LiveMapCubit extends Cubit<LiveMapState> {
  LiveMapCubit(this._repository, {required Permissions permissions})
      : super(LiveMapState(
          connection: _repository.connectionStatus,
          canMessage: permissions.can(Permission.driverMessage),
        ));

  final LiveMapRepository _repository;
  StreamSubscription<List<DriverLocation>>? _locations;
  StreamSubscription<RealtimeStatus>? _status;

  void start() {
    _status ??= _repository.watchConnectionStatus().listen((s) => emit(state.copyWith(connection: s)));
    _locations ??= _repository.watchLocations().listen(_onSnapshot);
  }

  void updatePermissions(Permissions permissions) =>
      emit(state.copyWith(canMessage: permissions.can(Permission.driverMessage)));

  /// Each frame is a full snapshot: replace all markers.
  void _onSnapshot(List<DriverLocation> drivers) {
    final selected = state.selected;
    emit(state.copyWith(
      drivers: drivers,
      receivedFirstSnapshot: true,
      lastSnapshotAt: DateTime.now(),
    ));
    // Refresh the side panel when the selected driver changes status
    // (e.g. picks up a trip), so "current trip" stays right.
    if (selected?.details != null) {
      final live = drivers.where((d) => d.id == selected!.id).firstOrNull;
      if (live != null && live.status != selected!.details!.status) _loadDetails(selected.id);
    }
  }

  void toggleStatus(DriverStatus status) {
    final hidden = {...state.hiddenStatuses};
    hidden.contains(status) ? hidden.remove(status) : hidden.add(status);
    emit(state.copyWith(hiddenStatuses: hidden));
  }

  Future<void> select(String driverId) async {
    if (state.selected?.id == driverId) return;
    emit(state.copyWith(selected: () => SelectedDriver(id: driverId, loading: true)));
    await _loadDetails(driverId);
  }

  void clearSelection() => emit(state.copyWith(selected: () => null));

  Future<void> _loadDetails(String driverId) async {
    try {
      final details = await _repository.fetchDriver(driverId);
      if (isClosed || state.selected?.id != driverId) return;
      emit(state.copyWith(
        selected: () => details == null
            ? SelectedDriver(id: driverId, error: 'This driver is no longer visible to you.')
            : SelectedDriver(id: driverId, details: details),
      ));
    } on ApiException catch (e) {
      if (isClosed || state.selected?.id != driverId) return;
      emit(state.copyWith(selected: () => SelectedDriver(id: driverId, error: e.message)));
    }
  }

  @override
  Future<void> close() async {
    await _locations?.cancel();
    await _status?.cancel();
    return super.close();
  }
}
