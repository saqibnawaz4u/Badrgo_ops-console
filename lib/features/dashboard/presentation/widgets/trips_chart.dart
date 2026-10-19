import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/kpis.dart';

/// Categorical slots 1–3 of the validated dataviz palette (blue, orange,
/// aqua), stepped separately for light and dark surfaces. Status colours
/// stay reserved for status, so "cancelled" is not drawn in red.
class _SeriesColors {
  const _SeriesColors(this.total, this.cancelled, this.completed);

  final Color total;
  final Color cancelled;
  final Color completed;

  static const light = _SeriesColors(Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A));
  static const dark = _SeriesColors(Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70));
}

class TripsChart extends StatelessWidget {
  const TripsChart({super.key, required this.series, required this.range});

  final List<SeriesPoint> series;
  final KpiRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.brightness == Brightness.dark ? _SeriesColors.dark : _SeriesColors.light;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final label = range == KpiRange.last24h ? DateFormat('HH:mm') : DateFormat('E d');

    if (series.isEmpty) {
      return Center(child: Text('No trips in this period.', style: muted));
    }

    LineChartBarData line(Color color, int Function(SeriesPoint) value, {bool emphasis = false}) => LineChartBarData(
      spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), value(series[i]).toDouble())],
      color: color,
      barWidth: 2,
      isCurved: false,
      dotData: FlDotData(show: series.length <= 8),
      belowBarData: BarAreaData(show: emphasis, color: color.withValues(alpha: 0.08)),
    );

    final maxY = series.map((p) => p.total).fold<int>(0, (a, b) => a > b ? a : b);
    final step = series.length > 12 ? (series.length / 6).ceilToDouble() : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            _LegendItem(color: colors.total, label: 'Total'),
            _LegendItem(color: colors.completed, label: 'Completed'),
            _LegendItem(color: colors.cancelled, label: 'Cancelled'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY == 0 ? 1 : (maxY * 1.15).ceilToDouble(),
              lineBarsData: [
                line(colors.total, (p) => p.total, emphasis: true),
                line(colors.completed, (p) => p.completed),
                line(colors.cancelled, (p) => p.cancelled),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    // The top of the axis is padded headroom, not a grid
                    // step; its label would collide with the step below.
                    getTitlesWidget: (value, meta) => value == meta.max && value % meta.appliedInterval != 0
                        ? const SizedBox.shrink()
                        : SideTitleWidget(
                            meta: meta,
                            child: Text(meta.formattedValue, style: muted),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= series.length || value != i.toDouble()) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(label.format(series[i].bucket), style: muted),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s == spots.first ? '${DateFormat(range == KpiRange.last24h ? 'd MMM HH:mm' : 'E d MMM').format(series[s.x.round()].bucket)}\n' : ''}'
                        '${const ['Total', 'Completed', 'Cancelled'][s.barIndex]}: ${s.y.toInt()}',
                        TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
