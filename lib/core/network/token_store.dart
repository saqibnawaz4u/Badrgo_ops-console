import 'package:shared_preferences/shared_preferences.dart';

/// Holds the session token in memory and persists it so the session
/// survives a page refresh (on web, SharedPreferences uses localStorage).
class TokenStore {
  TokenStore(this._prefs);

  static const _key = 'badrgo.session_token';

  final SharedPreferences _prefs;
  String? _token;

  String? get token => _token;

  /// Loads the persisted token into memory.
  String? restore() => _token = _prefs.getString(_key);

  Future<void> save(String token) async {
    _token = token;
    await _prefs.setString(_key, token);
  }

  Future<void> clear() async {
    _token = null;
    await _prefs.remove(_key);
  }
}
