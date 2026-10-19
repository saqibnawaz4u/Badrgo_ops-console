import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connectivity/data/health_repository_impl.dart';
import '../core/connectivity/presentation/connectivity_cubit.dart';
import '../core/network/graphql_client.dart';
import '../core/network/rest_client.dart';
import '../core/network/session_signals.dart';
import '../core/network/token_store.dart';
import '../core/presentation/theme_cubit.dart';
import '../core/realtime/live_status_cubit.dart';
import '../core/realtime/sse_client.dart';
import '../core/realtime/ws_client.dart';
import '../features/alerts/data/alerts_repository_impl.dart';
import '../features/alerts/domain/repositories/alerts_repository.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/dashboard/data/dashboard_repository_impl.dart';
import '../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../features/live_map/data/live_map_repository_impl.dart';
import '../features/live_map/domain/repositories/live_map_repository.dart';
import '../features/trips/data/trips_repository_impl.dart';
import '../features/trips/domain/repositories/trips_repository.dart';
import '../features/users/data/users_repository_impl.dart';
import '../features/users/domain/users.dart';
import 'config.dart';
import 'session_coordinator.dart';

/// Composition root: the only place that knows concrete classes. Widgets
/// receive repositories (by interface) and app-wide blocs from here.
class AppDependencies {
  AppDependencies._({
    required this.auth,
    required this.connectivity,
    required this.theme,
    required this.liveStatus,
    required this.coordinator,
    required this.trips,
    required this.dashboard,
    required this.alerts,
    required this.liveMap,
    required this.driverChat,
    required this.users,
  });

  final AuthBloc auth;
  final ConnectivityCubit connectivity;
  final ThemeCubit theme;
  final LiveStatusCubit liveStatus;
  final SessionCoordinator coordinator;
  final TripsRepository trips;
  final DashboardRepository dashboard;
  final AlertsRepository alerts;
  final LiveMapRepository liveMap;
  final DriverChatRepository driverChat;
  final UsersRepository users;

  static Future<AppDependencies> create(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final httpClient = http.Client();
    final tokens = TokenStore(prefs);
    final signals = SessionSignals();
    final rest = RestClient(baseUri: config.apiUri, httpClient: httpClient, tokens: tokens, signals: signals);
    final graphQL = GraphQLClient(rest);
    final authRepository = AuthRepositoryImpl(rest, tokens);

    // SSE and WS ask the coordinator before reconnecting; it is created
    // right after them.
    late final SessionCoordinator coordinator;
    final sse = SseClient(baseUri: config.apiUri, preflight: () => coordinator.preflight());
    final ws = WsClient(
      uriFor: config.webSocketUri,
      preflight: () => coordinator.preflight(),
      onUnauthorized: signals.reportUnauthorized,
      onForbidden: signals.reportForbidden,
    );

    final auth = AuthBloc(authRepository);
    final connectivity = ConnectivityCubit(HealthRepositoryImpl(baseUri: config.apiUri, httpClient: httpClient));
    coordinator = SessionCoordinator(
      auth: auth,
      authRepository: authRepository,
      connectivity: connectivity,
      signals: signals,
      sse: sse,
      ws: ws,
    )..start();

    return AppDependencies._(
      auth: auth,
      connectivity: connectivity,
      theme: ThemeCubit(prefs),
      liveStatus: LiveStatusCubit(events: sse, socket: ws),
      coordinator: coordinator,
      trips: TripsRepositoryImpl(graphQL: graphQL, rest: rest, events: sse),
      dashboard: DashboardRepositoryImpl(graphQL: graphQL, events: sse),
      alerts: AlertsRepositoryImpl(graphQL: graphQL, rest: rest, events: sse),
      liveMap: LiveMapRepositoryImpl(socket: ws, graphQL: graphQL),
      driverChat: DriverChatRepositoryImpl(socket: ws, rest: rest),
      users: UsersRepositoryImpl(rest),
    );
  }
}
