part of 'trips_list_bloc.dart';

enum ListStatus { initial, loading, ready, failure }

class RowMarkInfo extends Equatable {
  const RowMarkInfo(this.kind, this.at);

  final RowMark kind;
  final DateTime at;

  @override
  List<Object?> get props => [kind, at];
}

class TripsListState extends Equatable {
  const TripsListState({
    this.status = ListStatus.initial,
    this.filter = const TripFilter(),
    this.items = const [],
    this.endCursor,
    this.hasNextPage = false,
    this.totalCount = 0,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.marks = const {},
  });

  final ListStatus status;
  final TripFilter filter;
  final List<Trip> items;
  final String? endCursor;
  final bool hasNextPage;
  final int totalCount;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;

  /// Rows that just arrived or changed live, for highlighting.
  final Map<String, RowMarkInfo> marks;

  TripsListState copyWith({
    ListStatus? status,
    TripFilter? filter,
    List<Trip>? items,
    String? Function()? endCursor,
    bool? hasNextPage,
    int? totalCount,
    bool? loadingMore,
    String? Function()? error,
    String? Function()? loadMoreError,
    Map<String, RowMarkInfo>? marks,
  }) =>
      TripsListState(
        status: status ?? this.status,
        filter: filter ?? this.filter,
        items: items ?? this.items,
        endCursor: endCursor != null ? endCursor() : this.endCursor,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        totalCount: totalCount ?? this.totalCount,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error != null ? error() : this.error,
        loadMoreError: loadMoreError != null ? loadMoreError() : this.loadMoreError,
        marks: marks ?? this.marks,
      );

  @override
  List<Object?> get props => [
        status, filter, items, endCursor, hasNextPage, totalCount, loadingMore, error,
        loadMoreError, marks,
      ];
}
