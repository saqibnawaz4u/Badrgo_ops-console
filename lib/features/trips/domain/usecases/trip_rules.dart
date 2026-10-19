import 'dart:math';

import 'package:equatable/equatable.dart';

import '../../../../core/domain/shared_entities.dart';
import '../../../../core/permissions/permissions.dart';
import '../entities/trip.dart';

/// Which actions to offer on a trip: the user's permission AND a status
/// that the API accepts. The server checks again; this is for UX.
class TripActions extends Equatable {
  const TripActions({this.canAssign = false, this.canCancel = false, this.canRefund = false});

  static const none = TripActions();

  final bool canAssign;
  final bool canCancel;
  final bool canRefund;

  bool get any => canAssign || canCancel || canRefund;

  factory TripActions.resolve(Trip trip, Permissions permissions) => TripActions(
        canAssign: permissions.can(Permission.tripAssign) &&
            (trip.status == TripStatus.requested || trip.status == TripStatus.assigned),
        canCancel: permissions.can(Permission.tripCancel) && trip.status.isActive,
        canRefund: permissions.can(Permission.tripRefund) &&
            trip.status == TripStatus.completed &&
            trip.refundable.amount > 0,
      );

  @override
  List<Object?> get props => [canAssign, canCancel, canRefund];
}

/// Client-side checks that mirror the API's rules, so the user gets an
/// answer before the round trip. The server's 422 is still shown if it
/// disagrees (e.g. another refund landed in the meantime).
class TripInputRules {
  const TripInputRules._();

  static const reasonMin = 3;
  static const reasonMax = 200;

  static String? reason(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < reasonMin) return 'Enter at least $reasonMin characters.';
    if (text.length > reasonMax) return 'Keep it under $reasonMax characters.';
    return null;
  }

  static String? refundAmount(String? value, Money refundable) {
    final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (amount == null) return 'Enter an amount.';
    if (amount <= 0) return 'The amount must be more than 0.';
    if (amount > refundable.amount + 1e-9) {
      return 'At most ${refundable.amount.toStringAsFixed(2)} ${refundable.currency} is left to refund.';
    }
    // Compare with a tolerance: 0.29 * 100 is 28.999999999999996 in floating point.
    final cents = amount * 100;
    if ((cents - cents.round()).abs() > 1e-6) return 'Use at most 2 decimals.';
    return null;
  }
}

/// Nearest drivers first, by straight-line distance to the pickup.
List<AssignableDriver> rankByDistance(List<AssignableDriver> drivers, GeoPoint? pickup) {
  final ranked = [
    for (final d in drivers)
      d.withDistance(pickup == null || d.location == null ? null : haversineKm(pickup, d.location!)),
  ];
  ranked.sort((a, b) => (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity));
  return ranked;
}

double haversineKm(GeoPoint a, GeoPoint b) {
  const earthRadiusKm = 6371.0;
  double rad(double deg) => deg * pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * earthRadiusKm * asin(sqrt(h));
}
