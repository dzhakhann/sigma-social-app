import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  SIGMA SOCIAL — DESIGN SYSTEM  ·  "QUIET LUXURY"
//  Three mature, restrained palettes. No neon, no cartoons.
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

  /// Subtle single-color send button gradient
  LinearGradient get buttonGradient => LinearGradient(
    colors: [accent, accent.withOpacity(0.80)],
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

  // 0 · OBSIDIAN — near-black, muted steel-blue accent. Calm, focused.
  BrutalTheme(
    id: 'obsidian',
    nameEn: 'Obsidian',
    nameRu: 'Обсидиан',
    c: BrutalColors(
      bg:       Color(0xFF0C0C0E), // almost true black
      surface:  Color(0xFF141417), // very dark gray
      surface2: Color(0xFF1E1E22), // slightly lighter panel
      ink:      Color(0xFFE8E8ED), // soft white text
      inkSoft:  Color(0xFF62626E), // quiet muted gray
      accent:   Color(0xFF4F7CFF), // calm steel-blue (not neon)
      accent2:  Color(0xFF2EC4B6), // muted teal
      accent3:  Color(0xFF9B7FFF), // soft lavender
      danger:   Color(0xFFD95F5F), // muted red for likes
      shadow:   Color(0x40000000),
      onAccent: Color(0xFFFFFFFF),
      isDark:   true,
    ),
  ),

  // 1 · PARCHMENT — warm off-white, deep navy accent. Newspaper-clean.
  BrutalTheme(
    id: 'parchment',
    nameEn: 'Parchment',
    nameRu: 'Пергамент',
    c: BrutalColors(
      bg:       Color(0xFFF4F3EF), // warm paper
      surface:  Color(0xFFFFFFFF), // white card
      surface2: Color(0xFFECEBE6), // warm gray input
      ink:      Color(0xFF18181A), // near-black text
      inkSoft:  Color(0xFF7A7A80), // medium warm gray
      accent:   Color(0xFF2D4EE8), // deep calm blue
      accent2:  Color(0xFF0D9488), // forest teal
      accent3:  Color(0xFFC2502C), // warm terra cotta
      danger:   Color(0xFFBF3A3A), // muted red
      shadow:   Color(0x18000000),
      onAccent: Color(0xFFFFFFFF),
      isDark:   false,
    ),
  ),

  // 2 · SLATE — cool charcoal, no blue tint, olive-khaki accent. Masculine.
  BrutalTheme(
    id: 'slate',
    nameEn: 'Slate',
    nameRu: 'Сланец',
    c: BrutalColors(
      bg:       Color(0xFF111214), // cool near-black
      surface:  Color(0xFF1A1B1E), // dark charcoal
      surface2: Color(0xFF26272C), // medium charcoal
      ink:      Color(0xFFDFE0E6), // cool white
      inkSoft:  Color(0xFF6B6C73), // cool medium gray
      accent:   Color(0xFF7EB8A4), // muted sage-green
      accent2:  Color(0xFFC4A882), // warm beige/khaki
      accent3:  Color(0xFF8899BB), // dusty blue
      danger:   Color(0xFFCC5F5F), // muted crimson
      shadow:   Color(0x35000000),
      onAccent: Color(0xFF0C0C0E),
      isDark:   true,
    ),
  ),
];

// ─── APP CONFIG ───────────────────────────────────────────────────────────────
class AppConfig {
  final int themeIndex;
  final String lang;
  const AppConfig({this.themeIndex = 0, this.lang = 'ru'});

  AppConfig copyWith({int? themeIndex, String? lang}) =>
      AppConfig(themeIndex: themeIndex ?? this.themeIndex, lang: lang ?? this.lang);

  BrutalTheme get theme => kThemes[themeIndex.clamp(0, kThemes.length - 1)];
}

final ValueNotifier<AppConfig> appConfig =
    ValueNotifier<AppConfig>(const AppConfig());

// ─── INHERITED ACCESS ─────────────────────────────────────────────────────────
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
    cardTheme: CardTheme(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogTheme(
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
