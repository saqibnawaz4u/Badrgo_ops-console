import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/connectivity/presentation/connectivity_cubit.dart';
import '../../../core/connectivity/presentation/maintenance_view.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/presentation/theme_cubit.dart';
import '../../../core/presentation/widgets/brand_mark.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/realtime/live_status_cubit.dart';
import '../../../core/realtime/realtime_status.dart';
import '../../alerts/domain/repositories/alerts_repository.dart';
import '../../alerts/presentation/bloc/critical_alerts_cubit.dart';
import '../../alerts/presentation/widgets/critical_alert_banner.dart';
import '../../auth/domain/entities/current_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../domain/navigation_policy.dart';

IconData _iconFor(AppSection section) => switch (section) {
  AppSection.dashboard => Icons.space_dashboard_outlined,
  AppSection.trips => Icons.route_outlined,
  AppSection.liveMap => Icons.map_outlined,
  AppSection.alerts => Icons.notifications_outlined,
  AppSection.users => Icons.manage_accounts_outlined,
};

/// Signed-in frame: navigation built from permissions, the user's identity,
/// live-connection status and the app-wide banners (SOS, reconnecting,
/// offline). Keyed by user id in the router, so switching accounts rebuilds
/// it (and every bloc below it) from scratch.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.user, required this.location, required this.child});

  final CurrentUser user;
  final String location;
  final Widget child;

  static const policy = NavigationPolicy();

  @override
  Widget build(BuildContext context) {
    final destinations = policy.visibleFor(user.permissions);
    final current = policy.sectionFor(location);
    final selectedIndex = destinations.indexWhere((d) => d.section == current?.section);
    final canReadAlerts = user.permissions.can(Permission.alertRead);

    final scaffold = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final extended = constraints.maxWidth >= 1280;
        final body = Column(
          children: [
            if (canReadAlerts) const CriticalAlertBanner(),
            const _ConnectionStrip(),
            Expanded(child: child),
          ],
        );
        return Scaffold(
          appBar: _TopBar(user: user, showMenuButton: !wide),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        for (final (i, d) in destinations.indexed)
                          ListTile(
                            leading: Icon(_iconFor(d.section)),
                            title: Text(d.label),
                            selected: i == selectedIndex,
                            onTap: () {
                              Navigator.pop(context);
                              context.go(d.path);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          body: wide && destinations.length > 1
              ? Row(
                  children: [
                    NavigationRail(
                      extended: extended,
                      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
                      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                      onDestinationSelected: (i) => context.go(destinations[i].path),
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: d.section == AppSection.alerts && canReadAlerts
                                ? _AlertsIcon(icon: _iconFor(d.section))
                                : Icon(_iconFor(d.section)),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      },
    );

    if (!canReadAlerts) return scaffold;
    return BlocProvider(
      create: (context) =>
          CriticalAlertsCubit(context.read<AlertsRepository>(), permissions: user.permissions)..start(),
      child: BlocListener<AuthBloc, AuthState>(
        listenWhen: (a, b) => a.user?.permissions != b.user?.permissions && b.user != null,
        listener: (context, auth) => context.read<CriticalAlertsCubit>().updatePermissions(auth.user!.permissions),
        child: BlocSelector<CriticalAlertsCubit, CriticalAlertsState, int>(
          selector: (s) => s.open.length,
          builder: (context, openSos) => Title(
            // The browser tab shows open SOS alerts even when the console is
            // in a background tab.
            title: openSos > 0 ? '($openSos) SOS · badrgo Ops Console' : 'badrgo Ops Console',
            color: Theme.of(context).colorScheme.primary,
            child: scaffold,
          ),
        ),
      ),
    );
  }
}

class _AlertsIcon extends StatelessWidget {
  const _AlertsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => BlocSelector<CriticalAlertsCubit, CriticalAlertsState, int>(
    selector: (s) => s.open.length,
    builder: (context, count) => Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      backgroundColor: OpsColors.of(context).danger,
      child: Icon(icon),
    ),
  );
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.user, required this.showMenuButton});

  final CurrentUser user;
  final bool showMenuButton;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On phones the name, role and city move into the account menu.
    final compact = isCompact(context);
    return AppBar(
      toolbarHeight: 60,
      automaticallyImplyLeading: showMenuButton,
      titleSpacing: showMenuButton ? 0 : 16,
      title: Row(
        children: [
          BrandMark(size: 24, suffix: compact ? null : 'Ops'),
          const SizedBox(width: 16),
          const _LiveIndicator(),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Toggle dark mode',
          onPressed: () => context.read<ThemeCubit>().toggle(theme.brightness),
          icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Account',
          position: PopupMenuPosition.under,
          onSelected: (value) {
            if (value == 'sign-out') context.read<AuthBloc>().add(const AuthSignOutRequested());
          },
          itemBuilder: (context) => [
            if (compact)
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${user.roleLabel} · ${user.cityLabel}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            PopupMenuItem(enabled: false, child: Text(user.roleDescription, style: theme.textTheme.bodySmall)),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'sign-out',
              child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out')),
            ),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
            child: Row(
              children: [
                CircleAvatar(radius: 16, child: Text(user.name.isEmpty ? '?' : user.name[0])),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text('${user.roleLabel} · ${user.cityLabel}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) => BlocBuilder<LiveStatusCubit, LiveStatusState>(
    builder: (context, state) {
      final ops = OpsColors.of(context);
      final (label, color) = state.anyTroubled
          ? ('Reconnecting', ops.warning)
          : state.anyOpen
          ? ('Live', ops.success)
          : ('Connecting', ops.neutral);
      return Tooltip(
        message: 'Events (SSE): ${state.events.phase.name}\nDriver socket (WS): ${state.socket.phase.name}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
            ],
          ),
        ),
      );
    },
  );
}

/// The lighter states: realtime retrying while the API is up, or the
/// server not answering at all. Full maintenance is handled at the app root.
class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip();

  @override
  Widget build(BuildContext context) {
    final ops = OpsColors.of(context);
    final connectivity = context.watch<ConnectivityCubit>().state;
    if (connectivity.phase == ConnectivityPhase.unreachable) {
      return StatusStrip(
        icon: Icons.wifi_off,
        color: ops.danger,
        text: 'Offline: cannot reach the server. Retrying automatically; data on screen may be stale.',
        action: TextButton(
          onPressed: connectivity.checking ? null : context.read<ConnectivityCubit>().checkNow,
          child: const Text('Retry now'),
        ),
      );
    }
    final live = context.watch<LiveStatusCubit>().state;
    if (connectivity.isOnline && live.anyTroubled) {
      final which = [
        if (live.events.isTroubled) 'live events',
        if (live.socket.isTroubled) 'driver feed',
      ].join(' and ');
      final attempt = [
        live.events,
        live.socket,
      ].where((s) => s.phase == RealtimePhase.reconnecting).map((s) => s.attempt).fold(0, (a, b) => a > b ? a : b);
      return StatusStrip(
        icon: Icons.sync,
        color: ops.warning,
        text:
            'Reconnecting $which${attempt > 0 ? ' (attempt $attempt)' : ''}… missed events are replayed when we are back.',
      );
    }
    return const SizedBox.shrink();
  }
}
