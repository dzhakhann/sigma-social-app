import 'dart:io' show Platform;

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sigma_link.dart';

/// Deferred deep linking: recovers the link someone followed BEFORE the app
/// existed on their phone.
///
/// The flow it completes: a shared `/post/<id>` link is opened on a device with
/// no app → the web page sends them to Play with `&referrer=<the link>` → Play
/// hands that string to the app on its very first launch → we replay it after
/// they register. Without this the user installs, signs up, and lands on the
/// home screen with no trace of what they actually came to see.
///
/// Android-only by nature. Play Install Referrer is a Play Store API; the App
/// Store has no equivalent, so iOS will need a different mechanism.
class InstallReferrer {
  InstallReferrer._();

  /// Set once the referrer has been examined. Play only guarantees the value on
  /// first launch, but the flag is what stops us re-reading — and re-acting on —
  /// a stale referrer on every subsequent start.
  static const _kChecked = 'install_referrer_checked';
  static const _kPending = 'pending_deep_link';

  /// Reads the referrer and parks any Sigmacta link found in it.
  ///
  /// Runs before login, and deliberately does NOT navigate: at first launch
  /// there's no session yet. DeepLinks.consumePending() picks it up once there
  /// is one.
  static Future<void> check() async {
    if (!Platform.isAndroid) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kChecked) == true) return;

    try {
      final details = await AndroidPlayInstallReferrer.installReferrer;
      final raw = details.installReferrer ?? '';
      // Marked checked even on a miss: a normal Play install has no referrer,
      // and retrying forever would query the Play service on every launch.
      await p.setBool(_kChecked, true);
      if (raw.isEmpty) return;

      final link = _extract(raw);
      // Never overwrite a link that arrived through a real App Link — that one
      // is more recent and more specific than an install-time referrer.
      if (link != null && p.getString(_kPending) == null) {
        await p.setString(_kPending, link.url);
      }
    } catch (_) {
      // The Play service is missing (sideloaded APK, emulator without Play) or
      // refused. Nothing to recover; installing is still a success.
      await p.setBool(_kChecked, true);
    }
  }

  /// Pulls a Sigmacta link out of a referrer string.
  ///
  /// Play delivers whatever the link put in `referrer=`, commonly
  /// `utm_source=...&link=https%3A%2F%2F...`. Both a bare URL and a
  /// query-string-wrapped one are accepted, because the web side is free to
  /// change how it packs it and this shouldn't break when it does.
  static SigmaLink? _extract(String raw) {
    final candidates = <String>[raw];
    try {
      // Referrer is URL-encoded by Play; decode before looking for params.
      final decoded = Uri.decodeComponent(raw);
      candidates.add(decoded);
      for (final pair in decoded.split('&')) {
        final i = pair.indexOf('=');
        if (i <= 0) continue;
        final key = pair.substring(0, i);
        if (key == 'link' || key == 'url' || key == 'target') {
          candidates.add(Uri.decodeComponent(pair.substring(i + 1)));
        }
      }
    } catch (_) {}

    for (final c in candidates) {
      final trimmed = c.trim();
      if (!trimmed.startsWith('http')) continue;
      final link = SigmaLink.parse(Uri.parse(trimmed));
      if (link != null) return link;
    }
    return null;
  }
}
