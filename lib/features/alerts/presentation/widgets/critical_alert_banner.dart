import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/presentation/theme.dart';
import '../../../../core/presentation/formatters.dart';
import '../../../../core/presentation/widgets/page_header.dart';
import '../bloc/critical_alerts_cubit.dart';

/// Red strip pinned above every page while an SOS is open. It pulses when
/// a new one arrives and stays until acknowledged or hidden.
class CriticalAlertBanner extends StatefulWidget {
  const CriticalAlertBanner({super.key});

  @override
  State<CriticalAlertBanner> createState() => _CriticalAlertBannerState();
}

class _CriticalAlertBannerState extends State<CriticalAlertBanner> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  Timer? _pulseEnd;

  @override
  void dispose() {
    _pulseEnd?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// A new arrival restarts the 4 s window. reset() (not stop()) so the
  /// strip goes back to its normal red instead of freezing mid-pulse.
  void _startPulse() {
    _pulseEnd?.cancel();
    _pulse.repeat(reverse: true);
    _pulseEnd = Timer(const Duration(seconds: 4), _pulse.reset);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CriticalAlertsCubit, CriticalAlertsState>(
      listenWhen: (a, b) => a.lastArrivalAt != b.lastArrivalAt || (b.message != null && a.message != b.message),
      listener: (context, state) {
        if (state.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!)));
          context.read<CriticalAlertsCubit>().clearMessage();
        } else {
          _startPulse();
        }
      },
      builder: (context, state) {
        final visible = state.visible;
        if (visible.isEmpty) return const SizedBox.shrink();
        final cubit = context.read<CriticalAlertsCubit>();
        final alert = visible.first;
        final danger = OpsColors.of(context).danger;
        const onDanger = Colors.white;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Container(
            color: Color.lerp(danger, Colors.black, _pulse.value * 0.35),
            child: child,
          ),
          child: Semantics(
            liveRegion: true,
            label: 'Critical alert',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Builder(builder: (context) {
                final message = Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: visible.length == 1 ? 'SOS  ' : '${visible.length} open SOS  ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: '${alert.message} (${formatAgo(alert.createdAt)})'),
                    ]),
                    style: const TextStyle(color: onDanger),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
                final buttons = [
                  if (alert.tripId != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: onDanger),
                      onPressed: () => context.go('/trips/${alert.tripId}'),
                      child: const Text('Open trip'),
                    ),
                  if (state.canAcknowledge)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: onDanger, foregroundColor: danger),
                      onPressed: () => cubit.acknowledge(alert),
                      child: const Text('Acknowledge'),
                    ),
                ];
                final hide = IconButton(
                  tooltip: 'Hide (stays open in Alerts)',
                  color: onDanger,
                  onPressed: () => cubit.hide(alert.id),
                  icon: const Icon(Icons.close),
                );
                const icon = Icon(Icons.sos, color: onDanger);

                // Phones: buttons go on their own line so the message keeps
                // the width.
                if (isCompact(context)) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(children: [icon, const SizedBox(width: 12), message, hide]),
                    if (buttons.isNotEmpty) Wrap(spacing: 8, children: buttons),
                  ]);
                }
                return Row(children: [
                  icon,
                  const SizedBox(width: 12),
                  message,
                  const SizedBox(width: 8),
                  ...buttons,
                  hide,
                ]);
              }),
            ),
          ),
        );
      },
    );
  }
}
