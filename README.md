# badrgo Ops Console

A Flutter web dashboard for the badrgo city operations team (Doha, Al Rayyan, Al Wakrah), built on the hosted sandbox API. It uses REST, GraphQL, Server-Sent Events and WebSocket. Every screen, route and button is driven by the permissions in `GET /api/me`.

## Run it

Requirements: Flutter stable 3.x with web support, and Chrome.

```bash
flutter pub get
flutter run -d chrome --dart-define=API_URL=https://sandbox.badrgo.com
```

`API_URL` defaults to `https://sandbox.badrgo.com`, so you can leave out the `--dart-define`. The WebSocket URL is derived from it (`https` becomes `wss`, plus `/ws`).

Sign in with any demo account, using the password from the assessment brief. The sign-in screen has a "Sandbox demo accounts" list that fills in the email for you. No password is stored in the repo.

```bash
flutter test      # 92 tests: permissions, navigation, transports, trip rules, live lists, role-based widget tests
flutter analyze
```

> **Windows note:** if the project or Flutter SDK path contains a space (for example `C:\Users\New Moon\...`), the `objective_c` native-assets hook (pulled in by `shared_preferences`) fails to build. Run from the 8.3 short path instead, for example `C:\Users\NEWMOO~1\...`, with `PUB_CACHE` pointing at the short path too.

## What is built

| | Status |
|---|---|
| M1 Authentication | Done |
| M2 Role-aware shell | Done |
| M3 Dashboard | Done |
| M4 Trips | Done |
| M5 Live map | Done |
| M6 Alerts | Done |
| M7 Maintenance and connectivity | Done |
| B1 Driver chat | Done |
| B2 User admin | Done |
| B4 Smart reconnection (SSE resume and offline banner) | Done |
| B6 Responsive and dark mode | Done |
| B8 More tests | Partly: widget tests per role (trip actions, user admin), transport and realtime unit tests |
| B3, B5, B7 | Not done |

## Architecture

Clean MVVM with BLoC, organised by feature. Dependencies point inward: **View → ViewModel → Domain ← Data**.

```
lib/
  app/            composition root: DI, router, SessionCoordinator, config
  core/
    network/      RestClient, GraphQLClient, TokenStore, SessionSignals
    realtime/     SseClient (EventSource), WsClient (WebSocket), Backoff, LiveStatusCubit
    connectivity/ HealthRepository, ConnectivityCubit, maintenance view
    permissions/  Permission, Permissions (the /api/me map)
    presentation/ theme, formatters, shared state views
  features/<feature>/
    domain/       entities, repository interfaces, use cases (pure Dart)
    data/         repository implementations and DTO mapping (the only place that touches a transport)
    presentation/
      bloc/       Cubits and Blocs: UI state and permission checks
      *.dart      widgets: render state, send events, no logic and no API calls
```

Features: `auth`, `shell`, `dashboard`, `trips`, `live_map`, `alerts`, `users`.

### Which transport does what

| Transport | Used for | Where |
|---|---|---|
| REST | Sign-in and sign-out, `GET /api/me`, every write (assign, cancel, refund, acknowledge, user admin), chat history | `RestClient` |
| GraphQL | Dashboard KPIs and series, the trip list (cursor based), trip detail with nested rider, driver and city, available drivers | `GraphQLClient` (a thin POST over `RestClient`) |
| SSE `/api/events` | Live KPI tiles (`kpi`), the alerts feed, live trip list and trip detail updates | `SseClient` |
| WebSocket `/ws` | `drivers.locations` for the map, `driver.messages` and `driver.message.send` for chat | `WsClient` |

### Session, 401 and 403: one coordinator

Every transport reports problems to `SessionSignals`. `SessionCoordinator` (in `lib/app/`) is the only place that reacts to them:

- **401 from any transport** fires `AuthSessionExpired`. Realtime connections close and the router sends the user to sign-in. Realtime clients never reconnect on their own after a 401: their preflight sees it and stops. A 401 is only acted on if it was sent with the current token, so a late response from a previous session cannot sign the next user out. WebSocket close code 4001 is treated the same.
- **403** re-fetches `/api/me` (debounced). If an admin changed the role, the permissions change, the shell rebuilds its navigation, open pages lock themselves through `PermissionGate`, and SSE and WebSocket reopen with the new topics.
- **Ban or idle role change:** while signed in, `/api/me` is re-checked every 30 s. The API keeps already-open realtime connections alive after a ban (see API feedback), so this is what signs a banned user out even when they only watch live data.
- **Account switch:** the shell is keyed by user id, so every page Bloc is rebuilt. `SseClient.start()` and `WsClient.start()` always close the previous connection first, so there are no duplicate subscriptions and no leaked listeners.

### Realtime lifecycle

