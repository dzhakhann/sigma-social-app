import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

/// Centred "24 May" separator between days, with a hairline either side.
///
/// Rendered from inside the list's itemBuilder rather than as its own list
/// entry: injecting header rows would shift every index and break the
/// message-index bookkeeping that in-chat search and the scroll-to-message
/// anchors rely on.
class ChatDateDivider extends StatelessWidget {
  final DateTime day;

  const ChatDateDivider({super.key, required this.day});

  /// True when both timestamps fall on the same local calendar day.
  /// Null-safe: an unparseable timestamp counts as "same day" so a bad row
  /// can't sprout a spurious separator.
  static bool sameDay(dynamic a, dynamic b) {
    final da = parse(a), db = parse(b);
    if (da == null || db == null) return true;
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  /// Server timestamps arrive without a 'Z' despite being UTC — always via
  /// parseServerTime, never bare DateTime.parse.
  static DateTime? parse(dynamic raw) {
    if (raw == null) return null;
    try {
      return ApiService.parseServerTime(raw.toString());
    } catch (_) {
      return null;
    }
  }

  String _label(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    if (isToday) return context.t('today');
    final y = now.subtract(const Duration(days: 1));
    if (day.year == y.year && day.month == y.month && day.day == y.day) {
      return context.t('yesterday');
    }
    final months = context.t('monthsShort').split(',');
    final name =
        (day.month - 1) < months.length ? months[day.month - 1].trim() : '';
    // The year only earns its place once it stops being the current one.
    return day.year == now.year
        ? '${day.day} $name'
        : '${day.day} $name ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(
            child: Divider(color: c.ink.withOpacity(0.10), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(_label(context),
              style: TextStyle(
                  color: c.inkSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2)),
        ),
        Expanded(
            child: Divider(color: c.ink.withOpacity(0.10), thickness: 1)),
      ]),
    );
  }
}
