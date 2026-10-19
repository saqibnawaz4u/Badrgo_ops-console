import 'package:equatable/equatable.dart';

import 'realtime_status.dart';

/// One decoded SSE frame: `event:` name, JSON `data:` and optional `id:`.
class ServerEvent extends Equatable {
  const ServerEvent(this.name, this.data, {this.id});

  final String name;
  final Map<String, dynamic> data;
  final String? id;

  @override
  List<Object?> get props => [name, data, id];
}

/// Read side of `GET /api/events`. Feature repositories depend on this
/// interface and map frames into their own entities.
abstract interface class ServerEvents {
  /// Frames with the given event name (e.g. `trip.updated`).
  Stream<ServerEvent> on(String eventName);

  /// Topics the server dropped for this role (from the `ready` frame).
  Set<String> get deniedTopics;

  RealtimeStatus get status;
  Stream<RealtimeStatus> get statusStream;
}

/// Two-way side of `/ws`.
abstract interface class DriverSocket {
  /// Payloads pushed on [channel] (`drivers.locations`, `driver.messages`).
  /// Subscribes on first listen, re-subscribes after every reconnect and
  /// unsubscribes when the last listener cancels.
  Stream<Map<String, dynamic>> channel(String channel);

  /// Sends a command and completes with the `ack` payload, or throws an
  /// `ApiException` built from the matching `error` frame.
  Future<Map<String, dynamic>> command(String type, Map<String, dynamic> payload);

  RealtimeStatus get status;
  Stream<RealtimeStatus> get statusStream;
}
