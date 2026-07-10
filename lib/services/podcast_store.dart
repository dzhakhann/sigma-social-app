import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only storage for podcast History, Favourites ("Нравится") and the
/// Playlist queue. Kept in shared_preferences — nothing touches our server or
/// database, so this feature adds zero backend load.
///
/// An "episode" is a Map with at least: title, audio, and (for nice display)
/// showTitle, artist, artwork, feedUrl, duration.
class PodcastStore {
  static const _kHistory = 'pod_history';
  static const _kFav = 'pod_favorites';

  static Future<List<Map>> _read(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(key);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => Map.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(String key, List<Map> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(list));
  }

  // ─── History (recently played) ─────────────────────────────────────────────
  static Future<List<Map>> history() => _read(_kHistory);

  static Future<void> addHistory(Map ep) async {
    final list = await _read(_kHistory);
    list.removeWhere((e) => e['audio'] == ep['audio']);
    list.insert(0, ep);
    if (list.length > 50) list.removeRange(50, list.length);
    await _write(_kHistory, list);
  }

  static Future<void> clearHistory() => _write(_kHistory, []);

  // ─── Favourites ("Нравится") ───────────────────────────────────────────────
  static Future<List<Map>> favorites() => _read(_kFav);

  static Future<bool> isFavorite(String audio) async {
    final list = await _read(_kFav);
    return list.any((e) => e['audio'] == audio);
  }

  /// Toggles favourite; returns the new state (true = now favourite).
  static Future<bool> toggleFavorite(Map ep) async {
    final list = await _read(_kFav);
    final i = list.indexWhere((e) => e['audio'] == ep['audio']);
    bool nowFav;
    if (i >= 0) {
      list.removeAt(i);
      nowFav = false;
    } else {
      list.insert(0, ep);
      nowFav = true;
    }
    await _write(_kFav, list);
    return nowFav;
  }

  // ─── Named playlists (YouTube-style) ───────────────────────────────────────
  // Stored as a list of { name, episodes: [...] }.
  static const _kPlaylists = 'pod_playlists';

  static Future<List<Map>> playlists() => _read(_kPlaylists);

  static Future<void> createPlaylist(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final list = await _read(_kPlaylists);
    if (list.any((p) => (p['name'] ?? '') == n)) return;
    list.insert(0, {'name': n, 'episodes': []});
    await _write(_kPlaylists, list);
  }

  static Future<void> deletePlaylist(String name) async {
    final list = await _read(_kPlaylists);
    list.removeWhere((p) => (p['name'] ?? '') == name);
    await _write(_kPlaylists, list);
  }

  static Future<void> addToPlaylist(String name, Map ep) async {
    final list = await _read(_kPlaylists);
    final i = list.indexWhere((p) => (p['name'] ?? '') == name);
    if (i < 0) return;
    final eps = (list[i]['episodes'] as List).map((e) => Map.from(e)).toList();
    if (eps.any((e) => e['audio'] == ep['audio'])) return;
    eps.add(ep);
    list[i]['episodes'] = eps;
    await _write(_kPlaylists, list);
  }

  static Future<void> removeFromPlaylist(String name, String audio) async {
    final list = await _read(_kPlaylists);
    final i = list.indexWhere((p) => (p['name'] ?? '') == name);
    if (i < 0) return;
    final eps = (list[i]['episodes'] as List).map((e) => Map.from(e)).toList();
    eps.removeWhere((e) => e['audio'] == audio);
    list[i]['episodes'] = eps;
    await _write(_kPlaylists, list);
  }
}
