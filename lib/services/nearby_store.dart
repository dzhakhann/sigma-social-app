import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local (device-only) history of Sigma Nearby exchanges — shown on the
/// Discover screen under the "Profile exchange" card. Nothing is stored on
/// the server: same privacy stance as Rhythm history.
class NearbyStore {
  static const _key = 'nearby_recent';

  static Future<List<Map>> recent() async {
    final p = await SharedPreferences.getInstance();
    try {
      return ((jsonDecode(p.getString(_key) ?? '[]')) as List)
          .map((e) => Map.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(Map user) async {
    final p = await SharedPreferences.getInstance();
    final list = await recent();
    list.removeWhere((e) => e['id'].toString() == user['id'].toString());
    list.insert(0, {
      'id': user['id'],
      'username': user['username'],
      'avatar_url': user['avatar_url'],
      'at': DateTime.now().toIso8601String(),
    });
    if (list.length > 20) list.removeRange(20, list.length);
    await p.setString(_key, jsonEncode(list));
  }
}
