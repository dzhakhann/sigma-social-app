import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A Dynamic-Island-style banner that grows out of a small pill at the top of
/// the screen into a card with an avatar, two lines of text and one action.
///
/// Built for Sigma Nearby's "found someone" moment, but deliberately generic —
/// in-app message notifications want exactly this shape.
///
/// Drop it into a [Stack] and drive [visible]; it animates itself in and out.
/// Swiping up dismisses.
class IslandBanner extends StatefulWidget {
  final bool visible;

  /// Leading circle — usually an avatar.
  final Widget? leading;
  final String title;
  final String subtitle;

  /// Trailing button. Hidden when [actionLabel] is null.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Swipe-up / tap-outside dismissal. Null makes the banner non-dismissible.
  final VoidCallback? onDismiss;

  final Color accent;

  const IslandBanner({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.leading,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  @override
  State<IslandBanner> createState() => _IslandBannerState();
}

class _IslandBannerState extends State<IslandBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Extra upward offset while the user drags the banner away.
  double _dragUp = 0;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _ctrl.forward();
  }

  @override
  void didUpdateWidget(IslandBanner old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _dragUp = 0;
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (widget.onDismiss == null) return;
    HapticFeedback.selectionClick();
    widget.onDismiss!();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        if (t == 0) return const SizedBox.shrink();

        // Two-stage entrance: the pill drops in first, then widens into the
        // card. Splitting it this way is what reads as "the notch grew",
        // rather than a card that simply faded in.
        final drop = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
        final grow =
            Curves.easeOutCubic.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));

        final maxW = MediaQuery.of(context).size.width - 28;
        final width = ui.lerpDouble(132, maxW, grow)!;
        final height = ui.lerpDouble(40, 92, grow)!;
        final radius = ui.lerpDouble(20, 28, grow)!;

        return Positioned(
          top: 8 - _dragUp,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, -70 * (1 - drop)),
            child: Opacity(
              opacity: (t / 0.25).clamp(0.0, 1.0),
              child: Center(
                child: GestureDetector(
                  onVerticalDragUpdate: (d) {
                    if (widget.onDismiss == null) return;
                    setState(() => _dragUp = (_dragUp - d.delta.dy).clamp(0, 140));
                  },
                  onVerticalDragEnd: (_) {
                    if (_dragUp > 40) {
                      _dismiss();
                    } else {
                      setState(() => _dragUp = 0);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: BackdropFilter(
                      // Constant sigma on purpose — animating blur forces a
                      // fresh backdrop render every frame and drops the entrance
                      // below 60 FPS on mid-range phones.
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: const Color(0xFF15171F).withOpacity(0.86),
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                              color: widget.accent.withOpacity(0.22 * grow),
                              width: 1),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 26,
                                offset: const Offset(0, 8)),
                            // Accent bloom, so the island feels lit from within
                            // once it has opened.
                            BoxShadow(
                                color: widget.accent.withOpacity(0.16 * grow),
                                blurRadius: 30,
                                spreadRadius: 1),
                          ],
                        ),
                        // The contents only exist once there's room for them —
                        // otherwise they'd overflow the collapsed pill.
                        child: grow < 0.35
                            ? _pillDots()
                            : Opacity(
                                opacity:
                                    ((grow - 0.35) / 0.65).clamp(0.0, 1.0),
                                child: _content(),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Placeholder shown while the pill is still too narrow for real content.
  Widget _pillDots() => Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (i) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: widget.accent.withOpacity(0.5 + 0.5 * (i == 1 ? 1 : 0)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );

  Widget _content() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.62), fontSize: 12.5)),
              ],
            ),
          ),
          if (widget.actionLabel != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onAction?.call();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    widget.accent,
                    widget.accent.withOpacity(0.75),
                  ]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.actionLabel!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ]),
      );
}
