import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/permissions/permissions.dart';
import '../core/presentation/widgets/state_views.dart';
import '../features/alerts/presentation/alerts_page.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/auth/presentation/sign_in_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/live_map/presentation/live_map_page.dart';
import '../features/shell/domain/navigation_policy.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/shell/presentation/permission_gate.dart';
import '../features/trips/presentation/trip_detail_page.dart';
import '../features/trips/presentation/trips_page.dart';
import '../features/users/presentation/users_page.dart';

/// Routes and the auth redirect. Access to each section is decided by the
/// [PermissionGate] inside the route (so a forbidden URL renders a proper
/// "no access" page instead of silently bouncing).
///
/// [refresh] re-runs the redirect; the caller owns and disposes it (usually
/// a [StreamListenable] over `auth.stream`).
GoRouter buildRouter(
  AuthBloc auth, {
  required Listenable refresh,
  NavigationPolicy policy = const NavigationPolicy(),
}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = auth.state.status;
      final location = state.uri.toString();
      final path = state.uri.path;

      if (status == AuthStatus.unknown) {
        return path == '/loading' ? null : '/loading?from=${Uri.encodeComponent(location)}';
      }
      if (status == AuthStatus.unauthenticated) {
        if (path == '/sign-in') return null;
        final from = _safeFrom(path == '/loading' ? state.uri.queryParameters['from'] : location);
        return from == null ? '/sign-in' : '/sign-in?from=${Uri.encodeComponent(from)}';
      }
      // Signed in.
      if (path == '/sign-in' || path == '/loading' || path == '/') {
        final from = _safeFrom(state.uri.queryParameters['from']);
        if (from != null) return from;
        return policy.homePathFor(auth.state.user!.permissions) ?? '/no-access';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInPage()),
      GoRoute(
        path: '/loading',
        // A non-network restore failure (e.g. a 500) leaves a notice and
        // nothing retries on its own, so offer it here.
        builder: (_, _) => Scaffold(
          body: BlocBuilder<AuthBloc, AuthState>(
            bloc: auth,
            builder: (context, state) => state.restorePending && state.notice != null
                ? MessageView(
                    icon: Icons.cloud_off,
                    title: 'Could not restore your session',
                    message: state.notice,
                    action: FilledButton.tonalIcon(
                      onPressed: () => auth.add(const AuthRestoreRetried()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  )
                : const LoadingView(label: 'Restoring your session…'),
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final user = auth.state.user;
          if (user == null) return const SizedBox.shrink();
          return AppShell(
            key: ValueKey('shell-${user.id}'),
            user: user,
            location: state.uri.path,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const PermissionGate(required: Permission.kpiRead, child: DashboardPage()),
          ),
          GoRoute(
            path: '/trips',
            builder: (_, _) => const PermissionGate(required: Permission.tripRead, child: TripsPage()),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => PermissionGate(
                  required: Permission.tripRead,
                  child: TripDetailPage(tripId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/map',
            builder: (_, _) => const PermissionGate(required: Permission.driverTrack, child: LiveMapPage()),
          ),
          GoRoute(
            path: '/alerts',
            builder: (_, _) => const PermissionGate(required: Permission.alertRead, child: AlertsPage()),
          ),
          GoRoute(
            path: '/users',
            builder: (_, _) => const PermissionGate(required: Permission.userList, child: UsersPage()),
          ),
          GoRoute(
            path: '/no-access',
            builder: (_, _) => const MessageView(
              icon: Icons.lock_outline,
              title: 'Nothing to show yet',
              message: 'Your role has no sections enabled. Ask an administrator for access.',
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: NotFoundView(
        title: 'Page not found',
        message: 'There is nothing at ${state.uri.path}.',
        action: FilledButton.tonal(onPressed: () => context.go('/'), child: const Text('Go home')),
      ),
    ),
  );
}

/// Only same-app paths, never back to the auth screens.
String? _safeFrom(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) return null;
  final path = Uri.tryParse(from)?.path ?? '';
  if (path == '/' || path == '/sign-in' || path == '/loading') return null;
  return from;
}

/// Notifies on every stream event (the router's refresh signal).
class StreamListenable extends ChangeNotifier {
  StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
