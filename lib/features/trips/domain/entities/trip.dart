import 'package:equatable/equatable.dart';

import '../../../../core/domain/shared_entities.dart';

enum TripStatus {
  requested('REQUESTED', 'Requested'),
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In progress'),
  completed('COMPLETED', 'Completed'),
  cancelled('CANCELLED', 'Cancelled');

  const TripStatus(this.graphQLName, this.label);

  /// GraphQL enum value (`IN_PROGRESS`). REST uses the lower-case form.
  final String graphQLName;
  final String label;

  /// Accepts both `IN_PROGRESS` (GraphQL) and `in_progress` (REST/SSE).
  static TripStatus parse(Object? value) {
    final upper = '$value'.toUpperCase();
    return TripStatus.values.firstWhere(
      (s) => s.graphQLName == upper,
      orElse: () => TripStatus.requested,
    );
  }

  bool get isActive => this == requested || this == assigned || this == inProgress;
}

class PersonRef extends Equatable {
  const PersonRef({required this.id, required this.name, this.phone, this.email, this.rating});

  final String id;
  final String name;

  /// Masked by the server for roles without `pii:read`.
  final String? phone;
  final String? email;
  final double? rating;

  @override
  List<Object?> get props => [id, name, phone, email, rating];
}

class TripDriver extends PersonRef {
  const TripDriver({
    required super.id,
    required super.name,
    super.phone,
    super.rating,
    this.vehicle,
    this.status,
  });

  final Vehicle? vehicle;
  final String? status;

  @override
  List<Object?> get props => [...super.props, vehicle, status];
}

class Place extends Equatable {
  const Place(this.address, [this.location]);

  final String address;
  final GeoPoint? location;

  @override
  List<Object?> get props => [address, location];
}

class TripTimelineEntry extends Equatable {
  const TripTimelineEntry(this.status, this.at);

  final TripStatus status;
  final DateTime at;

  @override
  List<Object?> get props => [status, at];
}

class Trip extends Equatable {
  const Trip({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    required this.refunded,
    required this.requestedAt,
    this.cityId,
    this.cityName,
    this.riderId,
    this.rider,
    this.driverId,
    this.driver,
    this.distanceKm,
    this.refundReason,
    this.cancelReason,
    this.cancelledBy,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
  });

  final String id;
  final TripStatus status;
  final String? cityId;
  final String? cityName;
  final String? riderId;
  final PersonRef? rider;
  final String? driverId;
  final TripDriver? driver;
  final Place pickup;
  final Place dropoff;
  final double? distanceKm;
  final Money fare;
  final Money refunded;
  final String? refundReason;
  final String? cancelReason;
  final String? cancelledBy;
  final DateTime requestedAt;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// What is left to refund. Never negative.
  Money get refundable {
    final left = fare.amount - refunded.amount;
    return Money(left < 0 ? 0 : double.parse(left.toStringAsFixed(2)), fare.currency);
  }

  /// Applies a live (REST-shaped) update to a row that may already carry
  /// nested names from GraphQL. Names are kept while the ids still match.
  Trip mergeLive(Trip live) => Trip(
        id: id,
        status: live.status,
        cityId: live.cityId ?? cityId,
        cityName: cityName,
        riderId: live.riderId ?? riderId,
        rider: (live.riderId == null || live.riderId == riderId) ? rider : null,
        driverId: live.driverId,
        driver: live.driverId != null && live.driverId == driverId ? driver : null,
        pickup: live.pickup,
        dropoff: live.dropoff,
        distanceKm: live.distanceKm ?? distanceKm,
        fare: live.fare,
        refunded: live.refunded,
        refundReason: live.refundReason,
        cancelReason: live.cancelReason,
        cancelledBy: live.cancelledBy,
        requestedAt: live.requestedAt,
        assignedAt: live.assignedAt,
        startedAt: live.startedAt,
        completedAt: live.completedAt,
        cancelledAt: live.cancelledAt,
      );

  /// Status changes in order, built from the timestamps (the same rule the
  /// GraphQL `timeline` field uses), so live REST-shaped updates have it too.
  List<TripTimelineEntry> get timeline => [
        TripTimelineEntry(TripStatus.requested, requestedAt),
        if (assignedAt != null) TripTimelineEntry(TripStatus.assigned, assignedAt!),
        if (startedAt != null) TripTimelineEntry(TripStatus.inProgress, startedAt!),
        if (completedAt != null) TripTimelineEntry(TripStatus.completed, completedAt!),
        if (cancelledAt != null) TripTimelineEntry(TripStatus.cancelled, cancelledAt!),
      ]..sort((a, b) => a.at.compareTo(b.at));

  /// True when names are missing and a GraphQL fetch would fill them in.
  bool get needsHydration =>
      (riderId != null && rider == null) || (driverId != null && driver == null);

  @override
  List<Object?> get props => [
        id, status, cityId, cityName, riderId, rider, driverId, driver, pickup, dropoff,
        distanceKm, fare, refunded, refundReason, cancelReason, cancelledBy, requestedAt,
        assignedAt, startedAt, completedAt, cancelledAt,
      ];
}

class TripPage extends Equatable {
  const TripPage({required this.trips, required this.endCursor, required this.hasNextPage, required this.totalCount});

  final List<Trip> trips;
  final String? endCursor;
  final bool hasNextPage;
  final int totalCount;

  @override
  List<Object?> get props => [trips, endCursor, hasNextPage, totalCount];
}

/// A live `trip.created` / `trip.updated` frame.
class TripChange extends Equatable {
  const TripChange({required this.isNew, required this.change, required this.trip});

  final bool isNew;

  /// created, assigned, reassigned, started, completed, cancelled, refunded.
  final String change;
  final Trip trip;

  @override
  List<Object?> get props => [isNew, change, trip];
}

/// A driver that can take a trip, with distance to the pickup.
class AssignableDriver extends Equatable {
  const AssignableDriver({
    required this.id,
    required this.name,
    this.rating,
    this.vehicle,
    this.location,
    this.distanceKm,
  });

  final String id;
  final String name;
  final double? rating;
  final Vehicle? vehicle;
  final GeoPoint? location;
  final double? distanceKm;

  AssignableDriver withDistance(double? km) => AssignableDriver(
      id: id, name: name, rating: rating, vehicle: vehicle, location: location, distanceKm: km);

  @override
  List<Object?> get props => [id, name, rating, vehicle, location, distanceKm];
}
