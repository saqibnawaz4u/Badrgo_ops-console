import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../domain/entities/current_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Owns the session: restore on page load, sign-in, sign-out, the global
/// 401 reaction and keeping permissions fresh after a 403.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repository) : super(const AuthState.unknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthRestoreRetried>(_onStarted);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthSessionExpired>(_onSessionExpired);
    on<AuthRefreshRequested>(_onRefresh);
    on<AuthUserRefreshed>(_onUserRefreshed);
  }

  final AuthRepository _repository;
  bool _refreshing = false;

  Future<void> _onStarted(AuthEvent event, Emitter<AuthState> emit) async {
    if (state.status != AuthStatus.unknown) return;
    final token = _repository.restoreToken();
    if (token == null) {
      emit(const AuthState.unauthenticated());
      return;
    }
    emit(const AuthState.unknown());
    try {
      final user = await _repository.fetchMe();
      emit(AuthState.authenticated(user, token));
    } on ApiException catch (e) {
      switch (e.code) {
        case ApiErrorCode.unauthenticated:
          await _repository.clearLocalSession();
          emit(const AuthState.unauthenticated(
            notice: 'Your session has ended. Please sign in again.',
          ));
        case ApiErrorCode.maintenance || ApiErrorCode.network:
          // Keep the token: we retry restoring when the API is back.
          emit(const AuthState.unknown(restorePending: true));
        default:
          emit(AuthState.unknown(restorePending: true, notice: e.message));
      }
    }
  }

  Future<void> _onSignIn(AuthSignInRequested event, Emitter<AuthState> emit) async {
    if (state.submitting) return;
    emit(const AuthState.unauthenticated(submitting: true));
    try {
      final user = await _repository.signIn(email: event.email, password: event.password);
      emit(AuthState.authenticated(user, _repository.token!));
    } on ApiException catch (e) {
      emit(AuthState.unauthenticated(signInError: e.message));
    }
  }

  Future<void> _onSignOut(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    if (state.status != AuthStatus.authenticated) return;
    await _repository.signOut();
    emit(const AuthState.unauthenticated(notice: 'You have been signed out.'));
  }

  /// Any 401 from any transport lands here. Only the first one counts:
  /// once we are signed out, later 401s are ignored, so there is no loop.
  Future<void> _onSessionExpired(AuthSessionExpired event, Emitter<AuthState> emit) async {
    if (state.status == AuthStatus.unauthenticated) return;
    await _repository.clearLocalSession();
    emit(const AuthState.unauthenticated(
      notice: 'Your session has ended (signed out elsewhere, expired or the account was '
          'disabled). Please sign in again.',
    ));
  }

  /// After a 403, or periodically: permissions may have changed.
  Future<void> _onRefresh(AuthRefreshRequested event, Emitter<AuthState> emit) async {
    if (state.status != AuthStatus.authenticated || _refreshing) return;
    _refreshing = true;
    try {
      final user = await _repository.fetchMe();
      if (state.status == AuthStatus.authenticated) {
        emit(state.copyWithUser(user));
      }
    } on ApiException {
      // 401 is handled by the global signal; other errors keep the old user.
    } finally {
      _refreshing = false;
    }
  }

  void _onUserRefreshed(AuthUserRefreshed event, Emitter<AuthState> emit) {
    if (state.status == AuthStatus.authenticated && state.user!.id == event.user.id) {
      emit(state.copyWithUser(event.user));
    }
  }
}
