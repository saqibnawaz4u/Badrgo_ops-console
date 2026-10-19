import 'package:flutter/material.dart';

import '../../../../core/presentation/formatters.dart';
import '../../../../core/presentation/widgets/page_header.dart';
import '../../domain/entities/trip.dart';
import '../../domain/entities/trip_filter.dart';

class TripFiltersBar extends StatefulWidget {
  const TripFiltersBar({super.key, required this.filter, required this.onFilterChanged, required this.onSearchChanged});

  final TripFilter filter;
  final ValueChanged<TripFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  State<TripFiltersBar> createState() => _TripFiltersBarState();
}

class _TripFiltersBarState extends State<TripFiltersBar> {
  late final _search = TextEditingController(text: widget.filter.search);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final filter = widget.filter;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: filter.from == null ? null : DateTimeRange(start: filter.from!, end: filter.to ?? filter.from!),
    );
    if (range == null) return;
    _change(filter.copyWith(from: () => range.start, to: () => range.end));
  }

  /// A filter change cancels the bloc's pending (debounced) search, so send
  /// the text currently in the box along with it instead of the last applied
  /// search.
  void _change(TripFilter next) => widget.onFilterChanged(next.copyWith(search: _search.text));

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final hasRange = filter.from != null || filter.to != null;
    final search = TextField(
      controller: _search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Trip id, address or rider',
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _search.clear();
                  widget.onSearchChanged('');
                  setState(() {});
                },
              ),
      ),
      onChanged: (value) {
        setState(() {});
        widget.onSearchChanged(value);
      },
    );
    final controls = [
      for (final status in TripStatus.values)
        FilterChip(
          label: Text(status.label),
          selected: filter.statuses.contains(status),
          onSelected: (selected) => _change(
            filter.copyWith(statuses: selected ? {...filter.statuses, status} : ({...filter.statuses}..remove(status))),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _pickRange,
        icon: const Icon(Icons.date_range, size: 18),
        label: Text(hasRange ? '${formatDay(filter.from)} – ${formatDay(filter.to)}' : 'Any date'),
      ),
      if (hasRange)
        IconButton(
          tooltip: 'Clear dates',
          onPressed: () => _change(filter.copyWith(from: () => null, to: () => null)),
          icon: const Icon(Icons.event_busy),
        ),
      if (!filter.isEmpty)
        TextButton(
          onPressed: () {
            _search.clear();
            widget.onFilterChanged(const TripFilter());
          },
          child: const Text('Clear all'),
        ),
    ];

    // On phones the chips scroll sideways in one line instead of wrapping
    // into a block that pushes the list off screen.
    if (isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, control) in controls.indexed) ...[if (i > 0) const SizedBox(width: 8), control],
              ],
            ),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 280, child: search),
        ...controls,
      ],
    );
  }
}
