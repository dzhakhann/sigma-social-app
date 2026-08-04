import 'dart:convert' show base64Decode;
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/chat_wallpaper.dart';
import '../theme/brutal_theme.dart';

/// Renders a chat wallpaper: a multi-stop gradient with an optional procedural
/// pattern tiled over it.
///
/// The pattern is drawn, not shipped as an image — that's what lets a wallpaper
/// stay a handful of numbers in SharedPreferences instead of a downloaded asset,
/// and it scales to any screen without a seam. It's also what makes these read
/// as designed backgrounds rather than the flat two-colour ramps they were.
class ChatBackground extends StatelessWidget {
  /// Stored wallpaper map, or null for the plain themed background.
  final Map? wallpaper;
  final Widget child;

  const ChatBackground({super.key, required this.wallpaper, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final w = wallpaper;
    if (w == null) return ColoredBox(color: c.bg, child: child);

    // A gallery photo is still supported — it just has no pattern over it.
    // Web has no filesystem to hold a permanent copy in (no path_provider
    // build), so its picker stores the bytes as base64 instead — see
    // ChatDetailScreen._pickWallpaperPhoto.
    if (w['type'] == 'image' && w['dataB64'] != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: MemoryImage(base64Decode(w['dataB64'].toString())),
            fit: BoxFit.cover,
          ),
        ),
        child: child,
      );
    }
    if (w['type'] == 'image' && w['path'] != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(File(w['path'].toString())),
            fit: BoxFit.cover,
          ),
        ),
        child: child,
      );
    }

    final preset = ChatWallpaper.presetById(w['id']);
    if (preset == null) return ColoredBox(color: c.bg, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: preset.colors.map((v) => Color(v)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: preset.pattern == WallpaperPattern.none
          ? child
          : Stack(children: [
              // Pattern never intercepts input and repaints only on resize.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PatternPainter(preset.pattern),
                    ),
                  ),
                ),
              ),
              child,
            ]),
    );
  }
}

/// Static pattern overlay. Deliberately low-contrast white/black at a few
/// percent opacity: a chat background has to stay readable under text, so the
/// pattern is texture rather than decoration you'd notice on its own.
class _PatternPainter extends CustomPainter {
  final WallpaperPattern pattern;

  _PatternPainter(this.pattern);

  @override
  void paint(Canvas canvas, Size size) {
    // Arcs are two full-height curves, not a tiled motif — they're drawn once
    // against the whole canvas instead of going through the tiling loop below.
    if (pattern == WallpaperPattern.arcs) {
      _arcs(canvas, size);
      return;
    }
    final paint = Paint()..color = Colors.white.withOpacity(0.055);
    const step = 54.0;
    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;

    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        // Offset every other row so the tiling doesn't read as a grid.
        final x = col * step + (r.isEven ? 0 : step / 2);
        final y = r * step;
        canvas.save();
        canvas.translate(x, y);
        switch (pattern) {
          case WallpaperPattern.dots:
            canvas.drawCircle(Offset.zero, 3.4, paint);
            break;
          case WallpaperPattern.rings:
            canvas.drawCircle(
                Offset.zero,
                8,
                Paint()
                  ..color = paint.color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.4);
            break;
          case WallpaperPattern.hearts:
            _heart(canvas, 7, paint);
            break;
          case WallpaperPattern.stars:
            _star(canvas, 7, paint);
            break;
          case WallpaperPattern.waves:
            _wave(canvas, step, paint);
            break;
          case WallpaperPattern.none:
          case WallpaperPattern.arcs:
            // arcs never reaches the tiling loop — handled above.
            break;
        }
        canvas.restore();
      }
    }
  }

  /// Left `|)` and right `(|`: two arcs bulging toward the centre, each with a
  /// soft outer glow and a brighter core line. Control points are fractions of
  /// the canvas, so the shape is identical on any screen.
  void _arcs(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    for (final left in [true, false]) {
      // Anchored off-screen at top and bottom so neither end is visible.
      final x0 = left ? -w * 0.10 : w * 1.10;
      final bulge = left ? w * 0.46 : w * 0.54;
      final path = Path()
        ..moveTo(x0, -h * 0.05)
        ..cubicTo(bulge, h * 0.22, bulge, h * 0.78, x0, h * 1.05);

      // Wide, very faint bloom first…
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..color = Colors.white.withOpacity(0.030)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      // …then a thin bright core, which is what reads as a light edge.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withOpacity(0.085),
      );
    }
  }

  void _heart(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(0, s * 0.7)
      ..cubicTo(-s * 1.4, -s * 0.2, -s * 0.5, -s * 1.1, 0, -s * 0.4)
      ..cubicTo(s * 0.5, -s * 1.1, s * 1.4, -s * 0.2, 0, s * 0.7)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _star(Canvas canvas, double s, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? s : s * 0.42;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _wave(Canvas canvas, double step, Paint paint) {
    final stroke = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(-step / 2, 0)
      ..quadraticBezierTo(-step / 4, -7, 0, 0)
      ..quadraticBezierTo(step / 4, 7, step / 2, 0);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_PatternPainter o) => o.pattern != pattern;
}
