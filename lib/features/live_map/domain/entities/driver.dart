import 'package:equatable/equatable.dart';

import '../../../../core/domain/shared_entities.dart';

enum DriverStatus {
  available('Available'),
  onTrip('On trip'),
  offline('Offline');

  const DriverStatus(this.label);

  final String label;

  static DriverStatus parse(Object? value) => switch ('$value'.toLowerCase()) {
        'available' => available,
        'on_trip' => onTrip,
        _ => offline,
      };
}

/// One marker from a `drivers.locations` snapshot.
class DriverLocation extends Equatable {
  const DriverLocation({
    required this.id,
    required this.name,
    required this.status,
    required this.position,
    this.cityId,
    this.heading,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final DriverStatus status;
  final GeoPoint position;
  final String? cityId;
  final double? heading;
  final DateTime? lastSeenAt;

  @override
  List<Object?> get props => [id, name, status, position, cityId, heading, lastSeenAt];
}

class CurrentTripSummary extends Equatable {
  const CurrentTripSummary({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    this.riderName,
  });

  final String id;
  final String status;
  final String pickup;
  final String dropoff;
  final String? riderName;

  @override
  List<Object?> get props => [id, status, pickup, dropoff, riderName];
}

class DriverDetails extends Equatable {
  const DriverDetails({
    required this.id,
    required this.name,
    required this.status,
    this.phone,
    this.rating,
    this.vehicle,
    this.cityName,
    this.lastSeenAt,
    this.currentTrip,
  });

  final String id;
  final String name;
  final DriverStatus status;

  /// Masked for roles without `pii:read`.
  final String? phone;
  final double? rating;
  final Vehicle? vehicle;
  final String? cityName;
  final DateTime? lastSeenAt;
  final CurrentTripSummary? currentTrip;

  @override
  List<Object?> get props => [id, name, status, phone, rating, vehicle, cityName, lastSeenAt, currentTrip];
}

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.driverId,
    required this.fromDriver,
    required this.body,
    required this.createdAt,
    this.sentBy,
  });

  final String id;
  final String driverId;
  final bool fromDriver;
  final String body;
  final DateTime createdAt;
  final String? sentBy;

  @override
  List<Object?> get props => [id, driverId, fromDriver, body, createdAt, sentBy];
}
