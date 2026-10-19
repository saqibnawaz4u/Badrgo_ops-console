import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/presentation/formatters.dart';
import '../../../core/realtime/realtime_status.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../domain/entities/driver.dart';
import '../domain/repositories/live_map_repository.dart';
import 'bloc/driver_chat_cubit.dart';
import 'bloc/live_map_cubit.dart';
import 'widgets/driver_chat_panel.dart';

Color driverStatusColor(BuildContext context, DriverStatus status) {
  final ops = OpsColors.of(context);
  return switch (status) {
    DriverStatus.available => ops.success,
    DriverStatus.onTrip => ops.info,
    DriverStatus.offline => ops.neutral,
  };
}

class LiveMapPage extends StatelessWidget {
  const LiveMapPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => LiveMapCubit(
          context.read<LiveMapRepository>(),
          permissions: context.read<AuthBloc>().state.user!.permissions,
        )..start(),
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.user?.permissions != b.user?.permissions && b.user != null,
          listener: (context, auth) => context.read<LiveMapCubit>().updatePermissions(auth.user!.permissions),
          child: const _LiveMapView(),
        ),
      );
}

class _LiveMapView extends StatelessWidget {
  const _LiveMapView();

  @override
  Widget build(BuildContext context) {
    final center = context.read<AuthBloc>().state.user?.city?.center;
    final initialCenter = center == null ? const LatLng(25.25, 51.5) : LatLng(center.lat, center.lng);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      return BlocBuilder<LiveMapCubit, LiveMapState>(
        builder: (context, state) {
          final map = Stack(children: [
            _DriverMap(initialCenter: initialCenter, zoom: center == null ? 10 : 11.5, state: state),
            Positioned(top: 12, left: 12, right: 12, child: _MapToolbar(state: state)),
            if (state.connection.isTroubled || (!state.connection.isOpen && !state.receivedFirstSnapshot))
              Positioned(bottom: 16, left: 0, right: 0, child: Center(child: _ConnectionOverlay(state: state))),
          ]);
          final panel = state.selected == null ? null : _DriverPanel(state: state);
          if (wide) {
            return Row(children: [
              Expanded(child: map),
              if (panel != null) SizedBox(width: 380, child: panel),
            ]);
          }
          return Column(children: [
            Expanded(child: map),
            if (panel != null) SizedBox(height: constraints.maxHeight * 0.5, child: panel),
          ]);
        },
      );
    });
  }
}

class _DriverMap extends StatelessWidget {
  const _DriverMap({required this.initialCenter, required this.zoom, required this.state});

  final LatLng initialCenter;
  final double zoom;
  final LiveMapState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LiveMapCubit>();
    final stale = state.connection.isTroubled;
    return FlutterMap(
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: zoom,
        onTap: (_, _) => cubit.clearSelection(),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.badrgo.ops_console',
        ),
        Opacity(
          opacity: stale ? 0.45 : 1,
          child: MarkerLayer(
            markers: [
              for (final d in state.visibleDrivers)
                Marker(
                  key: ValueKey(d.id),
                  point: LatLng(d.position.lat, d.position.lng),
                  width: 36,
                  height: 36,
                  child: _DriverMarker(
                    driver: d,
                    selected: state.selected?.id == d.id,
                    onTap: () => cubit.select(d.id),
                  ),
                ),
            ],
          ),
        ),
        const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
      ],
    );
  }
}

class _DriverMarker extends StatelessWidget {
  const _DriverMarker({required this.driver, required this.selected, required this.onTap});

  final DriverLocation driver;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = driverStatusColor(context, driver.status);
    return Tooltip(
      message: '${driver.name} · ${driver.status.label}',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: selected ? 4 : 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: selected ? 8 : 3),
              ],
            ),
            child: Transform.rotate(
              angle: (driver.heading ?? 0) * math.pi / 180,
              child: const Icon(Icons.navigation, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapToolbar extends StatelessWidget {
  const _MapToolbar({required this.state});

  final LiveMapState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LiveMapCubit>();
    final counts = state.counts;
    return Align(
      alignment: Alignment.topLeft,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Live drivers', style: Theme.of(context).textTheme.titleSmall),
              for (final s in [DriverStatus.available, DriverStatus.onTrip])
                FilterChip(
                  avatar: Icon(Icons.circle, size: 12, color: driverStatusColor(context, s)),
                  label: Text('${s.label} (${counts[s]})'),
                  selected: !state.hiddenStatuses.contains(s),
                  onSelected: (_) => cubit.toggleStatus(s),
                  showCheckmark: false,
                ),
              Text(
                state.lastSnapshotAt == null ? 'Waiting for first update…' : 'Updated ${formatTime(state.lastSnapshotAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionOverlay extends StatelessWidget {
  const _ConnectionOverlay({required this.state});

  final LiveMapState state;

  @override
  Widget build(BuildContext context) {
    final status = state.connection;
    final ops = OpsColors.of(context);
    final (text, color) = switch (status.phase) {
      RealtimePhase.reconnecting => (
          'Live driver feed dropped. Reconnecting (attempt ${status.attempt})… positions may be stale.',
          ops.warning,
        ),
      RealtimePhase.paused => ('Live driver feed paused until the server is back.', ops.warning),
      // The overlay is only shown while the feed is not open (see
      // _LiveMapView), so `open` just needs to keep the switch exhaustive.
      RealtimePhase.connecting || RealtimePhase.open => ('Connecting to the live driver feed…', ops.info),
      RealtimePhase.idle => ('Live driver feed is not connected.', ops.neutral),
    };
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
          const SizedBox(width: 12),
          Text(text),
        ]),
      ),
    );
  }
}

class _DriverPanel extends StatelessWidget {
  const _DriverPanel({required this.state});

  final LiveMapState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LiveMapCubit>();
    final selected = state.selected!;
    final details = selected.details;
    final theme = Theme.of(context);
    Widget body;
    if (selected.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (selected.error != null) {
      body = Center(child: Text(selected.error!));
    } else {
      final d = details!;
      final trip = d.currentTrip;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.circle, size: 12, color: driverStatusColor(context, d.status)),
                const SizedBox(width: 6),
                Text(d.status.label),
                const Spacer(),
                if (d.rating != null) Text('★ ${d.rating!.toStringAsFixed(2)}'),
              ]),
              const SizedBox(height: 8),
              if (d.phone != null) SelectableText(d.phone!),
              if (d.vehicle != null) Text(d.vehicle!.label),
              Text('${d.cityName ?? ''} · last seen ${formatAgo(d.lastSeenAt)}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Text('Current trip', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (trip == null)
                const Text('No active trip.')
              else
                Card(
                  child: ListTile(
                    title: Text('${trip.pickup} → ${trip.dropoff}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${trip.status.replaceAll('_', ' ').toLowerCase()}'
                        '${trip.riderName != null ? ' · ${trip.riderName}' : ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/trips/${trip.id}'),
                  ),
                ),
            ]),
          ),
          if (state.canMessage) ...[
            const Divider(height: 1),
            Expanded(
              child: BlocProvider(
                key: ValueKey(d.id),
                create: (context) =>
                    DriverChatCubit(context.read<DriverChatRepository>(), driverId: d.id)..start(),
                child: DriverChatPanel(driverOffline: d.status == DriverStatus.offline),
              ),
            ),
          ],
        ],
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: Column(children: [
        ListTile(
          title: Text(details?.name ?? 'Driver', style: theme.textTheme.titleMedium),
          trailing: IconButton(tooltip: 'Close', onPressed: cubit.clearSelection, icon: const Icon(Icons.close)),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ]),
    );
  }
}
