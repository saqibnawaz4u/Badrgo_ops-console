import 'package:equatable/equatable.dart';

enum AlertSeverity {
  critical,
  warning,
  info;

  static AlertSeverity parse(Object? value) => switch ('$value'.toLowerCase()) {
        'critical' => critical,
        'warning' => warning,
        _ => info,
      };
}

enum AlertType {
  sos('SOS'),
  highDemand('High demand'),
  noDriverAvailable('No driver available'),
  refundIssued('Refund issued'),
  other('Alert');

  const AlertType(this.label);

  final String label;

  static AlertType parse(Object? value) => switch ('$value'.toLowerCase()) {
        'sos' => sos,
        'high_demand' => highDemand,
        'no_driver_available' => noDriverAvailable,
        'refund_issued' => refundIssued,
        _ => other,
      };
}

class Alert extends Equatable {
  const Alert({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.createdAt,
    this.cityId,
    this.cityName,
    this.tripId,
    this.driverId,
    this.driverName,
    this.acknowledgedAt,
    this.acknowledgedBy,
  });

  final String id;
  final AlertType type;
  final AlertSeverity severity;
  final String message;
  final DateTime createdAt;
  final String? cityId;
  final String? cityName;
  final String? tripId;
  final String? driverId;
  final String? driverName;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;

  bool get isOpen => acknowledgedAt == null;
  bool get isCritical => severity == AlertSeverity.critical;

  /// Local mark once our REST acknowledge succeeds; the SSE frame that
  /// follows brings the server's values through [mergeLive].
  Alert markAcknowledged(DateTime at) => Alert(
        id: id,
        type: type,
        severity: severity,
        message: message,
        createdAt: createdAt,
        cityId: cityId,
        cityName: cityName,
        tripId: tripId,
        driverId: driverId,
        driverName: driverName,
        acknowledgedAt: acknowledgedAt ?? at,
        acknowledgedBy: acknowledgedBy,
      );

  /// Live frames are REST-shaped (ids only); keep names we already have.
  Alert mergeLive(Alert live) => Alert(
        id: id,
        type: live.type,
        severity: live.severity,
        message: live.message,
        createdAt: live.createdAt,
        cityId: live.cityId ?? cityId,
        cityName: cityName,
        tripId: live.tripId ?? tripId,
        driverId: live.driverId ?? driverId,
        driverName: driverName,
        acknowledgedAt: live.acknowledgedAt,
        acknowledgedBy: live.acknowledgedBy,
      );

  @override
  List<Object?> get props => [
        id, type, severity, message, createdAt, cityId, cityName, tripId, driverId, driverName,
        acknowledgedAt, acknowledgedBy,
      ];
}

class AlertChange extends Equatable {
  const AlertChange(this.alert, {required this.isNew});

  final Alert alert;

  /// `alert.created` (true) or `alert.acknowledged` (false).
  final bool isNew;

  @override
  List<Object?> get props => [alert, isNew];
}

class AlertPage extends Equatable {
  const AlertPage({required this.alerts, required this.endCursor, required this.hasNextPage, required this.totalCount});

  final List<Alert> alerts;
  final String? endCursor;
  final bool hasNextPage;
  final int totalCount;

  @override
  List<Object?> get props => [alerts, endCursor, hasNextPage, totalCount];
}
