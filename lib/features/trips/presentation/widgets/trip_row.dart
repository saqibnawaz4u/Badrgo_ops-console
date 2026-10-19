import 'package:flutter/material.dart';

import '../../../../core/presentation/theme.dart';
import '../../../../core/presentation/formatters.dart';
import '../../domain/entities/trip.dart';
import '../../domain/usecases/trip_list_merger.dart';
import 'trip_status_chip.dart';

class TripRow extends StatelessWidget {
  const TripRow({super.key, required this.trip, required this.onTap, this.mark});

  final Trip trip;
  final RowMark? mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ops = OpsColors.of(context);
    final theme = Theme.of(context);
    final background = switch (mark) {
      RowMark.created => ops.created,
      RowMark.updated => ops.updated,
      null => Colors.transparent,
    };
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 860;
            final route = Text(
              '${trip.pickup.address}  →  ${trip.dropoff.address}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
            final people = Text(
              'Rider: ${trip.rider?.name ?? trip.riderId ?? '—'} · '
              'Driver: ${trip.driver?.name ?? (trip.driverId == null ? 'unassigned' : '…')}',
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
            final status = Row(mainAxisSize: MainAxisSize.min, children: [
              TripStatusChip(trip.status),
              if (mark != null) ...[
                const SizedBox(width: 6),
                mark == RowMark.created ? const RowMarkBadge.created() : const RowMarkBadge.updated(),
              ],
            ]);
            final fare = Text(formatMoney(trip.fare),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [status, const Spacer(), fare]),
                  const SizedBox(height: 6),
                  route,
                  const SizedBox(height: 2),
                  people,
                  Text('${formatDateTime(trip.requestedAt)} · ${trip.id}', style: muted),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 190, child: Align(alignment: Alignment.centerLeft, child: status)),
                SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDateTime(trip.requestedAt)),
                      Text(trip.cityName ?? '', style: muted),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [route, people],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 110, child: Align(alignment: Alignment.centerRight, child: fare)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class RowMarkBadge extends StatelessWidget {
  const RowMarkBadge.created({super.key}) : created = true;
  const RowMarkBadge.updated({super.key}) : created = false;

  final bool created;

  @override
  Widget build(BuildContext context) {
    final ops = OpsColors.of(context);
    final color = created ? ops.success : ops.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        created ? 'NEW' : 'UPDATED',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.surface,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
      ),
    );
  }
}
