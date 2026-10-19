part of 'auth_bloc.dart';

sealed class AuthEvent {
  const AuthEvent();
}

/// App start: restore the persisted session.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// The API is back after maintenance while we were still restoring.
class AuthRestoreRetried extends AuthEvent {
  const AuthRestoreRetried();
}

class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});
  final String email;
  final String password;
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Raised by any transport on 401 (or WebSocket close 4001).
class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}

/// Re-fetch `/api/me` (after a 403, or on the periodic check).
class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

/// A fresh `/api/me` fetched elsewhere (e.g. the realtime preflight).
class AuthUserRefreshed extends AuthEvent {
  const AuthUserRefreshed(this.user);
  final CurrentUser user;
}
