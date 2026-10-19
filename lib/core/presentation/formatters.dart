import 'package:intl/intl.dart';

import '../domain/shared_entities.dart';

final _amount = NumberFormat('#,##0.00');
final _count = NumberFormat.decimalPattern();
final _dateTime = DateFormat('d MMM, HH:mm');
final _time = DateFormat('HH:mm:ss');
final _day = DateFormat('d MMM yyyy');

String formatMoney(Money money) => '${money.currency} ${_amount.format(money.amount)}'.trim();

/// Revenue and similar totals come as one entry per currency.
List<String> formatMoneyList(List<Money> values) =>
    values.isEmpty ? const ['—'] : [for (final m in values) formatMoney(m)];

String formatCount(num value) => _count.format(value);

String formatPercent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

String formatDateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value);

String formatTime(DateTime? value) => value == null ? '—' : _time.format(value);

String formatDay(DateTime? value) => value == null ? '—' : _day.format(value);

String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String formatAgo(DateTime? value, {DateTime? now}) {
  if (value == null) return '—';
  final diff = (now ?? DateTime.now()).difference(value);
  if (diff.inSeconds < 10) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return formatDateTime(value);
}
