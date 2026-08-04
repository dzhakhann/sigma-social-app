import 'package:shared_preferences/shared_preferences.dart';

/// Per-chat mute flag (local only — there's no push-notification system for
/// chat messages yet, so this suppresses in-app sound/vibration cues today
/// and is the foundation for real push muting later).
class ChatMute {
  static SharedPreferences? _p;
  static Future<void> _ensure() async => _p ??= await SharedPreferences.getInstance();

  static Future<bool> isMuted(String chatId) async {
    await _ensure();
    return _p!.getBool('muted_$chatId') ?? false;
  }

  static Future<void> setMuted(String chatId, bool muted) async {
    await _ensure();
    if (muted) {
      await _p!.setBool('muted_$chatId', true);
    } else {
      await _p!.remove('muted_$chatId');
    }
  }
}
