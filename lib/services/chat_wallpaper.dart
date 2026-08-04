import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which procedural texture is tiled over a wallpaper's gradient.
/// Drawn in ChatBackground — see the note there on why these aren't images.
enum WallpaperPattern { none, dots, rings, hearts, stars, waves, arcs }

/// One wallpaper option: a multi-stop gradient plus an optional pattern.
class ChatWallpaperPreset {
  final String id;

  /// 2–4 ARGB stops. More than two is what stops these looking like a flat
  /// ramp — the old presets were all two-colour and read as plain fills.
  final List<int> colors;
  final WallpaperPattern pattern;

  /// Pro-only. Every wallpaper is: changing the chat background is a Pro
  /// feature in its own right, so the free tier gets the themed default and
  /// nothing else. Kept as a field rather than hardcoded so a promo/free
  /// wallpaper can be introduced later without touching the gate.
  final bool pro;

  const ChatWallpaperPreset(this.id, this.colors, this.pattern,
      {this.pro = true});
}

/// Telegram-style chat background: a preset gradient or a photo from the
/// gallery. Stored per chat (falls back to a global default so a wallpaper
/// picked once can apply everywhere) — purely local, like every other
/// on-device preference in this app (history, downloads, etc.).
class ChatWallpaper {
  static SharedPreferences? _p;
  static Future<void> _ensure() async =>
      _p ??= await SharedPreferences.getInstance();

  /// Chosen to stay readable under white text AND under the accent-tinted
  /// "own message" bubble, which is why every one of them is dark and
  /// low-contrast rather than vivid.
  static const List<ChatWallpaperPreset> catalog = [
    ChatWallpaperPreset('midnight', [0xFF0F2027, 0xFF203A43, 0xFF2C5364],
        WallpaperPattern.none),
    ChatWallpaperPreset('graphite', [0xFF232526, 0xFF3A3D40, 0xFF414345],
        WallpaperPattern.none),
    ChatWallpaperPreset('slate', [0xFF16222A, 0xFF2B4A5A, 0xFF3A6073],
        WallpaperPattern.dots),
    ChatWallpaperPreset(
        'ocean', [0xFF1A2980, 0xFF1E6F9F, 0xFF26D0CE], WallpaperPattern.waves),
    ChatWallpaperPreset(
        'orchid', [0xFF360033, 0xFF6A0F5B, 0xFF0B8793], WallpaperPattern.rings),
    ChatWallpaperPreset(
        'ember', [0xFF4B134F, 0xFF8E3B4A, 0xFFC94B4B], WallpaperPattern.dots),
    ChatWallpaperPreset('rose', [0xFF41295A, 0xFF77335E, 0xFF9E4C63],
        WallpaperPattern.hearts),
    ChatWallpaperPreset('aurora', [0xFF0B486B, 0xFF2A6F7B, 0xFF3B8686],
        WallpaperPattern.stars),
    ChatWallpaperPreset('steel', [0xFF283048, 0xFF5A6674, 0xFF859398],
        WallpaperPattern.rings),
    ChatWallpaperPreset('forest', [0xFF0F2C24, 0xFF1F4F3C, 0xFF2E7D5B],
        WallpaperPattern.waves),
    ChatWallpaperPreset('plum', [0xFF2B1B3D, 0xFF4A2C5E, 0xFF6E3B7E],
        WallpaperPattern.stars),
    // Two big facing light curves down the sides — the look from the reference
    // mockup, as BACKGROUND light rather than as a path messages travel along.
    ChatWallpaperPreset('orbit', [0xFF120E1C, 0xFF1E1630, 0xFF2A1F45],
        WallpaperPattern.arcs),
    ChatWallpaperPreset('orbitRose', [0xFF15101C, 0xFF241A2E, 0xFF3A2440],
        WallpaperPattern.arcs),
  ];

  /// Wallpapers saved by older builds stored the preset's INDEX in the old
  /// eight-item list, not an id. Mapped onto the closest new preset so an
  /// update doesn't silently wipe everyone's chosen background.
  static const _legacyIndexIds = [
    'midnight', 'ocean', 'graphite', 'aurora',
    'orchid', 'steel', 'slate', 'ember',
  ];

  static ChatWallpaperPreset? presetById(Object? id) {
    if (id == null) return null;
    if (id is int) {
      if (id < 0 || id >= _legacyIndexIds.length) return null;
      return presetById(_legacyIndexIds[id]);
    }
    final s = id.toString();
    // A numeric STRING is the same legacy value read back out of JSON.
    final asInt = int.tryParse(s);
    if (asInt != null) return presetById(asInt);
    for (final p in catalog) {
      if (p.id == s) return p;
    }
    return null;
  }

  static Future<Map?> get(String chatId) async {
    await _ensure();
    final raw =
        _p!.getString('wallpaper_$chatId') ?? _p!.getString('wallpaper_default');
    if (raw == null) return null;
    try {
      return Map.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String chatId, Map? wallpaper,
      {bool asDefault = false}) async {
    await _ensure();
    final key = asDefault ? 'wallpaper_default' : 'wallpaper_$chatId';
    if (wallpaper == null) {
      await _p!.remove(key);
    } else {
      await _p!.setString(key, jsonEncode(wallpaper));
    }
  }

  /// Clears a Pro wallpaper the user is no longer entitled to.
  ///
  /// Wallpapers live in SharedPreferences, so an expired subscription would
  /// otherwise leave a Pro background applied indefinitely — the picker can
  /// only stop you choosing a new one.
  static Future<void> enforceEntitlement(bool hasPro) async {
    if (hasPro) return;
    await _ensure();
    for (final key in _p!.getKeys().toList()) {
      if (!key.startsWith('wallpaper_')) continue;
      final raw = _p!.getString(key);
      if (raw == null) continue;
      try {
        final map = Map.from(jsonDecode(raw));
        // A gallery photo is a Pro feature too — it was never in the free set.
        final isProChoice = map['type'] == 'image' ||
            (presetById(map['id'])?.pro ?? false);
        if (isProChoice) await _p!.remove(key);
      } catch (_) {
        await _p!.remove(key);
      }
    }
  }
}
