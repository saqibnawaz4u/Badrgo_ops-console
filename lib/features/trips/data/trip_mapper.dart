import '../../../core/domain/shared_entities.dart';
import '../domain/entities/trip.dart';

/// Maps both trip shapes the API returns:
/// * GraphQL: nested `rider`, `driver`, `city`, `pickup.location`, enums in
///   upper case.
/// * REST / SSE: flat `riderId`, `driverId`, `cityId`, `pickup.lat/lng`,
///   lower-case status.
class TripMapper {
  const TripMapper._();

  static const listFields = '''
    id status requestedAt assignedAt startedAt completedAt cancelledAt
    pickup { address } dropoff { address }
    fare { amount currency } refunded { amount currency }
    city { id name } rider { id name } driver { id name }
  ''';

  static const detailFields = '''
    id status distanceKm
    requestedAt assignedAt startedAt completedAt cancelledAt
    cancelReason cancelledBy refundReason
    fare { amount currency } refunded { amount currency }
    pickup { address location { lat lng } }
    dropoff { address location { lat lng } }
    city { id name currency }
    rider { id name phone email rating }
    driver { id name phone rating status vehicle { make model plate color } }
  ''';

  static Trip fromJson(Map<String, dynamic> json) {
    final city = json['city'] as Map<String, dynamic>?;
    final rider = json['rider'] as Map<String, dynamic>?;
    final driver = json['driver'] as Map<String, dynamic>?;
    return Trip(
      id: json['id'] as String,
      status: TripStatus.parse(json['status']),
      cityId: (city?['id'] ?? json['cityId']) as String?,
      cityName: city?['name'] as String?,
      riderId: (rider?['id'] ?? json['riderId']) as String?,
      rider: rider == null
          ? null
          : PersonRef(
              id: rider['id'] as String,
              name: '${rider['name'] ?? ''}',
              phone: rider['phone'] as String?,
              email: rider['email'] as String?,
              rating: (rider['rating'] as num?)?.toDouble(),
            ),
      driverId: (driver?['id'] ?? json['driverId']) as String?,
      driver: driver == null
          ? null
          : TripDriver(
              id: driver['id'] as String,
              name: '${driver['name'] ?? ''}',
              phone: driver['phone'] as String?,
              rating: (driver['rating'] as num?)?.toDouble(),
              status: driver['status'] as String?,
              vehicle: Vehicle.fromJson(driver['vehicle']),
            ),
      pickup: _place(json['pickup']),
      dropoff: _place(json['dropoff']),
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      fare: Money.fromJson(json['fare']),
      refunded: Money.fromJson(json['refunded']),
      refundReason: json['refundReason'] as String?,
      cancelReason: json['cancelReason'] as String?,
      cancelledBy: json['cancelledBy'] as String?,
      requestedAt: parseDate(json['requestedAt']) ?? DateTime.now(),
      assignedAt: parseDate(json['assignedAt']),
      startedAt: parseDate(json['startedAt']),
      completedAt: parseDate(json['completedAt']),
      cancelledAt: parseDate(json['cancelledAt']),
    );
  }

  static Place _place(Object? json) {
    if (json is! Map) return const Place('');
    return Place(
      '${json['address'] ?? ''}',
      GeoPoint.fromJson(json['location']) ?? GeoPoint.fromJson(json),
    );
  }

  static AssignableDriver driverFromJson(Map<String, dynamic> json) => AssignableDriver(
        id: json['id'] as String,
        name: '${json['name'] ?? ''}',
        rating: (json['rating'] as num?)?.toDouble(),
        vehicle: Vehicle.fromJson(json['vehicle']),
        location: GeoPoint.fromJson(json['location']),
      );
}
