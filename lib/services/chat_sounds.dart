import 'package:audioplayers/audioplayers.dart';

import 'notification_prefs.dart';

/// Short click on send, softer one on receive — the in-chat feedback Telegram
/// gives you.
///
/// Separate from the notification tones on purpose: these fire on EVERY message
/// and must stay under ~100ms and quiet, whereas a notification tone is meant
/// to be noticed from across a room.
///
/// One shared player, reused for every blip. Creating an AudioPlayer per sound
/// leaks a platform player each time and eventually starves the audio session —
/// the same mistake that made music previews go silent earlier in this project.
class ChatSounds {
  ChatSounds._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;

  static Future<void> _ensure() async {
    if (_ready) return;
    _ready = true;
    // Never duck or interrupt whatever the user is listening to for a 90ms
    // click — without this, a blip pauses their music on some devices.
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  static Future<void> _play(String name) async {
    // Honours the same master + sound switches the settings screen exposes, so
    // "sound off" means silent everywhere rather than just in notifications.
    final prefs = NotificationPrefs.value.value;
    if (!prefs.enabled || !prefs.soundOn) return;
    try {
      await _ensure();
      await _player.stop();
      await _player.play(AssetSource('sounds/notif_$name.wav'), volume: 0.55);
    } catch (_) {
      // A missing asset or a busy audio session must never break sending.
    }
  }

  static Future<void> sent() => _play('send');

  static Future<void> received() => _play('receive');
}
