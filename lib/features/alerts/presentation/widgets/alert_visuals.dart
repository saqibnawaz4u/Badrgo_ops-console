import 'package:flutter/material.dart';

import '../../../../core/presentation/theme.dart';
import '../../domain/entities/alert.dart';

Color severityColor(BuildContext context, AlertSeverity severity) {
  final ops = OpsColors.of(context);
  return switch (severity) {
    AlertSeverity.critical => ops.danger,
    AlertSeverity.warning => ops.warning,
    AlertSeverity.info => ops.info,
  };
}

IconData alertIcon(AlertType type) => switch (type) {
      AlertType.sos => Icons.sos,
      AlertType.highDemand => Icons.trending_up,
      AlertType.noDriverAvailable => Icons.no_crash_outlined,
      AlertType.refundIssued => Icons.currency_exchange,
      AlertType.other => Icons.notifications_outlined,
    };
