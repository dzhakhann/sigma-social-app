import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/pro_state.dart';
import '../services/profile_background.dart';
import '../theme/brutal_theme.dart';
import 'pro_upsell_sheet.dart';

class _Particle {
  final double x0, size, phase, swayAmp, swayFreq, opacity, rotSpeed;
  final TextPainter? tp;
  const _Particle({
    required this.x0,
    required this.size,
    required this.phase,
    required this.swayAmp,
    required this.swayFreq,
    required this.opacity,
    required this.rotSpeed,
    this.tp,
  });
}

List<_Particle> _generateParticles(ProfileBackgroundPreset p) {
  final rnd = math.Random(p.id.hashCode);
  return List.generate(p.count, (i) {
    final size = p.minSize + rnd.nextDouble() * (p.maxSize - p.minSize);
    TextPainter? tp;
    if (p.shape == ParticleShape.glyph && p.glyphs.isNotEmpty) {
      final glyph = p.glyphs[rnd.nextInt(p.glyphs.length)];
      // Laid out ONCE here, not per animation frame — the painter just blits
      // this same TextPainter at a new offset every tick.
      tp = TextPainter(
        text: TextSpan(text: glyph, style: TextStyle(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    return _Particle(
      x0: rnd.nextDouble(),
      size: size,
      phase: rnd.nextDouble(),
      swayAmp: 0.015 + rnd.nextDouble() * 0.04,
      swayFreq: 1 + rnd.nextDouble() * 2,
      opacity: 0.35 + rnd.nextDouble() * 0.45,
      rotSpeed: (rnd.nextDouble() - 0.5) * 2,
      tp: tp,
    );
  });
}

/// Telegram-style animated particle background for the profile screen.
/// Renders behind [child]; a null preset just shows the plain theme colour.
class ProfileBackgroundView extends StatefulWidget {
  final ProfileBackgroundPreset? preset;
  final Widget child;
  const ProfileBackgroundView(
      {super.key, required this.preset, required this.child});

  @override
  State<ProfileBackgroundView> createState() => _ProfileBackgroundViewState();
}

class _ProfileBackgroundViewState extends State<ProfileBackgroundView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 22))
        ..repeat();
  List<_Particle> _particles = const [];

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    if (p != null) _particles = _generateParticles(p);
  }

  @override
  void didUpdateWidget(covariant ProfileBackgroundView old) {
    super.didUpdateWidget(old);
    if (old.preset?.id != widget.preset?.id) {
      final p = widget.preset;
      _particles = p == null ? const [] : _generateParticles(p);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final p = widget.preset;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: c.bg,
          gradient: p == null
              ? null
              : LinearGradient(
                  colors: p.colors.map((v) => Color(v)).toList(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        ),
      ),
      if (p != null)
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticlePainter(
                _particles, _ctrl.value, p.shape, p.rising, p.particleColor),
            size: Size.infinite,
          ),
        ),
      widget.child,
    ]);
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final ParticleShape shape;
  final bool rising;
  final int colorValue;
  _ParticlePainter(
      this.particles, this.t, this.shape, this.rising, this.colorValue);

  @override
  void paint(Canvas canvas, Size size) {
    for (final pt in particles) {
      final progress = (t + pt.phase) % 1.0;
      final travel = rising ? (1 - progress) : progress;
      final dx = (pt.x0 + math.sin(progress * 2 * math.pi * pt.swayFreq) * pt.swayAmp) *
          size.width;
      final dy = travel * size.height;
      // Fades across the loop seam so nothing pops in/out abruptly.
      double fade = 1.0;
      if (progress < 0.08) {
        fade = progress / 0.08;
      } else if (progress > 0.92) {
        fade = (1 - progress) / 0.08;
      }
      final opacity = (pt.opacity * fade).clamp(0.0, 1.0);
      if (opacity <= 0.01) continue;

      if (pt.tp != null) {
        final tp = pt.tp!;
        // A tightly-bounded saveLayer is the only way to alpha-blend a whole
        // glyph (colour emoji ignore TextStyle.color, so tinting the paint
        // directly wouldn't fade them) — bounding it to just the glyph's own
        // rect keeps the offscreen buffer tiny instead of the whole canvas.
        final rect = Rect.fromCenter(
            center: Offset(dx, dy), width: tp.width + 4, height: tp.height + 4);
        canvas.saveLayer(rect, Paint()..color = Colors.white.withOpacity(opacity));
        tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
        canvas.restore();
      } else if (shape == ParticleShape.circle) {
        canvas.drawCircle(Offset(dx, dy), pt.size / 2,
            Paint()..color = Color(colorValue).withOpacity(opacity));
      } else {
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(progress * 2 * math.pi * pt.rotSpeed);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: pt.size, height: pt.size * 0.6),
            Radius.circular(pt.size * 0.15),
          ),
          Paint()..color = Color(colorValue).withOpacity(opacity),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}

/// Static (non-animated) preview for the picker grid — six live particle
/// fields running at once in a sheet would just be a fresh performance
/// problem to replace the one this session already fixed. A fixed scatter of
/// the same glyphs/shapes at half density gives an honest preview instead.
class ProfileBackgroundSwatch extends StatelessWidget {
  final ProfileBackgroundPreset preset;
  const ProfileBackgroundSwatch({super.key, required this.preset});

  @override
  Widget build(BuildContext context) {
    final particles = _generateParticles(preset)
        .take((preset.count / 2).ceil())
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: preset.colors.map((v) => Color(v)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _ParticlePainter(
            particles, 0.35, preset.shape, preset.rising, preset.particleColor),
        size: Size.infinite,
      ),
    );
  }
}

/// Opens the background picker. Returns the chosen preset id, `''` to clear,
/// or null if dismissed without a choice.
Future<String?> showProfileBackgroundPicker(
  BuildContext context, {
  required String? current,
  required Map user,
}) {
  final c = context.k;
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => _PickerBody(current: current, user: user),
  );
}

class _PickerBody extends StatelessWidget {
  final String? current;
  final Map user;
  const _PickerBody({required this.current, required this.user});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ValueListenableBuilder<bool>(
      valueListenable: ProState.isPro,
      builder: (_, hasPro, __) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: c.inkSoft.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Text(context.t('profileBgTitle'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
              children: [
                _noneSwatch(context, c),
                for (final p in ProfileBackgrounds.catalog)
                  _swatch(context, c, p, hasPro),
              ],
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(context.t('resetWallpaper'),
                  style: TextStyle(color: c.inkSoft)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _noneSwatch(BuildContext context, BrutalColors c) {
    final selected = current == null || current!.isEmpty;
    return GestureDetector(
      onTap: () => Navigator.pop(context, ''),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? c.accent : c.ink.withOpacity(0.08),
              width: selected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.not_interested_rounded, color: c.inkSoft, size: 22),
      ),
    );
  }

  Widget _swatch(
      BuildContext context, BrutalColors c, ProfileBackgroundPreset p, bool hasPro) {
    final locked = p.pro && !hasPro;
    final selected = current == p.id;
    return GestureDetector(
      onTap: () {
        if (locked) {
          Navigator.pop(context);
          showProUpsell(context,
              user: user,
              icon: Icons.wallpaper_rounded,
              body: context.t('profileBgProOnly'));
          return;
        }
        Navigator.pop(context, p.id);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(fit: StackFit.expand, children: [
          ProfileBackgroundSwatch(preset: p),
          if (selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: c.accent, width: 2.5),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          if (locked)
            Container(
              color: Colors.black.withOpacity(0.35),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
            ),
        ]),
      ),
    );
  }
}
