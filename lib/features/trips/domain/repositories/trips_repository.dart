import '../entities/trip.dart';
import '../entities/trip_filter.dart';

abstract interface class TripsRepository {
  /// GraphQL `trips`, cursor based, newest first.
  Future<TripPage> fetchTrips({required TripFilter filter, String? after, int first = 25});

  /// GraphQL `trip` with nested rider, driver and city. Null when the trip
  /// does not exist or belongs to another city.
  Future<Trip?> fetchTrip(String id);

  /// Several trips in one GraphQL request (aliased fields), used to fill in
  /// names for rows that arrived over SSE.
  Future<List<Trip>> fetchTripsByIds(List<String> ids);

  /// GraphQL `drivers(status: AVAILABLE)` in the trip's city.
  Future<List<AssignableDriver>> fetchAvailableDrivers({String? cityId});

  /// SSE `trip.created` and `trip.updated`.
  Stream<TripChange> watchChanges();

  /// REST writes.
  Future<void> assignDriver({required String tripId, required String driverId});
  Future<void> cancelTrip({required String tripId, required String reason});
  Future<void> refundTrip({required String tripId, required double amount, required String reason});
}
