import 'package:equatable/equatable.dart';

import '../../../../core/domain/shared_entities.dart';

enum KpiRange {
  last24h('LAST_24H', 'Last 24h'),
  last7d('LAST_7D', 'Last 7 days');

  const KpiRange(this.graphQLName, this.label);

  final String graphQLName;
  final String label;
}

class TripCounts extends Equatable {
  const TripCounts({
    required this.requested,
    required this.assigned,
    required this.inProgress,
    required this.completed,
    required this.cancelled,
    required this.active,
    required this.cancellationRate,
  });

  final int requested;
  final int assigned;
  final int inProgress;
  final int completed;
  final int cancelled;
  final int active;

  /// 0..1
  final double cancellationRate;

  @override
  List<Object?> get props => [requested, assigned, inProgress, completed, cancelled, active, cancellationRate];
}

class DriverCounts extends Equatable {
  const DriverCounts({required this.available, required this.onTrip, required this.offline, required this.total});

  final int available;
  final int onTrip;
  final int offline;
  final int total;

  @override
  List<Object?> get props => [available, onTrip, offline, total];
}

class SeriesPoint extends Equatable {
  const SeriesPoint({required this.bucket, required this.total, required this.completed, required this.cancelled});

  final DateTime bucket;
  final int total;
  final int completed;
  final int cancelled;

  @override
  List<Object?> get props => [bucket, total, completed, cancelled];
}

class TopDriver extends Equatable {
  const TopDriver({required this.driverId, required this.trips, required this.earnings, this.name});

  final String driverId;
  final String? name;
  final int trips;
  final Money earnings;

  TopDriver withName(String? value) =>
      TopDriver(driverId: driverId, trips: trips, earnings: earnings, name: value ?? name);

  @override
  List<Object?> get props => [driverId, name, trips, earnings];
}

class Kpis extends Equatable {
  const Kpis({
    required this.range,
    required this.generatedAt,
    required this.trips,
    required this.revenue,
    required this.averageFare,
    required this.refunds,
    required this.drivers,
    required this.openAlerts,
    required this.series,
    required this.topDrivers,
  });

  final KpiRange range;
  final DateTime generatedAt;
  final TripCounts trips;

  /// One entry per currency: never assume a single currency.
  final List<Money> revenue;
  final List<Money> averageFare;
  final List<Money> refunds;
  final DriverCounts drivers;
  final int openAlerts;
  final List<SeriesPoint> series;
  final List<TopDriver> topDrivers;

  /// SSE frames carry driver ids only; keep names we already know.
  Kpis withDriverNamesFrom(Kpis? previous) {
    if (previous == null) return this;
    final names = {for (final d in previous.topDrivers) d.driverId: d.name};
    return Kpis(
      range: range,
      generatedAt: generatedAt,
      trips: trips,
      revenue: revenue,
      averageFare: averageFare,
      refunds: refunds,
      drivers: drivers,
      openAlerts: openAlerts,
      series: series,
      topDrivers: [for (final d in topDrivers) d.withName(names[d.driverId])],
    );
  }

  @override
  List<Object?> get props => [
    range,
    generatedAt,
    trips,
    revenue,
    averageFare,
    refunds,
    drivers,
    openAlerts,
    series,
    topDrivers,
  ];
}
