import '../../../../core/realtime/realtime_status.dart';
import '../entities/driver.dart';

abstract interface class LiveMapRepository {
  /// WebSocket `drivers.locations`: a full snapshot every ~2 s.
  Stream<List<DriverLocation>> watchLocations();

  /// GraphQL `driver(id)` with the nested current trip.
  Future<DriverDetails?> fetchDriver(String id);

  RealtimeStatus get connectionStatus;
  Stream<RealtimeStatus> watchConnectionStatus();
}

abstract interface class DriverChatRepository {
  /// REST `GET /api/drivers/{id}/messages`, oldest first.
  Future<List<ChatMessage>> fetchHistory(String driverId);

  /// WebSocket `driver.messages` channel.
  Stream<ChatMessage> watchMessages();

  /// WebSocket `driver.message.send`; completes with the stored message.
  Future<ChatMessage> send({required String driverId, required String body});
}
