import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Swaps the home-screen launcher icon to match the active theme.
///
/// Android only for now. The switch is done natively by enabling one
/// `activity-alias` and disabling the others (see MainActivity.kt) — there is no
/// API to change an activity's icon directly.
///
/// iOS needs a different mechanism entirely (`UIApplication
/// .setAlternateIconName`, with every variant pre-declared under
/// `CFBundleAlternateIcons` in Info.plist as PNG sets — iOS does not accept
/// vectors). The Dart side here is already platform-agnostic, so adding iOS is
/// a native-side change plus the icon assets; nothing above this call has to
/// know which platform it's on.
class LauncherIcon {
  LauncherIcon._();

  static const _channel = MethodChannel('com.sigmacta.app/launcher_icon');

  /// Theme ids that have an icon of their own. Anything else falls back to the
  /// default Sigmacta icon rather than failing.
  static const _known = {'boys', 'girls'};

  /// Applies the icon for [themeId]. Safe to call on every theme change and on
  /// every launch — enabling an already-enabled alias is a no-op.
  ///
  /// Never throws: a launcher that refuses the change must not break theme
  /// switching, which is the thing the user actually asked for.
  static Future<void> apply(String themeId) async {
    if (!Platform.isAndroid) return;
    final variant = _known.contains(themeId) ? themeId : 'default';
    try {
      await _channel.invokeMethod<bool>('setIcon', {'variant': variant});
    } catch (_) {}
  }
}
