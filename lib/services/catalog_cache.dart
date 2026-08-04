import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Disk cache for the Rhythm catalogs (music trending, default podcast and
/// audiobook lists). Screens render the cached copy instantly and refresh from
/// the network in the background — instead of a spinner on every open while a
/// (possibly cold) free-tier backend wakes up.
class CatalogCache {
  static SharedPreferences? _p;

  static Future<void> init() async =>
      _p ??= await SharedPreferences.getInstance();

  /// The cached list for [key], or null if nothing was saved yet.
  static List<Map>? get(String key) {
    final s = _p?.getString('cat_$key');
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List).map((e) => Map.from(e)).toList();
    } catch (_) {
      return null;
    }
  }

  static void put(String key, List<Map> data) {
    if (data.isEmpty) return; // never overwrite good data with a failure
    try {
      _p?.setString('cat_$key', jsonEncode(data));
    } catch (_) {}
  }
}
