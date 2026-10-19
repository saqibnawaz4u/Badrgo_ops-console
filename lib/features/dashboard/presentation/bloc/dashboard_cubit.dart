import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../domain/entities/kpis.dart';
import '../../domain/repositories/dashboard_repository.dart';

enum DashboardStatus { loading, ready, failure }

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.loading,
    this.kpis,
    this.chartRange = KpiRange.last24h,
    this.series = const [],
    this.chartLoading = false,
    this.chartError,
    this.error,
    this.lastLiveAt,
  });

  final DashboardStatus status;

  /// Tiles: always the last 24 h, kept live by SSE.
  final Kpis? kpis;
  final KpiRange chartRange;
  final List<SeriesPoint> series;
  final bool chartLoading;
  final String? chartError;
  final String? error;

  /// When the last SSE `kpi` tick arrived.
  final DateTime? lastLiveAt;

  DashboardState copyWith({
    DashboardStatus? status,
    Kpis? kpis,
    KpiRange? chartRange,
    List<SeriesPoint>? series,
    bool? chartLoading,
    String? Function()? chartError,
    String? Function()? error,
    DateTime? lastLiveAt,
  }) => DashboardState(
    status: status ?? this.status,
    kpis: kpis ?? this.kpis,
    chartRange: chartRange ?? this.chartRange,
    series: series ?? this.series,
    chartLoading: chartLoading ?? this.chartLoading,
    chartError: chartError != null ? chartError() : this.chartError,
    error: error != null ? error() : this.error,
    lastLiveAt: lastLiveAt ?? this.lastLiveAt,
  );

  @override
  List<Object?> get props => [status, kpis, chartRange, series, chartLoading, chartError, error, lastLiveAt];
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository) : super(const DashboardState());

  final DashboardRepository _repository;
  StreamSubscription<Kpis>? _live;

  /// Bumped per chart request, so a slow answer for a range the user has
  /// already left neither lands on the chart nor touches its spinner.
  int _chartRequest = 0;

  Future<void> start() async {
    _live ??= _repository.watchKpis().listen(_onLive);
    await load();
  }

  /// GraphQL snapshot: tiles plus the chart for the selected range.
  Future<void> load() async {
    if (state.kpis == null) emit(state.copyWith(status: DashboardStatus.loading));
    try {
      final kpis = await _repository.fetchKpis(KpiRange.last24h);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: DashboardStatus.ready,
          kpis: kpis.withDriverNamesFrom(state.kpis),
          series: state.chartRange == KpiRange.last24h ? kpis.series : null,
          error: () => null,
        ),
      );
      if (state.chartRange == KpiRange.last7d) await _loadChart(KpiRange.last7d);
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(
        state.kpis == null
            ? state.copyWith(status: DashboardStatus.failure, error: () => e.message)
            : state.copyWith(error: () => e.message),
      );
    }
  }

  Future<void> selectRange(KpiRange range) async {
    if (range == state.chartRange) return;
    emit(state.copyWith(chartRange: range, chartError: () => null));
    if (range == KpiRange.last24h && state.kpis != null) {
      // The tiles already hold the 24 h series: drop any pending 7d request.
      _chartRequest++;
      emit(state.copyWith(series: state.kpis!.series, chartLoading: false));
    } else {
      await _loadChart(range);
    }
  }

  /// Chart "Try again": refetches the selected range (selectRange ignores
  /// the range that is already selected).
  Future<void> retryChart() => _loadChart(state.chartRange);

  Future<void> _loadChart(KpiRange range) async {
    final request = ++_chartRequest;
    emit(state.copyWith(chartLoading: true, chartError: () => null));
    try {
      final kpis = await _repository.fetchKpis(range);
      if (isClosed || request != _chartRequest) return;
      emit(state.copyWith(series: kpis.series, chartLoading: false));
    } on ApiException catch (e) {
      if (isClosed || request != _chartRequest) return;
      emit(state.copyWith(chartLoading: false, chartError: () => e.message));
    }
  }

  void _onLive(Kpis live) {
    emit(
      state.copyWith(
        status: DashboardStatus.ready,
        kpis: live.withDriverNamesFrom(state.kpis),
        // The SSE tick covers the last 24 h, so it can drive that chart too.
        series: state.chartRange == KpiRange.last24h ? live.series : null,
        lastLiveAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _live?.cancel();
    return super.close();
  }
}
