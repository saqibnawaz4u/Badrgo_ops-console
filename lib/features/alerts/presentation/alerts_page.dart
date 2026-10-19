import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/connectivity/presentation/refresh_on_recovery.dart';
import '../../../core/presentation/formatters.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../domain/entities/alert.dart';
import '../domain/repositories/alerts_repository.dart';
import 'bloc/alerts_feed_cubit.dart';
import 'widgets/alert_visuals.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        AlertsFeedCubit(context.read<AlertsRepository>(), permissions: context.read<AuthBloc>().state.user!.permissions)
          ..start(),
    child: Builder(
      builder: (context) => MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (a, b) => a.user?.permissions != b.user?.permissions && b.user != null,
            listener: (context, auth) => context.read<AlertsFeedCubit>().updatePermissions(auth.user!.permissions),
          ),
          BlocListener<AlertsFeedCubit, AlertsFeedState>(
            listenWhen: (a, b) => b.message != null && a.message != b.message,
            listener: (context, state) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!)));
              context.read<AlertsFeedCubit>().clearMessage();
            },
          ),
        ],
        child: RefreshOnRecovery(onRecovered: context.read<AlertsFeedCubit>().load, child: const _AlertsView()),
      ),
    ),
  );
}

class _AlertsView extends StatelessWidget {
  const _AlertsView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertsFeedCubit, AlertsFeedState>(
      builder: (context, state) {
        final cubit = context.read<AlertsFeedCubit>();
        Widget body;
        if (state.status == AlertsStatus.loading) {
          body = const LoadingView(label: 'Loading alerts…');
        } else if (state.status == AlertsStatus.failure) {
          body = ErrorView(message: state.error ?? 'Unknown error', onRetry: cubit.load);
        } else if (state.items.isEmpty) {
          body = MessageView(
            icon: Icons.notifications_none,
            title: state.openOnly ? 'No open alerts' : 'No alerts',
            message: 'New alerts appear here live.',
          );
        } else {
          body = Card(
            clipBehavior: Clip.antiAlias,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 300) cubit.loadMore();
                return false;
              },
              child: ListView.separated(
                itemCount: state.items.length + (state.hasNextPage ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  // Footer: scrolling near it loads the next page, but a short
                  // first page never scrolls, so it also offers a button.
                  if (i == state.items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: state.loadingMore
                            ? const CircularProgressIndicator()
                            : TextButton(onPressed: cubit.loadMore, child: const Text('Load more')),
                      ),
                    );
                  }
                  final alert = state.items[i];
                  return _AlertTile(
                    key: ValueKey(alert.id),
                    alert: alert,
                    fresh: state.freshIds.contains(alert.id),
                    canAcknowledge: state.canAcknowledge,
                    acknowledging: state.acknowledging.contains(alert.id),
                    onAcknowledge: () => cubit.acknowledge(alert),
                  );
                },
              ),
            ),
          );
        }
        return Padding(
          padding: pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Alerts',
                badge: state.status == AlertsStatus.ready
                    ? CountPill('${formatCount(state.totalCount)} ${state.openOnly ? 'open' : 'total'}')
                    : null,
                actions: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Open')),
                      ButtonSegment(value: false, label: Text('All')),
                    ],
                    selected: {state.openOnly},
                    onSelectionChanged: (s) => cubit.setOpenOnly(s.first),
                    showSelectedIcon: false,
                  ),
                  IconButton(tooltip: 'Reload', onPressed: cubit.load, icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    super.key,
    required this.alert,
    required this.fresh,
    required this.canAcknowledge,
    required this.acknowledging,
    required this.onAcknowledge,
  });

  final Alert alert;
  final bool fresh;
  final bool canAcknowledge;
  final bool acknowledging;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(context, alert.severity);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final compact = isCompact(context);
    final actions = Wrap(
      spacing: 8,
      children: [
        if (alert.tripId != null)
          TextButton(onPressed: () => context.go('/trips/${alert.tripId}'), child: const Text('Open trip')),
        if (alert.isOpen && canAcknowledge)
          FilledButton.tonal(
            onPressed: acknowledging ? null : onAcknowledge,
            child: acknowledging
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Acknowledge'),
          ),
        if (!alert.isOpen) Icon(Icons.check_circle, color: OpsColors.of(context).success),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: fresh && alert.isOpen ? OpsColors.of(context).created.withValues(alpha: 0.6) : null,
        // Open critical alerts carry a red edge so they stand out in a long list.
        border: alert.isOpen && alert.severity == AlertSeverity.critical
            ? Border(left: BorderSide(color: color, width: 4))
            : null,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(alertIcon(alert.type), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(alert.type.label, style: theme.textTheme.titleSmall?.copyWith(color: color)),
                    Text(alert.severity.name.toUpperCase(), style: muted),
                    if (fresh) Text('· live', style: muted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(alert.message),
                const SizedBox(height: 4),
                Text(
                  [
                    formatAgo(alert.createdAt),
                    if (alert.cityName != null) alert.cityName!,
                    if (alert.driverName != null) 'Driver ${alert.driverName}',
                    if (!alert.isOpen)
                      'Acknowledged ${formatAgo(alert.acknowledgedAt)}'
                          '${alert.acknowledgedBy != null ? ' by ${alert.acknowledgedBy}' : ''}',
                  ].join(' · '),
                  style: muted,
                ),
                // Phones: actions go under the text so it keeps the width.
                if (compact) ...[const SizedBox(height: 8), actions],
              ],
            ),
          ),
          if (!compact) ...[const SizedBox(width: 12), actions],
        ],
      ),
    );
  }
}
