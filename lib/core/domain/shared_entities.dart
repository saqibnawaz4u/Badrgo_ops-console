import 'package:equatable/equatable.dart';

class Money extends Equatable {
  const Money(this.amount, this.currency);

  final double amount;
  final String currency;

  static Money fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return Money((map['amount'] as num?)?.toDouble() ?? 0, (map['currency'] as String?) ?? '');
  }

  static List<Money> listFromJson(Object? json) =>
      json is List ? json.map(Money.fromJson).toList() : const [];

  /// An empty currency (missing in the payload) is treated as compatible.
  Money operator -(Money other) {
    assert(
      currency.isEmpty || other.currency.isEmpty || currency == other.currency,
      'Cannot subtract $other from $this: currencies differ.',
    );
    return Money(amount - other.amount, currency);
  }

  @override
  List<Object?> get props => [amount, currency];
}

class GeoPoint extends Equatable {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  static GeoPoint? fromJson(Object? json) {
    if (json is! Map || json['lat'] is! num || json['lng'] is! num) return null;
    return GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
  }

  @override
  List<Object?> get props => [lat, lng];
}

class City extends Equatable {
  const City({required this.id, required this.name, this.currency, this.center});

  final String id;
  final String name;
  final String? currency;
  final GeoPoint? center;

  static City? fromJson(Object? json) {
    if (json is! Map || json['id'] == null) return null;
    return City(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? json['id'] as String,
      currency: json['currency'] as String?,
      center: GeoPoint.fromJson(json['center']),
    );
  }

  @override
  List<Object?> get props => [id, name, currency, center];
}

class Vehicle extends Equatable {
  const Vehicle({required this.make, required this.model, required this.plate, required this.color});

  final String make;
  final String model;
  final String plate;
  final String color;

  static Vehicle? fromJson(Object? json) {
    if (json is! Map) return null;
    return Vehicle(
      make: '${json['make'] ?? ''}',
      model: '${json['model'] ?? ''}',
      plate: '${json['plate'] ?? ''}',
      color: '${json['color'] ?? ''}',
    );
  }

  String get label => '$color $make $model · $plate';

  @override
  List<Object?> get props => [make, model, plate, color];
}

/// Parses an ISO date from the API (UTC) into local time.
DateTime? parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
