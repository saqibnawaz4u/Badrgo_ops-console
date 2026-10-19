import '../entities/current_user.dart';

abstract interface class AuthRepository {
  /// Token currently in memory (null when signed out).
  String? get token;

  /// Loads a persisted token. Returns null if there is none.
  String? restoreToken();

  /// `POST /api/auth/sign-in/email`, then `GET /api/me`. Persists the token.
  Future<CurrentUser> signIn({required String email, required String password});

  /// `GET /api/me`.
  Future<CurrentUser> fetchMe();

  /// Revokes the token on the server (best effort) and clears it locally.
  Future<void> signOut();

  /// Forgets the token locally without calling the server (after a 401).
  Future<void> clearLocalSession();
}
