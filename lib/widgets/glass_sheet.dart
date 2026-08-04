import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brutal_theme.dart';

/// One large card inside a [showGlassSheet] — icon tile, title, subtitle.
class GlassAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Overrides the accent tint of the icon tile. Defaults to `c.accent`.
  final Color? tint;

  /// Renders the title in `c.danger` and tints the tile red.
  final bool destructive;

  const GlassAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tint,
    this.destructive = false,
  });
}

/// Frosted-glass action sheet: blurred backdrop, translucent rounded panel and
/// large tappable cards that fade+slide in one after another.
///
/// Replaces the stock `showModalBottomSheet` + `ListTile` stack used across the
/// app, which read as a plain system menu. The entrance is driven entirely off
/// the route animation (one controller, no per-card tickers) so the stagger
/// stays cheap at 60 FPS.
Future<void> showGlassSheet(
  BuildContext context, {
  required String title,
  required List<GlassAction> actions,
  String? subtitle,
}) {
  final c = context.k;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.34),
    isScrollControlled: true,
    builder: (sheetCtx) =>
        _GlassSheet(c: c, title: title, subtitle: subtitle, actions: actions),
  );
}

class _GlassSheet extends StatelessWidget {
  final BrutalColors c;
  final String title;
  final String? subtitle;
  final List<GlassAction> actions;

  const _GlassSheet({
    required this.c,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final t = anim.value.clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 26 * t, sigmaY: 26 * t),
              child: Container(
                decoration: BoxDecoration(
                  // Translucent so the blurred content behind shows through —
                  // an opaque fill would defeat the BackdropFilter entirely.
                  color: c.surface.withOpacity(c.isDark ? 0.72 : 0.82),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: c.ink.withOpacity(c.isDark ? 0.10 : 0.06),
                      width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.22),
                        blurRadius: 34,
                        offset: const Offset(0, 10)),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.inkSoft.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(title,
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                    ],
                    const SizedBox(height: 14),
                    for (var i = 0; i < actions.length; i++)
                      _card(context, actions[i], i, t),
                    const SizedBox(height: 6),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, GlassAction a, int i, double t) {
    // Each card owns a slice of the route animation, offset by its index, so
    // they cascade instead of arriving as one block.
    final start = (i * 0.09).clamp(0.0, 0.5);
    final local =
        Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic)
            .transform(t);
    final tint = a.destructive ? c.danger : (a.tint ?? c.accent);

    return Opacity(
      opacity: local,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - local)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Material(
            color: c.surface2.withOpacity(c.isDark ? 0.55 : 0.75),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
                a.onTap();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tint.withOpacity(0.26), tint.withOpacity(0.12)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(a.icon, color: tint, size: 23),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(a.title,
                            style: TextStyle(
                                color: a.destructive ? c.danger : c.ink,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(a.subtitle,
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 12.3, height: 1.25)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: c.inkSoft.withOpacity(0.55), size: 20),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
