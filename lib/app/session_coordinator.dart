import 'dart:async';

import '../core/connectivity/presentation/connectivity_cubit.dart';
import '../core/error/api_exception.dart';
import '../core/network/session_signals.dart';
import '../core/permissions/permissions.dart';
import '../core/realtime/sse_client.dart';
import '../core/realtime/ws_client.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/shell/domain/navigation_policy.dart';

/// The one place that connects session, connectivity and realtime:
///
/// * 401 from any transport → [AuthSessionExpired] (once; no loop).
/// * 403 → re-fetch `/api/me` so the UI follows a role change.
/// * 503 / no response → [ConnectivityCubit] (maintenance or offline).
/// * Signed in → open SSE (topics from permissions) and, if allowed, the
///   WebSocket. Permissions changed → reopen both. Signed out → close both.
/// * Maintenance → pause realtime; recovered → resume it.
/// * Every 30 s while signed in, re-check `/api/me`: catches a ban or role
///   change even when the user is idle and only SSE is open.
class SessionCoordinator {
  SessionCoordinator({
    required AuthBloc auth,
    required AuthRepository authRepository,
    required ConnectivityCubit connectivity,
    required SessionSignals signals,
    required SseClient sse,
    required WsClient ws,
    this.policy = const NavigationPolicy(),
    this.meRefreshInterval = const Duration(seconds: 30),
  })  : _auth = auth,
        _authRepository = authRepository,
        _connectivity = connectivity,
        _signals = signals,
        _sse = sse,
        _ws = ws;

  final AuthBloc _auth;
  final AuthRepository _authRepository;
  final ConnectivityCubit _connectivity;
  final SessionSignals _signals;
  final SseClient _sse;
  final WsClient _ws;
  final NavigationPolicy policy;
  final Duration meRefreshInterval;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _meTimer;
  Timer? _forbiddenDebounce;

  /// What the realtime connections were opened for. Reopen when it changes.
  ({String userId, String token, Permissions permissions})? _connectedFor;
  ConnectivityPhase _lastPhase = ConnectivityPhase.online;

  void start() {
    _subscriptions.addAll([
      _signals.unauthorized.listen((_) => _auth.add(const AuthSessionExpired())),
      _signals.forbidden.listen((_) => _onForbidden()),
      _signals.maintenance.listen(_connectivity.reportMaintenance),
      _signals.networkFailure.listen((_) => _connectivity.reportNetworkFailure()),
      _auth.stream.listen(_onAuth),
      _connectivity.stream.listen(_onConnectivity),
    ]);
    _onAuth(_auth.state);
  }

  void _onForbidden() {
    _forbiddenDebounce?.cancel();
    _forbiddenDebounce = Timer(const Duration(milliseconds: 300), () {
      _auth.add(const AuthRefreshRequested());
    });
  }

  void _onAuth(AuthState state) {
    if (!state.isAuthenticated) {
      _stopRealtime();
      return;
    }
    final user = state.user!;
    final key = (userId: user.id, token: state.token!, permissions: user.permissions);
    if (key == _connectedFor) return;
    _connectedFor = key;

    // start() on each client stops any previous connection first, so an
    // account switch or role change never leaves a duplicate open.
    _sse.start(token: key.token, topics: policy.realtimeTopicsFor(user.permissions));
    if (policy.needsDriverSocket(user.permissions)) {
      _ws.start(token: key.token);
    } else {
      _ws.stop();
    }
    if (!_connectivity.state.isOnline) {
      _sse.pause();
      _ws.pause();
    }
    _meTimer?.cancel();
    _meTimer = Timer.periodic(meRefreshInterval, (_) {
      if (_connectivity.state.isOnline) _auth.add(const AuthRefreshRequested());
    });
  }

  void _stopRealtime() {
    _connectedFor = null;
    _meTimer?.cancel();
    _meTimer = null;
    _sse.stop();
    _ws.stop();
  }

  void _onConnectivity(ConnectivityState state) {
    final previous = _lastPhase;
    _lastPhase = state.phase;
    if (previous == state.phase) return;
    if (!state.isOnline) {
      _sse.pause();
      _ws.pause();
      return;
    }
    // Back online: reconnect realtime, and finish a restore that was
    // interrupted by maintenance. Pages refresh via RefreshOnRecovery.
    _sse.resume();
    _ws.resume();
    if (_auth.state.status == AuthStatus.unknown) _auth.add(const AuthRestoreRetried());
  }

  /// Called by SSE and WebSocket before reconnecting. A REST `/api/me` sees
  /// the real status code: 401 signs out, 503 enters maintenance (both via
  /// the global signals, which stop or pause the clients). Anything else,
  /// including no response, keeps retrying with backoff: a short network
  /// blip leaves the connectivity phase unchanged, so a client that paused
  /// itself here would never be resumed. A real outage switches the phase
  /// to unreachable, which pauses the clients in [_onConnectivity].
  Future<bool> preflight() async {
    try {
      final me = await _authRepository.fetchMe();
      _auth.add(AuthUserRefreshed(me));
      return true;
    } on ApiException catch (e) {
      return switch (e.code) {
        ApiErrorCode.unauthenticated || ApiErrorCode.maintenance => false,
        _ => true,
      };
    }
  }

  Future<void> dispose() async {
    _stopRealtime();
    _forbiddenDebounce?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
  }
}
