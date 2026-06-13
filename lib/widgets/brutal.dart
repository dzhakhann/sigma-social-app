import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
//  REUSABLE CLEAN MODERN WIDGETS
//  Soft press animation, subtle shadows, smooth transitions.
// ════════════════════════════════════════════════════════════════════════════

/// A pressable card that scales down slightly on press — feels tactile & clean.
class BrutalTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? borderColor;
  final double radius;
  final double border;
  final EdgeInsets padding;
  final Offset shadowOffset;

  const BrutalTap({
    super.key,
    required this.child,
    this.onTap,
    this.fill,
    this.borderColor,
    this.radius = 16,
    this.border = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.shadowOffset = const Offset(0, 2),
  });

  @override
  State<BrutalTap> createState() => _BrutalTapState();
}

class _BrutalTapState extends State<BrutalTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.fill ?? c.surface,
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.border > 0
                ? Border.all(
                    color: widget.borderColor ?? c.ink.withOpacity(0.1),
                    width: widget.border)
                : null,
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Clean card with subtle shadow.
class BrutalCard extends StatelessWidget {
  final Widget child;
  final Color? fill;
  final Color? borderColor;
  final double radius;
  final double border;
  final EdgeInsets padding;
  final Offset shadowOffset;

  const BrutalCard({
    super.key,
    required this.child,
    this.fill,
    this.borderColor,
    this.radius = 18,
    this.border = 0,
    this.padding = const EdgeInsets.all(16),
    this.shadowOffset = const Offset(0, 2),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      padding: padding,
      decoration: cleanCard(c, fill: fill, radius: radius),
      child: child,
    );
  }
}

/// Frosted-glass panel: translucent fill + backdrop blur + hairline border.
/// Use sparingly (blur is GPU-costly) — e.g. the floating side nav.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blur;
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(8),
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.surface.withOpacity(0.62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                  color: c.shadow, blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small label chip used as section markers.
class BrutalLabel extends StatelessWidget {
  final String text;
  final Color? fill;
  final Color? textColor;
  const BrutalLabel(this.text, {super.key, this.fill, this.textColor});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final bg = fill ?? c.accent;
    final auto = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? auto,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
