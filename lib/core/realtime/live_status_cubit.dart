import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'realtime_status.dart';

class LiveStatusState extends Equatable {
  const LiveStatusState({this.events = RealtimeStatus.idle, this.socket = RealtimeStatus.idle});

  /// SSE `/api/events`.
  final RealtimeStatus events;

  /// WebSocket `/ws`.
  final RealtimeStatus socket;

  bool get anyTroubled => events.isTroubled || socket.isTroubled;
  bool get anyOpen => events.isOpen || socket.isOpen;

  @override
  List<Object?> get props => [events, socket];
}

/// Combines SSE and WebSocket status for the shell's "Live" indicator and
/// the light "reconnecting" hint.
class LiveStatusCubit extends Cubit<LiveStatusState> {
  LiveStatusCubit({required RealtimeConnection events, required RealtimeConnection socket})
      : super(LiveStatusState(events: events.status, socket: socket.status)) {
    _subs = [
      events.statusStream.listen((s) => emit(LiveStatusState(events: s, socket: state.socket))),
      socket.statusStream.listen((s) => emit(LiveStatusState(events: state.events, socket: s))),
    ];
  }

  late final List<StreamSubscription<RealtimeStatus>> _subs;

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
