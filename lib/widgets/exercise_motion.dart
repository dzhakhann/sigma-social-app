import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/exercises_data.dart';

/// A lightweight, always-on-device motion cue for SigmaFit's exercise icon —
/// deliberately NOT a real photo/video form demo. Bundling actual exercise
/// GIFs/video would mean hosting third-party media (licensing + CDN cost),
/// which breaks this feature's "zero extra server/CDN cost" design (see
/// exercises_data.dart); a real 3D model+renderer is a much bigger lift than
/// a timed bodyweight-circuit screen warrants. This animates the SAME Material
/// icon already used everywhere in the app with a simple looping transform
/// (bounce/squash/tilt) chosen per [ExerciseMotion], so the exercise picker
/// and the workout player both feel alive instead of a static glyph.
class ExerciseMotionAnim extends StatefulWidget {
  final ExerciseMotion motion;
  final IconData icon;
  final Color color;
  final double size;
  const ExerciseMotionAnim({
    super.key,
    required this.motion,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  State<ExerciseMotionAnim> createState() => _ExerciseMotionAnimState();
}

class _ExerciseMotionAnimState extends State<ExerciseMotionAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon, size: widget.size, color: widget.color);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * math.pi;
        final wave = math.sin(t); // -1..1
        final bounce = wave.abs(); // 0..1, double-speed up/down
        switch (widget.motion) {
          case ExerciseMotion.squat:
            // Sink down into the squat, spring back up.
            return Transform.translate(
              offset: Offset(0, bounce * 10),
              child: Transform.scale(
                  scaleY: 1 - bounce * 0.16, scaleX: 1 + bounce * 0.06, child: icon),
            );
          case ExerciseMotion.pushup:
            // Body lowers/raises; a slight tilt sells the arm bend.
            return Transform.translate(
              offset: Offset(0, bounce * 8),
              child: Transform.rotate(angle: wave * 0.05, child: icon),
            );
          case ExerciseMotion.lunge:
            // Alternating forward/back weight shift.
            return Transform.translate(
                offset: Offset(wave * 12, 0), child: icon);
          case ExerciseMotion.jump:
            // Explosive up, soft landing.
            return Transform.translate(
              offset: Offset(0, -bounce * 16),
              child: Transform.rotate(angle: wave * 0.06, child: icon),
            );
          case ExerciseMotion.plank:
            // Held position — just a faint breathing wobble, no big motion.
            return Transform.translate(
                offset: Offset(0, wave * 1.6), child: icon);
          case ExerciseMotion.core:
            // Twist/crunch — rotation about the center.
            return Transform.rotate(angle: wave * 0.22, child: icon);
        }
      },
    );
  }
}
