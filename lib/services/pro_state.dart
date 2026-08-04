import 'package:flutter/foundation.dart';

import '../theme/brutal_theme.dart';
import 'chat_wallpaper.dart';

/// Whether the signed-in user currently has Sigmacta Pro.
///
/// A [ValueNotifier] rather than a field on the `user` map that screens pass
/// around: that map is snapshotted from [Session] at startup and handed down
/// the widget tree, so anything that grants Pro mid-session (redeeming a promo
/// code) left every already-built screen believing `is_pro: false`. That's what
/// made Premium themes stay locked immediately after a successful activation
/// while the profile screen — which re-fetches from the server — showed PRO.
///
/// Read it with a ValueListenableBuilder wherever Pro gates something, and set
/// it wherever the truth becomes known: session load, profile refresh, promo
/// redemption.
class ProState {
  ProState._();

  static final ValueNotifier<bool> isPro = ValueNotifier(false);

  /// Updates the flag and revokes anything Pro-only the user is no longer
  /// entitled to — Premium themes and Pro chat wallpapers.
  ///
  /// Bundled into one call on purpose: both live in local storage and would
  /// otherwise stay applied forever after a subscription lapsed, and a caller
  /// that only remembered the flag would leave them behind.
  static void set(bool value) {
    if (isPro.value != value) isPro.value = value;
    enforceThemeEntitlement(value);
    ChatWallpaper.enforceEntitlement(value);
  }
}