- **SSE:** browser `EventSource` from `package:web`, with `?token=` and `?topics=` (only the topics the user's permissions allow). `EventSource` cannot read the HTTP status, so on any error we close it, run a REST preflight (`GET /api/me`) to learn whether this is a 401, maintenance or a plain drop, and only then reconnect with backoff. We keep the last event `id` and reconnect with `?lastEventId=`, so the server replays missed events. `ready.deniedTopics` is read; support simply does not get KPI tiles.
- **WebSocket:** `web_socket_channel`. Channels are reference counted: subscribe on the first listener, subscribe again after every `welcome`, unsubscribe when the last listener leaves. Pings every 25 s. Reconnect with backoff after the same REST preflight.
- **Status UI:** a "Live / Reconnecting / Connecting" pill in the top bar, a lighter "Reconnecting live events (attempt n)…" strip under it, and a reconnecting overlay on the map.

### Maintenance (M7)

A 503 `MAINTENANCE` from any transport puts `ConnectivityCubit` in maintenance. The app shows a full-page maintenance state with the server's `message`, the reason (planned or unavailable) and how long it has lasted, based on `since`. The user stays signed in.

`/api/health` is polled with backoff, starting from `Retry-After` and capped at 30 s. A "Check now" button is also offered. When the API is back, SSE and WebSocket resume and every visible page refreshes its data through `RefreshOnRecovery`.

A dropped realtime connection while the API is up is a different case: it only shows the light reconnecting strip. No answer from the server at all shows a red "Offline" strip.

### Permission-driven UI

- `NavigationPolicy` maps each section to the permission that unlocks it. The shell, the router's home redirect and the SSE topic list all read from it.
- A URL the user may not open renders a "No access" page (`PermissionGate`), not a redirect or a crash.
- Trip actions come from `TripActions.resolve(trip, permissions)`, which checks both the permission and whether the trip's status allows it. The server still has the final say.
- No code branches on the role name. The role is only shown as a label in the top bar.

### Trips: live list without jank

`TripListMerger` (pure functions, unit tested) applies `trip.created` and `trip.updated` to the loaded, filtered list:

- New trips that match the filter are inserted newest-first and marked **NEW**.
- Updated rows are changed in place and marked **UPDATED**. Marks clear after 8 seconds.
- Updates for rows that are not loaded are ignored, so the list never jumps while someone reads it.
- SSE payloads carry ids only. Missing rider and driver names are fetched in one batched GraphQL query using aliases.
- When a search is active and only the rider name could match, the trip is held until the names arrive, then inserted only if it matches.
- Loading the next page skips rows already present, because live inserts shift offsets.

**409 INVALID_STATE:** the dialog closes and a banner shows the server's message plus "The trip has been refreshed to show its current state.", then the trip reloads. A 422 `VALIDATION_FAILED` stays in the dialog, with the server's field errors under the matching field. The refund amount is checked against `fare − refunded` before sending.

### Critical alerts

An open SOS shows a red banner above every page, with Open trip, Acknowledge (if permitted) and Hide. The banner pulses when a new one arrives. The browser tab title shows `(3) SOS`, so it is noticed even in a background tab. The Alerts item in the navigation has a badge.

## Branding

Colours and type follow [badrgo.com](https://badrgo.com/qa/) and the official logo (`assets/brand/badrgo_logo.svg`, rendered with `flutter_svg`): brand red `#CE0E2D` for primary actions, selection and the logo, neutral greys for text and surfaces, and Clash Grotesk for headings. Status colours stay semantic (in-progress trips are violet, not red), because red in an operations console means an error or an SOS.

Clash Grotesk's licence (ITF Free Font License) does not allow putting the font files in a repository, so they are not committed. `BrandFont.load` fetches them from Fontshare's own servers at start-up, which the licence allows. If that fails (offline or blocked), headings fall back to the default font and the app works the same.

## Package choices

| Package | Why |
|---|---|
| `flutter_bloc` / `bloc` | Required. Cubits for most screens, a Bloc where events matter (auth, trip list). |
| `go_router` | Declarative routes, a redirect hook for the auth state, clean path URLs (`usePathUrlStrategy`) so `/trips/trp_123` can be shared and reloaded. |
| `package:web` `EventSource` | The browser's native SSE: streaming without buffering issues, and `id:` tracking. We disable its own blind retry and run ours so we can tell a 401 from maintenance from a drop. |
| `web_socket_channel` | Standard and works on web. Wrapped behind a connector so it can be faked in tests. |
| `http` | Small. GraphQL is a single POST, so a full GraphQL client (ferry, graphql_flutter) would add codegen and caching we did not need. |
| `flutter_map` + OpenStreetMap tiles | No API key needed. Markers are replaced on every snapshot (the API sends full snapshots, not deltas). |
| `fl_chart` | Line chart for the trips series. |
| `shared_preferences` | Persists the session token, so a page refresh keeps the user signed in. |
| `flutter_svg` | Renders the official badrgo logo from its SVG, sharp at every size and recoloured white on the red panel. |
| `mocktail`, `bloc_test` | Repository and Bloc fakes in widget tests. |

## Tests

92 tests in total.

```
test/core/permissions_test.dart                  parsing, wildcard, order-independent equality
test/core/rest_client_test.dart                  timeout -> network failure signal; 503 (even HTML) -> maintenance signal
test/core/health_repository_test.dart            /api/health: up, maintenance (JSON or not), unreachable
test/core/connectivity_cubit_test.dart           health polling honours Retry-After, clamped
test/core/backoff_test.dart                      delays never exceed the cap, even with jitter
test/core/ws_client_test.dart                    no pong -> reconnect through preflight; pongs -> stays open
test/core/theme_test.dart                        OpsColors lerp/copyWith, ThemeCubit.setMode
test/features/shell/navigation_policy_test.dart  sections, routes, SSE topics and WebSocket per role
test/features/auth/restore_loading_route_test.dart  failed restore shows the notice and "Try again"
test/features/users/users_page_actions_test.dart widget test: user admin buttons follow user:create/set-role/ban; ban dialog closes cleanly
test/features/users/users_cubit_test.dart        a stale page response cannot overwrite a newer one
test/features/trips/trip_rules_test.dart         which actions each role gets per trip status; refund validation
test/features/trips/trip_list_merger_test.dart   live insert, update and removal, filters, hydration, pagination
test/features/trips/trips_list_bloc_test.dart    events during a load are replayed; stale search cancelled; hydration retry
test/features/trips/trip_detail_cubit_test.dart  own-write echo suppression by change kind; unexpected errors reset busy
test/features/trips/trip_detail_actions_test.dart  widget test: the real trip page per role
test/features/dashboard/dashboard_test.dart      stale chart ranges ignored, chart retry, refresh notice, Live vs Snapshot
test/features/alerts/alerts_acknowledge_test.dart  acknowledge updates the feed at once; SSE echo is idempotent
test/features/live_map/driver_chat_panel_test.dart  sending is disabled for offline drivers
```

The fixtures in `test/fixtures/roles.dart` are the exact `permissions` maps the sandbox returned for each demo account. The tests check real role behaviour, not guessed roles.

The widget test renders the real `TripDetailPage` with a mocked repository:
- **dispatcher** sees "Assign driver" and "Cancel trip".
- **support** sees neither, but sees "Refund" on a completed trip.
- **viewer** sees the trip with no action buttons at all.
- A trip from another city shows "Trip not found".

## Trade-offs

- **Hand-written GraphQL documents and DTO mapping** instead of codegen (B7). Fewer moving parts in 48 hours; the cost is no compile-time schema check.
- **Polling `/api/me` every 30 s** to catch bans and role changes. That is one small request per user; the alternative was trusting realtime connections that the API keeps open after a ban.
- **The SSE preflight is a REST call** on every realtime error. It costs one request per reconnect, and in return the app always knows why the connection dropped.
- **Ignoring live updates for rows that are not loaded** keeps the list stable. The total count and a reload are always one click away.

## With more time

- Typed GraphQL operations from the schema (`graphql_codegen`) and a generated REST client from `/openapi.json` (B7).
- Widget tests for the shell per role, golden tests for the main screens, and one integration test against the sandbox (assign, then watch the SSE update arrive).
- Arabic and RTL (B5).
- Driver and rider forms for ops_manager (B3).
- Virtualised trip table with sortable columns, and keyboard shortcuts for dispatchers.
- Self-hosted or paid map tiles: the public OpenStreetMap servers are not meant for production traffic (`flutter_map` warns about this at start-up).

## API feedback and known issues

1. **Banned users keep their open realtime connections.** `/docs/realtime` says new connections are refused, but open ones stay open until they reconnect. A banned dispatcher could keep watching the live map and alerts. We work around it with the 30 s `/api/me` check. Suggestion: close SSE and WebSocket for that user on ban or session revoke (WebSocket close code 4001).
2. **No signal when `lastEventId` is too old to replay.** The replay buffer is the last 500 events server-wide. After a long disconnect the client cannot tell whether it missed events. We refresh visible data after every outage to be safe. Suggestion: send a `reset` event, or a `ready` flag, when the id is outside the buffer.
3. **GraphQL validation errors use `GRAPHQL_VALIDATION_FAILED`**, which is not one of the documented codes (`UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID_STATE`, `VALIDATION_FAILED`). We map unknown codes to a generic error.
4. **Status casing differs by transport:** GraphQL uses `IN_PROGRESS`, while REST and SSE use `in_progress`. The mapper accepts both.
5. **The sandbox alert feed is very noisy:** Doha had over 500 open alerts, most of them identical "High demand" warnings. Grouping repeats server-side (a count on one alert) would make the feed more useful.
6. **Map tiles:** the app uses the public OpenStreetMap tile servers, which is fine for a review but not for production.
