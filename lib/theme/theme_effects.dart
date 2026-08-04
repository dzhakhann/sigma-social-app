import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brutal_theme.dart';

/// Ambient per-theme atmosphere, painted procedurally on top of the whole app.
///
/// Girls gets drifting petals and sparkles; Boys gets neon light streaks. Every
/// particle is drawn with a CustomPainter driven by ONE ticker for the entire
/// overlay — no widget per particle, no per-particle AnimationController, so
/// the cost stays a single repaint of one layer regardless of count.
///
/// Deliberately procedural: the illustrated version of this (cats, sports cars)
/// needs real art assets. The hooks are here — see [ThemeEffectStyle] — so
/// dropping in Lottie/PNG later replaces the painter without touching any
/// screen. Neutral themes render nothing at all and skip the ticker entirely.
enum ThemeEffectStyle { none, girls, boys }

ThemeEffectStyle effectStyleFor(String themeId) {
  switch (themeId) {
    case 'girls':
      return ThemeEffectStyle.girls;
    case 'boys':
      return ThemeEffectStyle.boys;
    default:
      return ThemeEffectStyle.none;
  }
}

/// Wraps the app and paints the active theme's ambience over it.
class ThemeEffectsOverlay extends StatefulWidget {
  final Widget child;
  final ThemeEffectStyle style;
  final BrutalColors colors;

  const ThemeEffectsOverlay({
    super.key,
    required this.child,
    required this.style,
    required this.colors,
  });

  @override
  State<ThemeEffectsOverlay> createState() => _ThemeEffectsOverlayState();
}

class _ThemeEffectsOverlayState extends State<ThemeEffectsOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(ThemeEffectsOverlay old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style) _rebuild();
  }

  void _rebuild() {
    _ctrl?.dispose();
    _ctrl = null;
    if (widget.style == ThemeEffectStyle.none) {
      _particles = const [];
      return;
    }
    final rnd = math.Random(7);
    // Modest counts on purpose. The brief asked for "very rarely, not
    // annoying" — ambience you notice only if you look for it.
    final count = widget.style == ThemeEffectStyle.girls ? 14 : 9;
    _particles = List.generate(count, (i) => _Particle.random(rnd, i));
    // A long period keeps everything slow: one full pass takes ~24s, so the
    // motion reads as drift rather than animation.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return widget.child;
    return Stack(children: [
      widget.child,
      // Purely decorative, so it must never intercept a tap.
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) => CustomPaint(
                painter: _EffectsPainter(
                  t: ctrl.value,
                  style: widget.style,
                  particles: _particles,
                  colors: widget.colors,
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Particle {
  /// Horizontal position as a fraction of width, so it survives rotation and
  /// any screen size.
  final double x;

  /// Phase offset — staggers particles across the shared clock instead of
  /// having them all start together.
  final double phase;
  final double size;
  final double drift;
  final double spin;
  final int kind;

  const _Particle({
    required this.x,
    required this.phase,
    required this.size,
    required this.drift,
    required this.spin,
    required this.kind,
  });

  factory _Particle.random(math.Random r, int i) => _Particle(
        x: r.nextDouble(),
        phase: r.nextDouble(),
        size: 4 + r.nextDouble() * 7,
        drift: (r.nextDouble() - 0.5) * 0.18,
        spin: (r.nextDouble() - 0.5) * 4,
        kind: i % 3,
      );
}

class _EffectsPainter extends CustomPainter {
  final double t;
  final ThemeEffectStyle style;
  final List<_Particle> particles;
  final BrutalColors colors;

  _EffectsPainter({
    required this.t,
    required this.style,
    required this.particles,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (style == ThemeEffectStyle.girls) {
      _paintGirls(canvas, size);
    } else {
      _paintBoys(canvas, size);
    }
  }

  // ── Girls: petals and sparkles drifting down ──────────────────────────────
  void _paintGirls(Canvas canvas, Size size) {
    for (final p in particles) {
      final local = (t + p.phase) % 1.0;
      final y = local * (size.height + 80) - 40;
      // Sway sideways as it falls, like something actually falling through air.
      final x = (p.x + math.sin(local * math.pi * 2) * p.drift) * size.width;
      // Fade in and out at the extremes so nothing pops into existence.
      final fade = math.sin(local * math.pi).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = (p.kind == 2 ? colors.accent3 : colors.accent2)
            .withOpacity(0.30 * fade);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      if (p.kind == 0) {
        _petal(canvas, p.size, paint);
      } else if (p.kind == 1) {
        _sparkle(canvas, p.size, paint);
      } else {
        _heart(canvas, p.size, paint);
      }
      canvas.restore();
    }
  }

  void _petal(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(s, -s * 0.2, 0, s)
      ..quadraticBezierTo(-s, -s * 0.2, 0, -s)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _sparkle(Canvas canvas, double s, Paint paint) {
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, -s), Offset(0, s), stroke);
    canvas.drawLine(Offset(-s, 0), Offset(s, 0), stroke);
    canvas.drawLine(
        Offset(-s * 0.5, -s * 0.5), Offset(s * 0.5, s * 0.5), stroke);
    canvas.drawLine(
        Offset(s * 0.5, -s * 0.5), Offset(-s * 0.5, s * 0.5), stroke);
  }

  void _heart(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(0, s * 0.7)
      ..cubicTo(-s * 1.4, -s * 0.2, -s * 0.5, -s * 1.1, 0, -s * 0.4)
      ..cubicTo(s * 0.5, -s * 1.1, s * 1.4, -s * 0.2, 0, s * 0.7)
      ..close();
    canvas.drawPath(path, paint);
  }

  // ── Boys: neon streaks sweeping across ────────────────────────────────────
  void _paintBoys(Canvas canvas, Size size) {
    for (final p in particles) {
      final local = (t + p.phase) % 1.0;
      final y = p.x * size.height;
      final len = 60 + p.size * 14;
      // Travel further than the screen so a streak is never seen to stop.
      final x = local * (size.width + len * 2) - len;
      final fade = math.sin(local * math.pi).clamp(0.0, 1.0);
      final tint = p.kind == 0 ? colors.accent : colors.accent2;

      // A gradient along the streak gives it a head and a tail without
      // drawing several shapes.
      final rect = Rect.fromLTWH(x - len, y - 1, len, 2.2);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [tint.withOpacity(0), tint.withOpacity(0.55 * fade)],
        ).createShader(rect)
        ..strokeCap = StrokeCap.round;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);

      // Faint bloom at the leading edge — the "neon" part.
      canvas.drawCircle(
        Offset(x, y),
        2.6 + p.size * 0.25,
        Paint()
          ..color = tint.withOpacity(0.22 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_EffectsPainter o) =>
      o.t != t || o.style != style || o.colors != colors;
}
