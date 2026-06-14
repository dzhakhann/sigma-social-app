import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Persists the logged-in session (JWT + user) so the app stays signed in
/// across restarts — like Instagram/Telegram. Cleared only on logout.
class Session {
  static const _kToken = 'session_token';
  static const _kUser = 'session_user';

  /// Save after a successful login / register / recover.
  static Future<void> save(String token, Map user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kUser, jsonEncode(user));
    ApiService.setToken(token);
  }

  /// Load on app start. Returns the saved user (and primes the token), or null.
  static Future<Map?> load() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString(_kToken);
    final userStr = p.getString(_kUser);
    if (token == null || userStr == null) return null;
    ApiService.setToken(token);
    try {
      return jsonDecode(userStr) as Map;
    } catch (_) {
      return null;
    }
  }

  /// Clear on logout.
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUser);
    ApiService.clearToken();
  }
}
