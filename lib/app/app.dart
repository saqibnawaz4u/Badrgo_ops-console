import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/connectivity/presentation/connectivity_cubit.dart';
import '../core/connectivity/presentation/maintenance_view.dart';
import '../core/presentation/theme_cubit.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../core/presentation/theme.dart';
import 'di.dart';
import 'router.dart';

class OpsConsoleApp extends StatefulWidget {
  const OpsConsoleApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<OpsConsoleApp> createState() => _OpsConsoleAppState();
}

class _OpsConsoleAppState extends State<OpsConsoleApp> {
  late final StreamListenable _authRefresh = StreamListenable(widget.deps.auth.stream);
  late final GoRouter _router = buildRouter(widget.deps.auth, refresh: _authRefresh);

  @override
  void dispose() {
    _router.dispose();
    _authRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.deps;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: deps.trips),
        RepositoryProvider.value(value: deps.dashboard),
        RepositoryProvider.value(value: deps.alerts),
        RepositoryProvider.value(value: deps.liveMap),
        RepositoryProvider.value(value: deps.driverChat),
        RepositoryProvider.value(value: deps.users),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: deps.auth),
          BlocProvider.value(value: deps.connectivity),
          BlocProvider.value(value: deps.theme),
          BlocProvider.value(value: deps.liveStatus),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, mode) => MaterialApp.router(
            title: 'badrgo Ops Console',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            routerConfig: _router,
            builder: (context, child) => _MaintenanceGate(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

/// During maintenance the whole app is covered by [MaintenanceView]. The
/// router and its pages stay mounted underneath, so nothing is lost and the
/// session is kept.
class _MaintenanceGate extends StatelessWidget {
  const _MaintenanceGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BlocBuilder<ConnectivityCubit, ConnectivityState>(
        builder: (context, state) {
          final maintenance = state.phase == ConnectivityPhase.maintenance;
          final user = context.select((AuthBloc b) => b.state.user);
          return Stack(children: [
            ExcludeFocus(excluding: maintenance, child: child),
            if (maintenance)
              Positioned.fill(
                child: MaintenanceView(
                  state: state,
                  signedInAs: user == null ? null : '${user.name} · ${user.roleLabel} · ${user.cityLabel}',
                ),
              ),
          ]);
        },
      );
}
