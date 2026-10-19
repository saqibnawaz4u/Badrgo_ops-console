import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../error/api_exception.dart';
import 'backoff.dart';
import 'realtime_status.dart';
import 'server_events.dart';

typedef SocketConnector = WebSocketChannel Function(Uri uri);

/// WebSocket client for `/ws`: JSON envelopes `{ type, id?, payload? }`.
///
/// * Channels are reference counted: subscribe on first listener, re-subscribe
///   after every `welcome`, unsubscribe when the last listener leaves.
/// * Close code 4001 means "unauthorized": we report it and never reconnect.
/// * Any other drop reconnects with backoff, after a REST [preflight] that
///   tells a dropped socket apart from maintenance or an expired session.
class WsClient implements DriverSocket, RealtimeConnection {
  WsClient({
    required Uri Function(String token) uriFor,
    required Future<bool> Function() preflight,
    required void Function() onUnauthorized,
    required void Function() onForbidden,
    SocketConnector? connector,
    Backoff? backoff,
    this.pingInterval = const Duration(seconds: 25),
    this.commandTimeout = const Duration(seconds: 10),
    this.pongTimeout = const Duration(seconds: 10),
  })  : _uriFor = uriFor,
        _preflight = preflight,
        _onUnauthorized = onUnauthorized,
        _onForbidden = onForbidden,
        _connector = connector ?? WebSocketChannel.connect,
        _backoff = backoff ?? Backoff();

  /// Channel name → frame `type` the server pushes on it.
  static const channelFrames = {
    'drivers.locations': 'drivers.locations',
    'driver.messages': 'driver.message',
  };

  static const unauthorizedCloseCode = 4001;

  final Uri Function(String token) _uriFor;
  final Future<bool> Function() _preflight;
  final void Function() _onUnauthorized;
  final void Function() _onForbidden;
  final SocketConnector _connector;
  final Backoff _backoff;
  final Duration pingInterval;
  final Duration commandTimeout;

  /// How long after a ping we wait for any frame before treating the socket
  /// as dropped. A half-open connection never fires `onDone` on its own.
  final Duration pongTimeout;

  final _statusController = StreamController<RealtimeStatus>.broadcast();
  final _channels = <String, StreamController<Map<String, dynamic>>>{};
  final _pending = <String, Completer<Map<String, dynamic>>>{};

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _pongTimer;
  String? _token;
  RealtimeStatus _status = RealtimeStatus.idle;
  bool _running = false;
  bool _paused = false;
  int _generation = 0;
  int _nextId = 0;

  @override
  RealtimeStatus get status => _status;

