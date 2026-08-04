import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../screens/pro_screen.dart';
import '../theme/brutal_theme.dart';

/// Shared Pro upsell for gated features (SigmaFit, favorite track, ...).
///
/// A modal sheet instead of a SnackBar: SnackBars are owned by the single
/// app-wide ScaffoldMessenger, so triggering one from a bottom-nav tab and
/// then switching tabs (IndexedStack swaps the visible child, it doesn't
/// change routes) left it sitting on screen indefinitely with no route
/// change to clear it. A modal sheet is scoped to the Navigator that opened
/// it and always dismisses on its own.
void showProUpsell(
  BuildContext context, {
  required Map user,
  required IconData icon,
  required String body,
}) {
  final c = context.k;
  showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _PulsingProIcon(icon: icon, colors: [c.accent, c.accent3]),
          const SizedBox(height: 16),
          Text(sheetCtx.t('proTitle'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accentFill,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.pop(sheetCtx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ProScreen(user: user)));
              },
              child: Text(sheetCtx.t('proBuyBtn'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// A gently breathing icon badge — scale + glow loop, so the upsell doesn't
/// read as just another static settings row. Subtle on purpose: this is a
/// sheet asking for money, not a game reward.
class _PulsingProIcon extends StatefulWidget {
  final IconData icon;
  final List<Color> colors;
  const _PulsingProIcon({required this.icon, required this.colors});

  @override
  State<_PulsingProIcon> createState() => _PulsingProIconState();
}

class _PulsingProIconState extends State<_PulsingProIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final scale = 1.0 + 0.08 * t;
        final glow = 8.0 + 10.0 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: widget.colors),
              boxShadow: [
                BoxShadow(
                  color: widget.colors.last.withOpacity(0.35 + 0.25 * t),
                  blurRadius: glow,
                  spreadRadius: 1 + 2 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Icon(widget.icon, color: Colors.white, size: 30),
    );
  }
}
