part of 'auth_bloc.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState extends Equatable {
  const AuthState._({
    required this.status,
    this.user,
    this.token,
    this.notice,
    this.signInError,
    this.submitting = false,
    this.restorePending = false,
  });

  const AuthState.unknown({bool restorePending = false, String? notice})
      : this._(status: AuthStatus.unknown, restorePending: restorePending, notice: notice);

  const AuthState.unauthenticated({String? notice, String? signInError, bool submitting = false})
      : this._(
          status: AuthStatus.unauthenticated,
          notice: notice,
          signInError: signInError,
          submitting: submitting,
        );

  const AuthState.authenticated(CurrentUser user, String token)
      : this._(status: AuthStatus.authenticated, user: user, token: token);

  final AuthStatus status;
  final CurrentUser? user;
  final String? token;

  /// Informational message for the sign-in page (e.g. "session ended").
  final String? notice;

  /// Server error from the last sign-in attempt (wrong password, banned).
  final String? signInError;
  final bool submitting;

  /// Restoring a saved session failed because the API was unreachable.
  final bool restorePending;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWithUser(CurrentUser user) => AuthState._(status: status, user: user, token: token);

  @override
  List<Object?> get props => [status, user, token, notice, signInError, submitting, restorePending];
}