  @override
  Stream<RealtimeStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> channel(String channel) {
    // ignore: close_sinks (closed implicitly: removed on last cancel)
    final controller = _channels.putIfAbsent(
      channel,
      () => StreamController<Map<String, dynamic>>.broadcast(
        onListen: () => _sendIfOpen('subscribe', {'channel': channel}),
        onCancel: () {
          _channels.remove(channel);
          _sendIfOpen('unsubscribe', {'channel': channel});
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>> command(String type, Map<String, dynamic> payload) {
    if (!_status.isOpen) {
      return Future.error(const ApiException(
        ApiErrorCode.network,
        'Live connection is not open. Try again in a moment.',
      ));
    }
    final id = 'c-${++_nextId}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(type, payload, id: id);
    return completer.future.timeout(commandTimeout, onTimeout: () {
      _pending.remove(id);
      throw const ApiException(ApiErrorCode.network, 'The server did not answer in time.');
    });
  }

  void start({required String token}) {
    stop();
    _running = true;
    _token = token;
    _connect();
  }

  @override
  void stop() {
    _running = false;
    _paused = false;
    _generation++;
    _token = null;
    _backoff.reset();
    _teardown();
    _setStatus(RealtimeStatus.idle);
  }

  @override
  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _generation++;
    _teardown();
    _setStatus(const RealtimeStatus(RealtimePhase.paused));
  }

  @override
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    _backoff.reset();
    _connect();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _setStatus(RealtimeStatus(RealtimePhase.connecting, attempt: _backoff.attempt));

    final socket = _connector(_uriFor(_token!));
    _socket = socket;
    try {
      await socket.ready;
    } on Object {
      if (generation == _generation) unawaited(_onClosed(generation, null));
      return;
    }
    if (generation != _generation) {
      unawaited(socket.sink.close());
      return;
    }
    _socketSub = socket.stream.listen(
      (raw) => _onFrame(raw, generation),
      onDone: () => _onClosed(generation, socket.closeCode),
      onError: (Object _) {},
    );
  }

  void _onFrame(Object? raw, int generation) {
    // Any frame proves the connection is alive, not only `pong`.
    _pongTimer?.cancel();
    _pongTimer = null;
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } on Object {
      return;
    }
    final type = frame['type'] as String?;
    final id = frame['id'] as String?;
    final payload = (frame['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    switch (type) {
      case 'welcome':
        _backoff.reset();
        _setStatus(const RealtimeStatus(RealtimePhase.open));
        for (final channel in _channels.keys) {
          _send('subscribe', {'channel': channel});
        }
        _pingTimer?.cancel();
        _pingTimer = Timer.periodic(pingInterval, (_) => _ping(generation));
      case 'ack':
        _pending.remove(id)?.complete(payload);
      case 'error':
        final error = ApiException(
          ApiErrorCode.fromServer(payload['code'] as String?),
          (payload['message'] as String?) ?? 'The live connection reported an error.',
          serverCode: payload['code'] as String?,
        );
        _pending.remove(id)?.completeError(error);
        if (error.code == ApiErrorCode.forbidden) _onForbidden();
        if (error.code == ApiErrorCode.unauthenticated) _onUnauthorized();
      case 'pong':
        break;
      default:
        for (final entry in _channels.entries) {
          if (channelFrames[entry.key] == type) entry.value.add(payload);
        }
    }
  }

  /// Keeps the first deadline if an earlier ping is still unanswered.
  void _ping(int generation) {
    _send('ping', null);
    _pongTimer ??= Timer(pongTimeout, () {
      _pongTimer = null;
      unawaited(_onClosed(generation, null));
    });
  }

  Future<void> _onClosed(int generation, int? closeCode) async {
    if (generation != _generation || !_running || _paused) return;
    _teardown();

    if (closeCode == unauthorizedCloseCode) {
      _setStatus(RealtimeStatus.idle);
      _running = false;
      _onUnauthorized();
      return;
    }

    final retryGeneration = ++_generation;
    final delay = _backoff.next();
    _setStatus(RealtimeStatus(
      RealtimePhase.reconnecting,
      attempt: _backoff.attempt,
      retryAt: DateTime.now().add(delay),
    ));
    final shouldRetry = await _preflight();
    if (retryGeneration != _generation || !_running || _paused) return;
    if (!shouldRetry) {
      pause();
      return;
    }
    _retryTimer = Timer(delay, () {
      if (retryGeneration == _generation && _running && !_paused) _connect();
    });
  }

  void _teardown() {
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _pongTimer = null;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    unawaited(_socket?.sink.close());
    _socket = null;
    for (final pending in _pending.values) {
      pending.completeError(const ApiException(ApiErrorCode.network, 'Live connection closed.'));
    }
    _pending.clear();
  }

  void _sendIfOpen(String type, Map<String, dynamic> payload) {
    if (_status.isOpen) _send(type, payload);
  }

  void _send(String type, Map<String, dynamic>? payload, {String? id}) {
    _socket?.sink.add(jsonEncode({
      'type': type,
      'id': ?id,
      'payload': ?payload,
    }));
  }

  void _setStatus(RealtimeStatus status) {
    if (status == _status) return;
    _status = status;
    _statusController.add(status);
  }
}
