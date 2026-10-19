import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/connectivity/presentation/refresh_on_recovery.dart';
import '../../../core/presentation/formatters.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/trips_repository.dart';
import 'bloc/trip_detail_cubit.dart';
import 'widgets/trip_action_dialogs.dart';
import 'widgets/trip_status_chip.dart';

class TripDetailPage extends StatelessWidget {
  const TripDetailPage({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        key: ValueKey(tripId),
        create: (context) => TripDetailCubit(
          context.read<TripsRepository>(),
          tripId: tripId,
          permissions: context.read<AuthBloc>().state.user!.permissions,
        )..start(),
        child: Builder(
          builder: (context) => MultiBlocListener(
            listeners: [
              // An admin may change our role while we look at the trip.
              BlocListener<AuthBloc, AuthState>(
                listenWhen: (a, b) => a.user?.permissions != b.user?.permissions && b.user != null,
                listener: (context, auth) =>
                    context.read<TripDetailCubit>().updatePermissions(auth.user!.permissions),
              ),
            ],
            child: RefreshOnRecovery(
              onRecovered: () => context.read<TripDetailCubit>().load(quiet: true),
              child: const _TripDetailView(),
            ),
          ),
        ),
      );
}

class _TripDetailView extends StatelessWidget {
  const _TripDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripDetailCubit, TripDetailState>(
      builder: (context, state) {
        final cubit = context.read<TripDetailCubit>();
        switch (state.status) {
          case DetailStatus.loading when state.trip == null:
            return const LoadingView(label: 'Loading trip…');
          case DetailStatus.notFound:
            return NotFoundView(
              title: 'Trip not found',
              message: 'Trip ${cubit.tripId} does not exist, or it belongs to a city you '
                  'cannot see.',
              action: FilledButton.tonal(
                onPressed: () => context.go('/trips'),
                child: const Text('Back to trips'),
              ),
            );
          case DetailStatus.failure when state.trip == null:
            return ErrorView(message: state.error ?? 'Unknown error', onRetry: cubit.load);
          default:
            break;
        }
        final trip = state.trip!;
        return ListView(
          padding: pagePadding(context, top: 24, bottom: 24),
          children: [
            _Header(trip: trip, state: state),
            if (state.banner != null) ...[
              const SizedBox(height: 16),
              _Banner(
                message: state.banner!,
                conflict: state.bannerIsConflict,
                onClose: cubit.dismissBanner,
              ),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 900 ? 2 : 1;
              final cards = [
                _RouteCard(trip: trip),
                _FareCard(trip: trip),
                _PersonCard(
                  title: 'Rider',
                  icon: Icons.person_outline,
                  name: trip.rider?.name,
                  lines: [
                    if (trip.rider?.phone != null) trip.rider!.phone!,
                    if (trip.rider?.email != null) trip.rider!.email!,
                    if (trip.rider?.rating != null) 'Rating ${trip.rider!.rating!.toStringAsFixed(2)}',
                  ],
                ),
                _PersonCard(
                  title: 'Driver',
                  icon: Icons.local_taxi_outlined,
                  name: trip.driver?.name,
                  emptyText: 'No driver assigned yet',
                  lines: [
                    if (trip.driver?.phone != null) trip.driver!.phone!,
                    if (trip.driver?.vehicle != null) trip.driver!.vehicle!.label,
                    if (trip.driver?.rating != null) 'Rating ${trip.driver!.rating!.toStringAsFixed(2)}',
                  ],
                ),
                _TimelineCard(trip: trip),
              ];
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: columns == 1
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 2,
                      child: card,
                    ),
                ],
              );
            }),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.trip, required this.state});

  final Trip trip;
  final TripDetailState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripDetailCubit>();
    final theme = Theme.of(context);
    final actions = state.actions;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Back to trips',
              onPressed: () => context.go('/trips'),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Trip', style: theme.textTheme.headlineSmall),
                  const SizedBox(width: 12),
                  TripStatusChip(trip.status),
                  if (state.status == DetailStatus.loading || state.busy) ...[
                    const SizedBox(width: 12),
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ]),
                SelectableText(
                  '${trip.id} · ${trip.cityName ?? trip.cityId ?? ''} · requested ${formatDateTime(trip.requestedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        if (actions.any)
          Wrap(spacing: 8, children: [
            if (actions.canAssign)
              FilledButton.icon(
                onPressed: state.busy ? null : () => showAssignDriverDialog(context, cubit),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(trip.driverId == null ? 'Assign driver' : 'Reassign driver'),
              ),
            if (actions.canRefund)
              FilledButton.tonalIcon(
                onPressed: state.busy ? null : () => showRefundDialog(context, cubit),
                icon: const Icon(Icons.currency_exchange),
                label: const Text('Refund'),
              ),
            if (actions.canCancel)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: state.busy ? null : () => showCancelTripDialog(context, cubit),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel trip'),
              ),
          ]),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.conflict, required this.onClose});

  final String message;
  final bool conflict;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ops = OpsColors.of(context);
    final color = conflict ? ops.warning : ops.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Icon(conflict ? Icons.sync_problem : Icons.bolt, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Dismiss'),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ]),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: emphasis ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Route',
        icon: Icons.route,
        child: Column(children: [
          _KeyValue('Pickup', trip.pickup.address),
          _KeyValue('Dropoff', trip.dropoff.address),
          _KeyValue('Distance', trip.distanceKm == null ? '—' : '${trip.distanceKm!.toStringAsFixed(1)} km'),
          if (trip.cancelReason != null)
            _KeyValue('Cancelled', '${trip.cancelReason} (by ${trip.cancelledBy ?? 'unknown'})'),
        ]),
      );
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: 'Fare and refunds',
        icon: Icons.payments_outlined,
        child: Column(children: [
          _KeyValue('Fare', formatMoney(trip.fare), emphasis: true),
          _KeyValue('Refunded', formatMoney(trip.refunded)),
          if (trip.status == TripStatus.completed)
            _KeyValue('Refundable', formatMoney(trip.refundable)),
          if (trip.refundReason != null) _KeyValue('Last refund reason', trip.refundReason!),
        ]),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.title,
    required this.icon,
    required this.name,
    required this.lines,
    this.emptyText = '—',
  });

  final String title;
  final IconData icon;
  final String? name;
  final List<String> lines;
  final String emptyText;

  @override
  Widget build(BuildContext context) => _SectionCard(
        title: title,
        icon: icon,
        child: name == null
            ? Text(emptyText, style: Theme.of(context).textTheme.bodyMedium)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name!, style: Theme.of(context).textTheme.titleMedium),
                  for (final line in lines) SelectableText(line),
                ],
              ),
      );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final entries = trip.timeline;
    return _SectionCard(
      title: 'Status timeline',
      icon: Icons.timeline,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [
                  Icon(Icons.circle, size: 12, color: tripStatusColor(context, entries[i].status)),
                  if (i < entries.length - 1)
                    Container(width: 2, height: 26, color: Theme.of(context).colorScheme.outlineVariant),
                ]),
                const SizedBox(width: 12),
                Expanded(child: Text(entries[i].status.label)),
                Text(formatDateTime(entries[i].at), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
