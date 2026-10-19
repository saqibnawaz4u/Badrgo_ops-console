import 'package:equatable/equatable.dart';

import 'trip.dart';

enum FilterMatch { yes, no, unknown }

class TripFilter extends Equatable {
  const TripFilter({this.statuses = const {}, this.from, this.to, this.search = ''});

  final Set<TripStatus> statuses;

  /// Inclusive local-day bounds on `requestedAt`.
  final DateTime? from;
  final DateTime? to;

  /// Trip id, address text or rider name (server-side semantics).
  final String search;

  bool get isEmpty => statuses.isEmpty && from == null && to == null && search.trim().isEmpty;

  TripFilter copyWith({
    Set<TripStatus>? statuses,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? search,
  }) =>
      TripFilter(
        statuses: statuses ?? this.statuses,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        search: search ?? this.search,
      );

  /// End of the `to` day, so "to 19 Oct" includes trips on the 19th.
  DateTime? get toExclusive => to == null ? null : DateTime(to!.year, to!.month, to!.day + 1);

  Map<String, dynamic> toGraphQL() => {
        if (statuses.isNotEmpty) 'status': [for (final s in statuses) s.graphQLName],
        if (from != null) 'from': DateTime(from!.year, from!.month, from!.day).toUtc().toIso8601String(),
        if (to != null) 'to': toExclusive!.toUtc().toIso8601String(),
        if (search.trim().isNotEmpty) 'search': search.trim(),
      };

  /// Does a live trip belong in the current list? `unknown` means a search
  /// is active and only the rider name (not in the SSE payload) could match,
  /// so the caller should fetch names first and ask again.
  FilterMatch matches(Trip trip) {
    if (statuses.isNotEmpty && !statuses.contains(trip.status)) return FilterMatch.no;
    if (from != null && trip.requestedAt.isBefore(DateTime(from!.year, from!.month, from!.day))) {
      return FilterMatch.no;
    }
    if (to != null && !trip.requestedAt.isBefore(toExclusive!)) return FilterMatch.no;

    final query = search.trim().toLowerCase();
    if (query.isEmpty) return FilterMatch.yes;
    final known = [trip.id, trip.pickup.address, trip.dropoff.address];
    if (known.any((field) => field.toLowerCase().contains(query))) return FilterMatch.yes;
    if (trip.rider == null) return FilterMatch.unknown;
    return trip.rider!.name.toLowerCase().contains(query) ? FilterMatch.yes : FilterMatch.no;
  }

  @override
  List<Object?> get props => [statuses, from, to, search];
}
