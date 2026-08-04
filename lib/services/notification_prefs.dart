import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-category notification switches plus sound/vibration choices.
///
/// Local-only on purpose: these govern how THIS device behaves when a push or
/// socket event arrives, so there's nothing for the server to know. Muting a
/// category still lets the event through — the client just doesn't raise a
/// notification for it — which keeps in-app badges and counters accurate.
///
/// Exposed as a [ValueNotifier] so the settings screen and the notification
/// service read the same source without either polling SharedPreferences.
class NotificationPrefs {
  NotificationPrefs._();

  /// Category ids. Order here is the order the settings screen renders.
  static const categories = [
    'messages',
    'groups',
    'calls',
    'stories',
    'comments',
    'likes',
    'followers',
    'news',
    'ai',
    'nearby',
  ];

  /// Built-in tones, each backed by `assets/sounds/notif_<id>.wav`
  /// (synthesised — see tool/gen_sounds.py).
  static const sounds = [
    'classic',
    'soft',
    'crystal',
    'pulse',
    'sigma',
    'neo',
    'bubble',
  ];

  /// Free for everyone. The rest are Pro.
  ///
  /// Classic and Soft on purpose: one neutral two-note chime and one gentle
  /// low one, so a free user still has a usable choice rather than a single
  /// forced tone.
  static const freeSounds = {'classic', 'soft'};

  static bool isFreeSound(String id) => freeSounds.contains(id);

  static const _kEnabled = 'notif_enabled';
  static const _kSound = 'notif_sound_on';
  static const _kVibrate = 'notif_vibrate';
  static const _kPreview = 'notif_preview';
  static const _kLed = 'notif_led';
  static const _kTone = 'notif_tone';
  static String _kCat(String id) => 'notif_cat_$id';

  static SharedPreferences? _p;

  /// Current state. Widgets listen to this; nothing reads prefs directly.
  static final ValueNotifier<NotificationSettings> value =
      ValueNotifier(const NotificationSettings());

  static Future<void> load() async {
    _p ??= await SharedPreferences.getInstance();
    final p = _p!;
    value.value = NotificationSettings(
      enabled: p.getBool(_kEnabled) ?? true,
      soundOn: p.getBool(_kSound) ?? true,
      vibrate: p.getBool(_kVibrate) ?? true,
      preview: p.getBool(_kPreview) ?? true,
      led: p.getBool(_kLed) ?? true,
      tone: p.getString(_kTone) ?? 'sigma',
      // Absent means on — a fresh install should notify about everything.
      disabled: {
        for (final id in categories)
          if (p.getBool(_kCat(id)) == false) id,
      },
    );
  }

  static Future<void> _save(NotificationSettings s) async {
    _p ??= await SharedPreferences.getInstance();
    final p = _p!;
    value.value = s;
    await p.setBool(_kEnabled, s.enabled);
    await p.setBool(_kSound, s.soundOn);
    await p.setBool(_kVibrate, s.vibrate);
    await p.setBool(_kPreview, s.preview);
    await p.setBool(_kLed, s.led);
    await p.setString(_kTone, s.tone);
    for (final id in categories) {
      await p.setBool(_kCat(id), !s.disabled.contains(id));
    }
  }

  static Future<void> setEnabled(bool v) =>
      _save(value.value.copyWith(enabled: v));
  static Future<void> setSoundOn(bool v) =>
      _save(value.value.copyWith(soundOn: v));
  static Future<void> setVibrate(bool v) =>
      _save(value.value.copyWith(vibrate: v));
  static Future<void> setPreview(bool v) =>
      _save(value.value.copyWith(preview: v));
  static Future<void> setLed(bool v) => _save(value.value.copyWith(led: v));
  static Future<void> setTone(String v) =>
      _save(value.value.copyWith(tone: v));

  static Future<void> setCategory(String id, bool on) {
    final next = Set<String>.from(value.value.disabled);
    if (on) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return _save(value.value.copyWith(disabled: next));
  }
}

@immutable
class NotificationSettings {
  final bool enabled;
  final bool soundOn;
  final bool vibrate;
  final bool preview;
  final bool led;
  final String tone;

  /// Categories the user switched OFF. Storing the off-set rather than the
  /// on-set means a category added in a future version defaults to on.
  final Set<String> disabled;

  const NotificationSettings({
    this.enabled = true,
    this.soundOn = true,
    this.vibrate = true,
    this.preview = true,
    this.led = true,
    this.tone = 'sigma',
    this.disabled = const {},
  });

  /// The single question the notification service needs to ask.
  bool allows(String category) => enabled && !disabled.contains(category);

  NotificationSettings copyWith({
    bool? enabled,
    bool? soundOn,
    bool? vibrate,
    bool? preview,
    bool? led,
    String? tone,
    Set<String>? disabled,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        soundOn: soundOn ?? this.soundOn,
        vibrate: vibrate ?? this.vibrate,
        preview: preview ?? this.preview,
        led: led ?? this.led,
        tone: tone ?? this.tone,
        disabled: disabled ?? this.disabled,
      );
}
