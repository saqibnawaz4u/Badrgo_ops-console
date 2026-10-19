import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'backoff.dart';
import 'realtime_status.dart';
import 'server_events.dart';

/// Server-Sent Events over the browser's native `EventSource`
/// (`package:web`). We take over reconnection from the browser:
///
/// * `EventSource` cannot read the HTTP status, so on any error we close it
///   and run [preflight] (a REST `GET /api/me`). REST sees the real 401 or
///   503 and raises the global signals; we only reconnect if it says so.
/// * We keep the last `id:` and reconnect with `?lastEventId=`, so the
///   server replays what we missed while we were away.
class SseClient implements ServerEvents, RealtimeConnection {
  SseClient({
    required Uri baseUri,
    required Future<bool> Function() preflight,
    Backoff? backoff,
  })  : _baseUri = baseUri,
        _preflight = preflight,
        _backoff = backoff ?? Backoff();

  static const _eventNames = [
    'ready',
    'kpi',
    'alert.created',
    'alert.acknowledged',
    'trip.created',
    'trip.updated',
    'driver.status',
  ];

  final Uri _baseUri;
  final Future<bool> Function() _preflight;
  final Backoff _backoff;

  final _frames = StreamController<ServerEvent>.broadcast();
  final _statusController = StreamController<RealtimeStatus>.broadcast();

  web.EventSource? _source;
  Timer? _retryTimer;
  String? _token;
  List<String> _topics = const [];
  String? _lastEventId;
  Set<String> _deniedTopics = const {};
  RealtimeStatus _status = RealtimeStatus.idle;
  bool _running = false;
  bool _paused = false;

  /// Bumped on every (re)connect and stop, so callbacks from an old
  /// EventSource are ignored.
  int _generation = 0;

  @override
  Stream<ServerEvent> on(String eventName) =>
      _frames.stream.where((frame) => frame.name == eventName);

  @override
  Set<String> get deniedTopics => _deniedTopics;

  @override
  RealtimeStatus get status => _status;

  @override
  Stream<RealtimeStatus> get statusStream => _statusController.stream;

  void start({required String token, required List<String> topics}) {
    stop();
    if (topics.isEmpty) return;
    _running = true;
    _token = token;
    _topics = topics;
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _paused = false;
    _generation++;
    _retryTimer?.cancel();
    _closeSource();
    _token = null;
    _lastEventId = null;
    _deniedTopics = const {};
    _backoff.reset();
    _setStatus(RealtimeStatus.idle);
  }

  @override
  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _generation++;
    _retryTimer?.cancel();
    _closeSource();
    _setStatus(const RealtimeStatus(RealtimePhase.paused));
  }

  @override
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    _backoff.reset();
    _connect();
  }

  void _connect() {
    final generation = ++_generation;
    _setStatus(RealtimeStatus(RealtimePhase.connecting, attempt: _backoff.attempt));

    final uri = _baseUri.replace(
      path: '${_baseUri.path}/api/events',
      queryParameters: {
        'token': _token!,
        'topics': _topics.join(','),
        'lastEventId': ?_lastEventId,
      },
    );
    final source = web.EventSource(uri.toString());
    _source = source;

    for (final name in _eventNames) {
      source.addEventListener(
        name,
        (web.Event event) {
          if (generation != _generation) return;
          _onFrame(name, event as web.MessageEvent);
        }.toJS,
      );
    }
    source.onerror = (web.Event _) {
      if (generation != _generation) return;
      _onError();
    }.toJS;
  }

  void _onFrame(String name, web.MessageEvent event) {
    final raw = event.data;
    if (!raw.isA<JSString>()) return;
    final Map<String, dynamic> data;
    try {
      data = jsonDecode((raw as JSString).toDart) as Map<String, dynamic>;
    } on Object {
      return;
    }
    final id = event.lastEventId;
    if (id.isNotEmpty) _lastEventId = id;

    if (name == 'ready') {
      _deniedTopics = {for (final t in (data['deniedTopics'] as List? ?? const [])) '$t'};
      _backoff.reset();
      _setStatus(const RealtimeStatus(RealtimePhase.open));
    }
    _frames.add(ServerEvent(name, data, id: id.isEmpty ? null : id));
  }

  Future<void> _onError() async {
    final generation = ++_generation;
    _closeSource();
    final delay = _backoff.next();
    _setStatus(RealtimeStatus(
      RealtimePhase.reconnecting,
      attempt: _backoff.attempt,
      retryAt: DateTime.now().add(delay),
    ));

    // Classify the failure through REST before retrying. On 401 the app
    // signs out (and calls stop); on 503 it pauses us until recovery.
    final shouldRetry = await _preflight();
    if (generation != _generation || !_running || _paused) return;
    if (!shouldRetry) {
      pause();
      return;
    }
    _retryTimer = Timer(delay, () {
      if (generation == _generation && _running && !_paused) _connect();
    });
  }

  void _closeSource() {
    _source?.close();
    _source = null;
  }

  void _setStatus(RealtimeStatus status) {
    if (status == _status) return;
    _status = status;
    _statusController.add(status);
  }
}
