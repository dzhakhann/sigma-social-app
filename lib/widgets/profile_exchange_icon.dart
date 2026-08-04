import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Apple-NameDrop-style animation for the "Profile exchange" action: two phones
/// facing each other while a little profile card flies contactlessly from one to
/// the other, with a soft signal pulse in the gap. Pure vector + animation, so
/// it stays crisp at any size and needs no asset.
class ProfileExchangeIcon extends StatefulWidget {
  final double size;
  final Color color;
  const ProfileExchangeIcon({Key? key, this.size = 56, required this.color})
      : super(key: key);

  @override
  State<ProfileExchangeIcon> createState() => _ProfileExchangeIconState();
}

class _ProfileExchangeIconState extends State<ProfileExchangeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _ExchangePainter(t: _c.value, color: widget.color),
        ),
      ),
    );
  }
}

class _ExchangePainter extends CustomPainter {
  final double t; // 0..1 loop
  final Color color;
  _ExchangePainter({required this.t, required this.color});

  double _easeInOut(double x) {
    if (x < 0.5) return 2 * x * x;
    final v = -2 * x + 2;
    return 1 - (v * v) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2, cy = size.height / 2;
    final center = Offset(cx, cy);

    // Gentle "breathing" — the phones lean a touch toward each other and back.
    final breathe = math.sin(t * 2 * math.pi);
    final lean = 0.09 + 0.03 * breathe; // radians

    // ── Signal pulse in the gap (behind the phones) ───────────────────────
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final r = (0.05 + 0.24 * phase) * s;
      final op = (1 - phase).clamp(0.0, 1.0) * 0.5;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withOpacity(op),
      );
    }

    // ── The two phones ────────────────────────────────────────────────────
    _phone(canvas, Offset(cx - 0.26 * s, cy), -lean, s);
    _phone(canvas, Offset(cx + 0.26 * s, cy), lean, s);

    // ── Profile card flying across, ping-ponging left↔right ───────────────
    // Triangle wave so it goes there and back; fades at both ends.
    final tri = t < 0.5 ? t * 2 : (1 - t) * 2; // 0→1→0
    final e = _easeInOut(tri);
    final startX = cx - 0.17 * s, endX = cx + 0.17 * s;
    final chipX = startX + (endX - startX) * e;
    final chipY = cy - 0.20 * s * math.sin(e * math.pi); // slight arc
    final fade = math.sin(tri * math.pi).clamp(0.0, 1.0);
    _chip(canvas, Offset(chipX, chipY), s, fade);
  }

  void _phone(Canvas canvas, Offset center, double angle, double s) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final w = 0.30 * s, h = 0.62 * s, r = 0.06 * s;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(r),
    );
    // Soft shadow + accent body.
    canvas.drawRRect(
      body.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withOpacity(0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(body, Paint()..color = color);

    // White screen.
    final screen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.78, height: h * 0.84),
      Radius.circular(r * 0.7),
    );
    canvas.drawRRect(screen, Paint()..color = Colors.white.withOpacity(0.95));

    // Person glyph on the screen (head + shoulders).
    final glyph = Paint()..color = color;
    canvas.drawCircle(Offset(0, -h * 0.14), w * 0.13, glyph);
    final shoulders = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(0, h * 0.10), width: w * 0.42, height: h * 0.22),
      Radius.circular(w * 0.18),
    );
    canvas.drawRRect(shoulders, glyph);

    canvas.restore();
  }

  void _chip(Canvas canvas, Offset at, double s, double fade) {
    if (fade <= 0.02) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    final w = 0.20 * s, h = 0.14 * s;
    final card = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(0.03 * s),
    );
    canvas.drawRRect(
      card.shift(const Offset(0, 1)),
      Paint()..color = Colors.black.withOpacity(0.16 * fade),
    );
    canvas.drawRRect(card, Paint()..color = color.withOpacity(fade));
    // tiny avatar dot + line on the card
    final white = Paint()..color = Colors.white.withOpacity(fade);
    canvas.drawCircle(Offset(-w * 0.22, 0), h * 0.22, white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.12, 0), width: w * 0.42, height: h * 0.16),
        Radius.circular(h * 0.08),
      ),
      white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ExchangePainter old) =>
      old.t != t || old.color != color;
}
