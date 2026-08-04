/// Which shape a preset's particles render as.
enum ParticleShape { glyph, circle, rect }

/// One animated profile-background option: a gradient plus a particle field.
///
/// Server-synced (profile_background on the user row) rather than local —
/// unlike a chat wallpaper this is part of how OTHER people see your profile,
/// so it can't just live in this device's SharedPreferences.
class ProfileBackgroundPreset {
  final String id;

  /// 2–3 ARGB stops behind the particles.
  final List<int> colors;

  final ParticleShape shape;

  /// Glyphs to pick from at random, one per particle. Ignored for non-glyph
  /// shapes.
  final List<String> glyphs;

  /// Solid colour for circle/rect particles. Ignored for glyph shapes (glyphs
  /// carry their own colour).
  final int particleColor;

  final int count;
  final double minSize;
  final double maxSize;

  /// Particles drift upward (hearts, bubbles) instead of falling (snow,
  /// petals, confetti).
  final bool rising;

  final bool pro;

  const ProfileBackgroundPreset(
    this.id,
    this.colors,
    this.shape, {
    this.glyphs = const [],
    this.particleColor = 0xFFFFFFFF,
    this.count = 14,
    this.minSize = 14,
    this.maxSize = 22,
    this.rising = false,
    this.pro = true,
  });
}

class ProfileBackgrounds {
  ProfileBackgrounds._();

  static const List<ProfileBackgroundPreset> catalog = [
    // Free
    ProfileBackgroundPreset(
      'sparkle',
      [0xFF0F1024, 0xFF1B1B3A, 0xFF2A2A5C],
      ParticleShape.glyph,
      glyphs: ['✨', '⭐'],
      count: 16,
      minSize: 10,
      maxSize: 18,
      pro: false,
    ),
    ProfileBackgroundPreset(
      'confetti',
      [0xFF2B1B3D, 0xFF6E3B7E, 0xFF9E4C9E],
      ParticleShape.rect,
      particleColor: 0xFFFFD166,
      count: 18,
      minSize: 6,
      maxSize: 11,
      pro: false,
    ),
    // Pro
    ProfileBackgroundPreset(
      'hearts',
      [0xFF41295A, 0xFF77335E, 0xFF9E4C63],
      ParticleShape.glyph,
      glyphs: ['💗', '❤️', '💕'],
      count: 14,
      minSize: 14,
      maxSize: 22,
      rising: true,
    ),
    ProfileBackgroundPreset(
      'petals',
      [0xFF4B3417, 0xFF8E6B2A, 0xFFC9974B],
      ParticleShape.glyph,
      glyphs: ['🌸', '🥀', '🍁'],
      count: 14,
      minSize: 16,
      maxSize: 24,
    ),
    ProfileBackgroundPreset(
      'bubbles',
      [0xFF0B2E3B, 0xFF1E6F7F, 0xFF26AACE],
      ParticleShape.circle,
      particleColor: 0xFFBFEFFF,
      count: 16,
      minSize: 8,
      maxSize: 20,
      rising: true,
    ),
    ProfileBackgroundPreset(
      'snow',
      [0xFF16222A, 0xFF2B4A5A, 0xFF3A6073],
      ParticleShape.glyph,
      glyphs: ['❄️'],
      count: 16,
      minSize: 12,
      maxSize: 18,
    ),
  ];

  static ProfileBackgroundPreset? byId(String? id) {
    if (id == null) return null;
    for (final p in catalog) {
      if (p.id == id) return p;
    }
    return null;
  }
}
