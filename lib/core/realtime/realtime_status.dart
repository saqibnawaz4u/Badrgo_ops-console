import 'package:equatable/equatable.dart';

enum RealtimePhase {
  /// Not started (signed out, or the role has no realtime access).
  idle,
  connecting,
  open,

  /// Dropped while the API is up; retrying with backoff.
  reconnecting,

  /// Waiting for the API to come back (maintenance or offline).
  paused,
}

class RealtimeStatus extends Equatable {
  const RealtimeStatus(this.phase, {this.attempt = 0, this.retryAt});

  static const idle = RealtimeStatus(RealtimePhase.idle);

  final RealtimePhase phase;
  final int attempt;
  final DateTime? retryAt;

  bool get isOpen => phase == RealtimePhase.open;
  bool get isTroubled =>
      phase == RealtimePhase.reconnecting ||
      phase == RealtimePhase.paused ||
      (phase == RealtimePhase.connecting && attempt > 0);

  @override
  List<Object?> get props => [phase, attempt, retryAt];
}

/// Lifecycle that the app layer drives for both SSE and WebSocket.
abstract interface class RealtimeConnection {
  RealtimeStatus get status;
  Stream<RealtimeStatus> get statusStream;

  /// Close and wait for [resume] (used during maintenance).
  void pause();
  void resume();

  /// Close for good and forget all state (sign-out, account switch).
  void stop();
}
