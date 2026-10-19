import 'package:badrgo_ops_console/core/domain/shared_entities.dart';
import 'package:badrgo_ops_console/features/trips/domain/entities/trip.dart';

Trip tripWith({
  String id = 'trp_test',
  TripStatus status = TripStatus.requested,
  double fare = 30,
  double refunded = 0,
  String? driverId,
  DateTime? requestedAt,
  String pickup = 'Pickup St',
  // SSE payloads carry ids only; GraphQL adds the nested rider.
  bool withRiderName = true,
}) =>
    Trip(
      id: id,
      status: status,
      cityId: 'doha',
      cityName: 'Doha',
      riderId: 'rdr_1',
      rider: withRiderName ? const PersonRef(id: 'rdr_1', name: 'Rider One', phone: '+974 5••• ••19') : null,
      driverId: driverId,
      pickup: Place(pickup),
      dropoff: const Place('Dropoff Rd'),
      fare: Money(fare, 'QAR'),
      refunded: Money(refunded, 'QAR'),
      requestedAt: requestedAt ?? DateTime.utc(2026, 10, 19, 12),
    );
