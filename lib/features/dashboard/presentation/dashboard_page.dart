import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/connectivity/presentation/refresh_on_recovery.dart';
import '../../../core/presentation/formatters.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../../../core/realtime/live_status_cubit.dart';
import '../domain/entities/kpis.dart';
import '../domain/repositories/dashboard_repository.dart';
import 'bloc/dashboard_cubit.dart';
import 'widgets/trips_chart.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => DashboardCubit(context.read<DashboardRepository>())..start(),
    child: Builder(
      builder: (context) =>
          RefreshOnRecovery(onRecovered: context.read<DashboardCubit>().load, child: const _DashboardView()),
    ),
  );
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final cubit = context.read<DashboardCubit>();
        if (state.status == DashboardStatus.loading && state.kpis == null) {
          return const LoadingView(label: 'Loading KPIs…');
        }
        if (state.status == DashboardStatus.failure && state.kpis == null) {
          return ErrorView(message: state.error ?? 'Unknown error', onRetry: cubit.load);
        }
        final kpis = state.kpis!;
        return ListView(
          padding: pagePadding(context, top: 24, bottom: 24),
          children: [
            PageHeader(
              title: 'Dashboard',
              badge: Text('Last 24 hours', style: Theme.of(context).textTheme.bodyMedium),
              actions: [_LiveStamp(lastLiveAt: state.lastLiveAt, generatedAt: kpis.generatedAt)],
            ),
            // A failed refresh keeps the last tiles; say so without hiding them.
            if (state.error != null) ...[
              const SizedBox(height: 8),
              _RefreshNotice(message: state.error!, onRetry: cubit.load),
            ],
            const SizedBox(height: 16),
            _KpiGrid(kpis: kpis),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final chart = _ChartCard(state: state, onRange: cubit.selectRange, onRetry: cubit.retryChart);
                final top = _TopDriversCard(drivers: kpis.topDrivers);
                if (constraints.maxWidth < 1000) {
                  return Column(children: [chart, const SizedBox(height: 16), top]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: chart),
                    const SizedBox(width: 16),
                    Expanded(child: top),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _LiveStamp extends StatelessWidget {
  const _LiveStamp({required this.lastLiveAt, required this.generatedAt});

  final DateTime? lastLiveAt;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final ops = OpsColors.of(context);
    // Live only while ticks arrive: falls back to "Snapshot" once SSE drops.
    final eventsOpen = context.select<LiveStatusCubit, bool>((c) => c.state.events.isOpen);
    final live = eventsOpen && lastLiveAt != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: live ? ops.success : ops.neutral),
        const SizedBox(width: 6),
        Text(
          live ? 'Live · updated ${formatTime(generatedAt)}' : 'Snapshot from ${formatTime(generatedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RefreshNotice extends StatelessWidget {
  const _RefreshNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final warning = OpsColors.of(context).warning;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing the last data. Refresh failed: $message',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis});

  final Kpis kpis;

  @override
  Widget build(BuildContext context) {
    final t = kpis.trips;
    final tiles = [
      _KpiTile(
        icon: Icons.directions_car,
        label: 'Active trips',
        values: [formatCount(t.active)],
        caption: '${t.requested} requested · ${t.assigned} assigned · ${t.inProgress} in progress',
      ),
      _KpiTile(icon: Icons.check_circle_outline, label: 'Completed', values: [formatCount(t.completed)]),
      _KpiTile(
        icon: Icons.cancel_outlined,
        label: 'Cancellation rate',
        values: [formatPercent(t.cancellationRate)],
        caption: '${formatCount(t.cancelled)} cancelled',
      ),
      _KpiTile(
        icon: Icons.payments_outlined,
        label: 'Revenue',
        values: formatMoneyList(kpis.revenue),
        caption: 'Avg fare ${formatMoneyList(kpis.averageFare).join(' · ')}',
      ),
      _KpiTile(
        icon: Icons.local_taxi_outlined,
        // Short label so it fits two-up on phones; the caption says which
        // number is which.
        label: 'Drivers',
        values: ['${kpis.drivers.available} / ${kpis.drivers.onTrip}'],
        caption: 'available / on trip · ${kpis.drivers.offline} offline',
      ),
      _KpiTile(
        icon: Icons.notifications_active_outlined,
        label: 'Open alerts',
        values: [formatCount(kpis.openAlerts)],
        alert: kpis.openAlerts > 0,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth > 1200
            ? 6
            : constraints.maxWidth > 700
            ? 3
            : 2;
        final width = (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.icon, required this.label, required this.values, this.caption, this.alert = false});

  final IconData icon;
  final String label;

  /// More than one line when the value is per currency.
  final List<String> values;
  final String? caption;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final warning = OpsColors.of(context).warning;
    final accent = alert ? warning : theme.colorScheme.primary;
    return Card(
      // Tiles that need attention are tinted so they stand out in the grid.
      color: alert ? Color.alphaBlend(warning.withValues(alpha: 0.08), theme.cardTheme.color!) : null,
      shape: alert
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: warning.withValues(alpha: 0.5)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              // Fixed gap (not a Spacer) so values line up across tiles
              // whether or not they have a caption.
              const SizedBox(height: 12),
              for (final v in values)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v,
                    style: (values.length > 1 ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium)?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              if (caption != null) Text(caption!, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.state, required this.onRange, required this.onRetry});

  final DashboardState state;
  final ValueChanged<KpiRange> onRange;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        // Stretch so the header Wrap spans the card and spaceBetween puts
        // the range switch on the right.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Trips over time', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  if (state.chartLoading)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              SegmentedButton<KpiRange>(
                segments: [for (final r in KpiRange.values) ButtonSegment(value: r, label: Text(r.label))],
                selected: {state.chartRange},
                onSelectionChanged: (s) => onRange(s.first),
                showSelectedIcon: false,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.chartRange == KpiRange.last24h ? 'Hourly buckets (UTC)' : 'Daily buckets (UTC)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: state.chartError != null
                ? ErrorView(message: state.chartError!, onRetry: onRetry)
                : TripsChart(series: state.series, range: state.chartRange),
          ),
        ],
      ),
    ),
  );
}

class _TopDriversCard extends StatelessWidget {
  const _TopDriversCard({required this.drivers});

  final List<TopDriver> drivers;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top drivers (24h)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (drivers.isEmpty) const Text('No completed trips yet.'),
          for (final (i, d) in drivers.take(8).indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
              title: Text(d.name ?? d.driverId, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${d.trips} trips'),
              trailing: Text(formatMoney(d.earnings)),
            ),
        ],
      ),
    ),
  );
}
