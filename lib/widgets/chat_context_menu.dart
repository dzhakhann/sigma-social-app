import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/brutal_theme.dart';

/// One row in the floating long-press menu (Reply/Forward/Copy/…).
class MenuAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  MenuAction(this.icon, this.label, this.color, this.onTap);
}

/// Telegram-style long-press message menu: the bubble scales up in place
/// behind a blurred backdrop, a quick-reaction emoji strip floats just above
/// the floating action menu. Shared by 1:1 and group chat so both look and
/// behave identically (previously group chat used a separate plain
/// `showModalBottomSheet` here, which is what this replaces).
class ChatContextMenu extends StatelessWidget {
  final Animation<double> animation;
  final Offset origin;
  final Size size;
  final Size screenSize;
  final bool isOwn;
  final BrutalColors c;
  final Widget bubble;
  final List<MenuAction> actions;

  /// Reaction strip — omitted entirely when [onReact] is null.
  final List<String> quickReactions;
  final String? myReaction;
  final ValueChanged<String>? onReact;

  const ChatContextMenu({
    super.key,
    required this.animation,
    required this.origin,
    required this.size,
    required this.screenSize,
    required this.isOwn,
    required this.c,
    required this.bubble,
    required this.actions,
    this.quickReactions = const [],
    this.myReaction,
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final fade = animation.value.clamp(0.0, 1.0);
        final spring = Curves.easeOutBack.transform(fade);
        const menuWidth = 208.0;
        final showReactions = onReact != null && quickReactions.isNotEmpty;
        const reactionsH = 52.0;
        final menuHeight = actions.length * 46.0 + 16;
        final totalHeight = menuHeight + (showReactions ? reactionsH : 0);
        final spaceBelow = screenSize.height - (origin.dy + size.height);
        final showBelow =
            spaceBelow > totalHeight + 24 || origin.dy < totalHeight + 24;
        final blockTop = showBelow
            ? origin.dy + size.height + 8
            : (origin.dy - totalHeight - 8).clamp(40.0, screenSize.height);
        final menuLeft =
            (isOwn ? origin.dx + size.width - menuWidth : origin.dx)
                .clamp(12.0, screenSize.width - menuWidth - 12);

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Stack(children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter:
                      ui.ImageFilter.blur(sigmaX: 6 * fade, sigmaY: 6 * fade),
                  child:
                      Container(color: Colors.black.withOpacity(0.32 * fade)),
                ),
              ),
              // The bubble itself, scaled up slightly in its exact place —
              // purely decorative, so taps fall through to the backdrop.
              Positioned(
                left: origin.dx,
                top: origin.dy,
                width: size.width,
                height: size.height,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * spring,
                    alignment:
                        isOwn ? Alignment.centerRight : Alignment.centerLeft,
                    child: bubble,
                  ),
                ),
              ),
              Positioned(
                left: menuLeft,
                top: blockTop,
                width: menuWidth,
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: 0.82 + 0.18 * spring,
                    alignment: showBelow
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showReactions && showBelow) ...[
                          _reactionStrip(context),
                          const SizedBox(height: 8),
                        ],
                        _menuCard(context),
                        if (showReactions && !showBelow) ...[
                          const SizedBox(height: 8),
                          _reactionStrip(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _reactionStrip(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final e in quickReactions)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.of(context).pop();
                  onReact!(e);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: e == myReaction
                      ? BoxDecoration(
                          color: c.accent.withOpacity(0.16),
                          shape: BoxShape.circle,
                        )
                      : null,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(e, style: const TextStyle(fontSize: 21)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _menuCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.ink.withOpacity(0.06)),
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                actions[i].onTap();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Text(actions[i].label,
                        style: TextStyle(
                            color: actions[i].color,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5)),
                  ),
                  Icon(actions[i].icon, color: actions[i].color, size: 19),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wraps a message bubble so long-press opens the menu anchored to that
/// bubble's real on-screen rect.
///
/// The rect comes from this widget's own RenderBox instead of a screen-level
/// `Map<String, GlobalKey>`. The map version silently did nothing whenever the
/// key failed to resolve — a list rebuild, or the optimistic `tmp_…` id being
/// swapped for the server id, both orphan the key — and it grew by one entry
/// per message with nothing ever pruning it.
class MessageLongPress extends StatelessWidget {
  final Widget child;
  final void Function(Offset origin, Size size) onMenu;

  const MessageLongPress({
    super.key,
    required this.child,
    required this.onMenu,
  });

  /// Flutter's default long-press is 500ms, which feels sluggish next to
  /// Telegram. RawGestureDetector is the only way to shorten it — GestureDetector
  /// doesn't expose the duration.
  static const pressDuration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (inner) => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: pressDuration),
            (recognizer) {
              // onLongPressStart, not onLongPress: it carries the touch
              // position, so the menu can still be anchored even if the
              // RenderBox lookup fails.
              recognizer.onLongPressStart = (details) {
                final box = inner.findRenderObject() as RenderBox?;
                if (box != null && box.attached) {
                  onMenu(box.localToGlobal(Offset.zero), box.size);
                } else {
                  // Degrade to a rect at the finger rather than doing nothing.
                  // Silently returning here is exactly how this feature
                  // "disappeared" before.
                  onMenu(details.globalPosition, const Size(1, 1));
                }
              };
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Shows the menu with the Telegram-style spring/blur transition. Callers
/// supply the bubble's on-screen rect (see [MessageLongPress]) so the
/// animation can scale it up in place.
Future<void> showChatContextMenu(
  BuildContext context, {
  required Offset origin,
  required Size size,
  required bool isOwn,
  required BrutalColors c,
  required Widget bubble,
  required List<MenuAction> actions,
  List<String> quickReactions = const [],
  String? myReaction,
  ValueChanged<String>? onReact,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dctx, anim, __) => ChatContextMenu(
      animation: anim,
      origin: origin,
      size: size,
      screenSize: MediaQuery.of(context).size,
      isOwn: isOwn,
      c: c,
      bubble: bubble,
      actions: actions,
      quickReactions: quickReactions,
      myReaction: myReaction,
      onReact: onReact,
    ),
    transitionBuilder: (_, __, ___, child) => child,
  );
}
