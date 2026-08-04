import 'package:flutter/material.dart';

import 'pro_badge.dart';

/// The verification checkmark shown next to a verified user's name.
///
/// One widget for the whole app. It used to be an inline `Icon(
/// Icons.verified_rounded)` repeated in seven screens, each picking its own
/// colour — several used `c.ink`, the primary *text* colour, so the badge was
/// black in some places and accent-coloured in others.
///
/// The blue is deliberately FIXED rather than themed. It's a trust signal that
/// has to look the same everywhere, and it already matches the badge rendered
/// in the CRM panel; letting it follow the palette would turn it pink in the
/// Girls theme and read as decoration rather than verification.
class VerifiedBadge extends StatelessWidget {
  final double size;

  const VerifiedBadge({super.key, this.size = 14});

  /// Sigmacta verification blue — same value as the CRM panel's badge.
  static const Color color = Color(0xFF4F7CFF);

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified_rounded, size: size, color: color);
}

/// A name followed by its status markers: the verification check, then the Pro
/// badge (the user's GIF, or the default chip).
///
/// One widget for both so the order and spacing can't drift between screens —
/// verification first, Pro second, everywhere.
class VerifiedName extends StatelessWidget {
  final String name;
  final bool verified;

  /// Pro badge. Renders nothing unless [isPro]; [proBadgeGif] null falls back
  /// to the plain PRO chip.
  final bool isPro;
  final String? proBadgeGif;

  final TextStyle? style;
  final double badgeSize;

  /// Constrains the text so a long name ellipsises instead of pushing the
  /// badges off-screen. Set false inside an already-bounded Row.
  final bool flexible;

  const VerifiedName({
    super.key,
    required this.name,
    required this.verified,
    this.isPro = false,
    this.proBadgeGif,
    this.style,
    this.badgeSize = 14,
    this.flexible = true,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        flexible ? Flexible(child: text) : text,
        if (verified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(size: badgeSize),
        ],
        if (isPro) ...[
          const SizedBox(width: 4),
          ProBadge(
              isPro: true, gifUrl: proBadgeGif, height: badgeSize + 4),
        ],
      ],
    );
  }
}
