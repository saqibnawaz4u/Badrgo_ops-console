import 'package:flutter/material.dart';

import '../../../../core/presentation/theme.dart';
import '../../domain/entities/trip.dart';

Color tripStatusColor(BuildContext context, TripStatus status) {
  final ops = OpsColors.of(context);
  return switch (status) {
    TripStatus.requested => ops.warning,
    TripStatus.assigned => ops.info,
    TripStatus.inProgress => ops.progress,
    TripStatus.completed => ops.success,
    TripStatus.cancelled => ops.danger,
  };
}

class TripStatusChip extends StatelessWidget {
  const TripStatusChip(this.status, {super.key});

  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final color = tripStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
