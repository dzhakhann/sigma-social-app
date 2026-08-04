import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/launcher_icon.dart';

// ════════════════════════════════════════════════════════════════════════════
//  SIGMA SOCIAL — DESIGN SYSTEM  ·  "QUIET LUXURY"
//  Four mature, restrained palettes. No neon, no cartoons.
//  Clean typography, soft shadows, muted accents.
// ════════════════════════════════════════════════════════════════════════════

class BrutalColors extends ThemeExtension<BrutalColors> {
  final Color bg;       // page background
  final Color surface;  // card / panel fill
  final Color surface2; // secondary fill (input bg, chips)
  final Color ink;      // primary text
  final Color inkSoft;  // muted text / icons
  final Color accent;   // primary accent
  final Color accent2;  // secondary accent
  final Color accent3;  // tertiary accent
  final Color danger;   // likes / destructive
  final Color shadow;   // soft shadow color
  final Color onAccent; // text on accent buttons
  final bool isDark;

  const BrutalColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.danger,
    required this.shadow,
    required this.onAccent,
    required this.isDark,
  });

  @override
  BrutalColors copyWith({
    Color? bg, Color? surface, Color? surface2,
    Color? ink, Color? inkSoft, Color? accent,
    Color? accent2, Color? accent3, Color? danger,
    Color? shadow, Color? onAccent, bool? isDark,
  }) => BrutalColors(
    bg: bg ?? this.bg, surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2, ink: ink ?? this.ink,
    inkSoft: inkSoft ?? this.inkSoft, accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2, accent3: accent3 ?? this.accent3,
    danger: danger ?? this.danger, shadow: shadow ?? this.shadow,
    onAccent: onAccent ?? this.onAccent, isDark: isDark ?? this.isDark,
  );

  @override
  BrutalColors lerp(ThemeExtension<BrutalColors>? other, double t) {
    if (other is! BrutalColors) return this;
    return BrutalColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accent3: Color.lerp(accent3, other.accent3, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  /// The accent shade to put BEHIND [onAccent] text — buttons, send FABs,
  /// filled chips. Text and fills pull the SAME colour in opposite
  /// directions and no single shade can serve both: to stay readable as
  /// text on Sigma's #0F1015 page a blue needs relative luminance ≥ 0.199,
  /// but to carry a white label it needs ≤ 0.183. So `accent` stays vivid
  /// for text/icons and this darkens it just enough to clear 4.5:1.
  ///
  /// Returns `accent` untouched when it already passes (Light, Girls) or
  /// when the label is dark rather than white (Boys' cyan) — darkening
  /// would make that case worse, so it's explicitly excluded.
  Color get accentFill {
    if (_contrast(onAccent, accent) >= 4.5) return accent;
    if (_luminance(onAccent) <= _luminance(accent)) return accent;
    var c = accent;
    for (var i = 0; i < 14; i++) {
      c = Color.lerp(c, const Color(0xFF000000), 0.05)!;
      if (_contrast(onAccent, c) >= 4.5) return c;
    }
    return c;
  }

  static double _channel(double c) => c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _luminance(Color c) =>
      0.2126 * _channel(c.red / 255) +
      0.7152 * _channel(c.green / 255) +
      0.0722 * _channel(c.blue / 255);

  static double _contrast(Color a, Color b) {
    final la = _luminance(a), lb = _luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Subtle single-color send button gradient
  LinearGradient get buttonGradient => LinearGradient(
    colors: [accentFill, accentFill.withOpacity(0.80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Story ring — muted multi-tone, not neon
  LinearGradient get storyGradient => LinearGradient(
    colors: [accent, accent2, accent3],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class BrutalTheme {
  final String id;
  final String nameEn;
  final String nameRu;
  final BrutalColors c;
  const BrutalTheme({
    required this.id, required this.nameEn,
    required this.nameRu, required this.c,
  });
  Brightness get brightness => c.isDark ? Brightness.dark : Brightness.light;
}

// ─── MATURE PALETTES ──────────────────────────────────────────────────────────
const List<BrutalTheme> kThemes = [

  // SIGMA — the one modest dark theme. bg #0F1015, cards #171923, blue accent.
  BrutalTheme(
    id: 'sigma',
    nameEn: 'Sigma',
    nameRu: 'Sigma',
    c: BrutalColors(
      bg:       Color(0xFF0F1015), // page background
      surface:  Color(0xFF171923), // cards / panels
      surface2: Color(0xFF1F2230), // inputs / chips
      ink:      Color(0xFFE9EBF1), // primary text
      inkSoft:  Color(0xFF878DA0), // muted text
      accent:   Color(0xFF4F7CFF), // blue accent
      accent2:  Color(0xFF6E92FF), // lighter blue
      accent3:  Color(0xFF9B7FFF), // soft lavender
      danger:   Color(0xFFE5556B), // likes / destructive
      shadow:   Color(0x66000000), // soft shadow
      onAccent: Color(0xFFFFFFFF),
      isDark:   true,
    ),
  ),

  // LIGHT — clean warm paper background with the same blue accent.
  BrutalTheme(
    id: 'light',
    nameEn: 'Light',
    nameRu: 'Светлая',
    c: BrutalColors(
      bg:       Color(0xFFF5F5F2),
      surface:  Color(0xFFFFFFFF),
      surface2: Color(0xFFEDEDEA),
      ink:      Color(0xFF17181C),
      inkSoft:  Color(0xFF66697A), // was #6E7280 — 4.39:1 on bg, just under AA

      accent:   Color(0xFF3563E9),
      accent2:  Color(0xFF5A82F0),
      accent3:  Color(0xFF8A6FF0),
      danger:   Color(0xFFD64560),
      shadow:   Color(0x22000000),
      onAccent: Color(0xFFFFFFFF),
      isDark:   false,
    ),
  ),

  // BOYS — deep midnight-navy with an electric cyan accent.
  BrutalTheme(
    id: 'boys',
    nameEn: 'Boys',
    nameRu: 'Boys',
    c: BrutalColors(
      bg:       Color(0xFF0A121F),
      surface:  Color(0xFF122032),
      surface2: Color(0xFF1A2C43),
      ink:      Color(0xFFE6F0FA),
      inkSoft:  Color(0xFF7C93AD),
      accent:   Color(0xFF17B8E8), // electric cyan
      accent2:  Color(0xFF4FD3F5),
      accent3:  Color(0xFF3A7BD5),
      danger:   Color(0xFFFF5C77),
      shadow:   Color(0x77000000),
      onAccent: Color(0xFF04121A),
      isDark:   true,
    ),
  ),

  // GIRLS — soft blush paper with a rose accent.
  BrutalTheme(
    id: 'girls',
    nameEn: 'Girls',
    nameRu: 'Girls',
    c: BrutalColors(
      bg:       Color(0xFFFFF5F8),
      surface:  Color(0xFFFFFFFF),
      surface2: Color(0xFFFDE8EF),
      ink:      Color(0xFF3A1F2B),
      // Muted text and the accent are DELIBERATELY this deep: the first pass
      // used a lighter rose (#E8508D / #9B7684) and theme_contrast_test.dart
      // caught it — white button labels sat at 3.5:1 and muted text at 3.7:1,
      // i.e. the same unreadable-on-light problem the post music bar had.
      // Don't lighten these without re-running that test.
      inkSoft:  Color(0xFF7D5566),
      accent:   Color(0xFFCE2F66), // rose
      accent2:  Color(0xFFF477AC),
      accent3:  Color(0xFFB06AD8), // orchid
      // Clearly RED, not another rose: the first pass used #D6395B, which
      // sat right next to the #D6336C accent — a "Delete" button looked
      // almost identical to a normal one. Destructive actions have to read
      // as destructive at a glance.
      danger:   Color(0xFFC0392B),
      shadow:   Color(0x1F5A2340),
      onAccent: Color(0xFFFFFFFF),
      isDark:   false,
    ),
  ),

];

// ─── APP CONFIG ───────────────────────────────────────────────────────────────
class AppConfig {
  final int themeIndex;
  final String lang;
  final String navSide; // 'right' | 'left'
  const AppConfig(
      {this.themeIndex = 0, this.lang = 'en', this.navSide = 'right'});

  AppConfig copyWith({int? themeIndex, String? lang, String? navSide}) =>
      AppConfig(
        themeIndex: themeIndex ?? this.themeIndex,
        lang: lang ?? this.lang,
        navSide: navSide ?? this.navSide,
      );

  BrutalTheme get theme => kThemes[themeIndex.clamp(0, kThemes.length - 1)];
}

final ValueNotifier<AppConfig> appConfig =
    ValueNotifier<AppConfig>(const AppConfig());

bool _cfgListenerAttached = false;

/// Load the saved language/theme on startup (default language = English), and
/// persist any future change so the choice survives restarts.
Future<void> loadAppConfig() async {
  try {
    final p = await SharedPreferences.getInstance();
    appConfig.value = AppConfig(
      themeIndex: p.getInt('cfg_theme') ?? 0,
      lang: p.getString('cfg_lang') ?? 'en',
      navSide: p.getString('cfg_nav') ?? 'right',
    );
  } catch (_) {}
  if (!_cfgListenerAttached) {
    _cfgListenerAttached = true;
    appConfig.addListener(() async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setInt('cfg_theme', appConfig.value.themeIndex);
        // The launcher icon follows the theme. Hooked into the persist
        // listener rather than the settings screen: that's the one place every
        // theme change goes through, including enforceThemeEntitlement()
        // revoking a Premium theme.
        LauncherIcon.apply(appConfig.value.theme.id);
        await p.setString('cfg_lang', appConfig.value.lang);
        await p.setString('cfg_nav', appConfig.value.navSide);
      } catch (_) {}
    });
  }
}

// ─── INHERITED ACCESS ─────────────────────────────────────────────────────────
/// Themes that require an active Pro subscription.
const Set<String> kPremiumThemeIds = {'boys', 'girls'};

/// Drops the user back to the default theme if they're sitting on a Premium one
/// without Pro.
///
/// The settings picker already blocks selecting one, but that isn't enough on
/// its own: a subscription that lapses (or a promo code that expires) would
/// otherwise leave the theme applied forever, since nothing re-checks it. Call
/// this wherever the user's Pro state becomes known — i.e. right after login or
/// a profile refresh.
void enforceThemeEntitlement(bool hasPro) {
  if (hasPro) return;
  final current = appConfig.value.theme.id;
  if (kPremiumThemeIds.contains(current)) {
    appConfig.value = appConfig.value.copyWith(themeIndex: 0);
  }
}

class AppScope extends InheritedWidget {
  final AppConfig config;
  const AppScope({super.key, required this.config, required super.child});

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!;
  }

  String get lang => config.lang;

  @override
  bool updateShouldNotify(AppScope old) => old.config != config;
}

extension BrutalContext on BuildContext {
  BrutalColors get k =>
      Theme.of(this).extension<BrutalColors>() ?? kThemes[0].c;
}

// ─── THEME DATA BUILDER ───────────────────────────────────────────────────────
ThemeData buildBrutalTheme(BrutalTheme t) {
  final c = t.c;
  final base = c.isDark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    colorScheme: (c.isDark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
      primary: c.accent,
      secondary: c.accent2,
      surface: c.surface,
      onSurface: c.ink,
      error: c.danger,
      brightness: t.brightness,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withOpacity(0.25),
      selectionHandleColor: c.accent,
    ),
    dividerColor: c.ink.withOpacity(0.07),
    iconTheme: IconThemeData(color: c.ink),
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.ink, fontSize: 20,
        fontWeight: FontWeight.w700, letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: c.ink),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.surface,
      selectedItemColor: c.accent,
      unselectedItemColor: c.inkSoft,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      hintStyle: TextStyle(color: c.inkSoft),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.accent, width: 1.2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface,
      contentTextStyle: TextStyle(color: c.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ─── HELPERS ─────────────────────────────────────────────────────────────────
BoxDecoration cleanCard(
  BrutalColors c, {
  Color? fill,
  double radius = 14,
  bool withBorder = false,
  double elevation = 1,
}) {
  return BoxDecoration(
    color: fill ?? c.surface,
    borderRadius: BorderRadius.circular(radius),
    border: withBorder
        ? Border.all(color: c.ink.withOpacity(0.07), width: 1)
        : null,
    boxShadow: elevation > 0
        ? [BoxShadow(color: c.shadow, offset: Offset(0, elevation * 2), blurRadius: elevation * 6)]
        : null,
  );
}

BoxDecoration brutalBox(
  BrutalColors c, {
  Color? fill,
  double radius = 14,
  double border = 0,
  Offset offset = Offset.zero,
  Color? borderColor,
}) => cleanCard(c, fill: fill, radius: radius, withBorder: border > 0);
