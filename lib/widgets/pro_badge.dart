import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/brutal_theme.dart';
import 'pro_badge_picker.dart';

/// The badge shown next to a Pro user's name: their chosen GIF, or the default
/// "PRO" chip when they haven't picked one.
///
/// Entitlement is enforced on the READ path — nothing renders unless [isPro] —
/// so a lapsed subscription falls back to no badge without having to wipe the
/// stored GIF. If they resubscribe, their choice is still there.
class ProBadge extends StatelessWidget {
  final bool isPro;

  /// Giphy URL, or null for the default chip.
  final String? gifUrl;
  final double height;

  /// Opens the picker. Only wired on your own profile.
  final VoidCallback? onTap;

  const ProBadge({
    super.key,
    required this.isPro,
    this.gifUrl,
    this.height = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPro) return const SizedBox.shrink();
    final c = context.k;
    final url = gifUrl;

    // An emoji badge is stored in the same field as a GIF URL — anything that
    // isn't a URL is an emoji. One column, because they're the same choice from
    // the user's point of view.
    if (isEmojiBadge(url)) {
      final child = Text(url!, style: TextStyle(fontSize: height * 0.9));
      return onTap == null
          ? child
          : GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: onTap, child: child);
    }

    final child = (url == null || url.isEmpty)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: c.accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6)),
            child: Text('PRO',
                style: TextStyle(
                    color: c.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: CachedNetworkImage(
              imageUrl: url,
              height: height,
              fit: BoxFit.contain,
              // A badge must never become a layout hole or a broken-image icon
              // in the middle of someone's name — both states fall back to a
              // fixed-size placeholder, then to the plain chip.
              placeholder: (_, __) => SizedBox(height: height, width: height),
              errorWidget: (_, __, ___) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('PRO',
                    style: TextStyle(
                        color: c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          );

    if (onTap == null) return child;
    // Opaque + padded: the chip is ~34x18, which is well under a comfortable
    // touch target, and this is the only way to reach the badge picker.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: child,
      ),
    );
  }
}
