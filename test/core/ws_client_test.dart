import 'dart:async';
import 'dart:convert';

import 'package:badrgo_ops_console/core/realtime/backoff.dart';
import 'package:badrgo_ops_console/core/realtime/realtime_status.dart';
import 'package:badrgo_ops_console/core/realtime/ws_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory socket. With [answerPings] it replies `pong` to every `ping`.
class _FakeChannel implements WebSocketChannel {
  _FakeChannel({required this.answerPings}) {
    sink = _FakeSink(this);
  }

  final bool answerPings;
  final incoming = StreamController<dynamic>();
  final sent = <String>[];

  @override
  // ignore: close_sinks (closed by the client under test)
  late final _FakeSink sink;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => null;

  void push(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;

  @override
  void add(dynamic data) {
    _channel.sent.add(data as String);
    if (_channel.answerPings && (jsonDecode(data) as Map)['type'] == 'ping') {
      scheduleMicrotask(() => _channel.push({'type': 'pong'}));
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<_FakeChannel> sockets;
  late WsClient client;
  late List<RealtimeStatus> statuses;
  var preflights = 0;

  WsClient build({required bool answerPings}) {
    sockets = [];
    statuses = [];
    preflights = 0;
    final ws = WsClient(
      uriFor: (token) => Uri.parse('wss://api.test/ws?token=$token'),
      preflight: () async {
        preflights++;
        return true;
      },
      onUnauthorized: () {},
      onForbidden: () {},
      connector: (_) {
        final socket = _FakeChannel(answerPings: answerPings);
        sockets.add(socket);
        return socket;
      },
      backoff: Backoff(initial: const Duration(milliseconds: 10), jitter: 0),
      pingInterval: const Duration(milliseconds: 20),
      pongTimeout: const Duration(milliseconds: 30),
    );
    ws.statusStream.listen(statuses.add);
    return ws;
  }

  Future<void> openFirstSocket() async {
    client.start(token: 't');
    await Future<void>.delayed(Duration.zero);
    sockets.single.push({'type': 'welcome'});
    await Future<void>.delayed(Duration.zero);
    expect(client.status.isOpen, isTrue);
  }

  tearDown(() => client.stop());

  test('no answer to a ping drops the socket and reconnects after a preflight', () async {
    client = build(answerPings: false);
    await openFirstSocket();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sockets.first.sent.map((s) => jsonDecode(s)['type']), contains('ping'));
    expect(statuses.map((s) => s.phase), contains(RealtimePhase.reconnecting));
    expect(preflights, greaterThanOrEqualTo(1));
    expect(sockets.length, greaterThanOrEqualTo(2));
  });

  test('a socket that answers pings stays open', () async {
    client = build(answerPings: true);
    await openFirstSocket();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sockets.single.sent.where((s) => jsonDecode(s)['type'] == 'ping').length, greaterThan(2));
    expect(client.status.isOpen, isTrue);
    expect(preflights, 0);
  });
}
