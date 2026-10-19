import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../presentation/theme.dart';
import '../../presentation/formatters.dart';
import 'connectivity_cubit.dart';

/// Full-screen state while the API answers 503 MAINTENANCE. Sits on top of
/// the app (pages stay mounted underneath), keeps the session, shows the
/// server's message and how long it has lasted, and polls `/api/health`.
class MaintenanceView extends StatefulWidget {
  const MaintenanceView({super.key, required this.state, this.signedInAs});

  final ConnectivityState state;

  /// "Hamad Al-Marri · Dispatcher · Doha", when signed in.
  final String? signedInAs;

  @override
  State<MaintenanceView> createState() => _MaintenanceViewState();
}

class _MaintenanceViewState extends State<MaintenanceView> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint once a second for the "down for" and "next check" counters.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    final info = s.info;
    final now = DateTime.now();
    final planned = info?.isPlanned ?? false;
    final nextIn = s.nextCheckAt?.difference(now);
    final warning = OpsColors.of(context).warning;

    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(planned ? Icons.engineering : Icons.cloud_off, size: 64, color: warning),
                const SizedBox(height: 16),
                Text(
                  planned ? 'Scheduled maintenance' : 'The service is temporarily unavailable',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  info?.message ?? 'The API is under maintenance.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(spacing: 24, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  _Fact(
                    label: 'Down for',
                    value: s.since == null ? '—' : formatDuration(now.difference(s.since!)),
                  ),
                  _Fact(
                    label: 'Next check',
                    value: s.checking
                        ? 'checking…'
                        : nextIn == null
                            ? '—'
                            : 'in ${formatDuration(nextIn)}',
                  ),
                  if (info?.reason != null) _Fact(label: 'Reason', value: info!.reason!),
                ]),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: s.checking ? null : context.read<ConnectivityCubit>().checkNow,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check now'),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.signedInAs == null
                      ? 'This page reconnects by itself when the service is back.'
                      : 'You are still signed in as ${widget.signedInAs}. '
                          'Everything reconnects and refreshes by itself when the service is back.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]);
}

/// Slim strip for the lighter cases: offline / server not answering, or a
/// realtime connection retrying while the API itself is fine.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.icon, required this.text, required this.color, this.action});

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
            ?action,
          ]),
        ),
      );
}
