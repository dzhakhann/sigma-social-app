import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// Human-readable timestamps, Telegram-style.
///
/// One implementation because the same "today / yesterday / 15 July" decision is
/// needed by the chat header, group member lists and anywhere else a last-seen
/// or a date has to be legible.
class HumanTime {
  HumanTime._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _month(BuildContext context, int month) {
    final months = context.t('monthsShort').split(',');
    return (month - 1) < months.length ? months[month - 1].trim() : '';
  }

  /// How many calendar days [t] is before today. 0 = today, 1 = yesterday.
  ///
  /// Compared by DATE, not by elapsed hours. Elapsed hours is what made the
  /// chat header show a bare "last seen at 20:54" at 11:25 the NEXT morning —
  /// only ~14 hours had passed, so it never reached the "show a date" branch and
  /// there was no way to tell which day it meant.
  static int daysAgo(DateTime t) {
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(t.year, t.month, t.day);
    return a.difference(b).inDays;
  }

  /// "5 min ago" / "today at 20:54" / "yesterday at 20:54" /
  /// "15 Jul at 20:54" / "15 Jul 2025 at 20:54".
  static String lastSeen(BuildContext context, DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 70) return context.t('online');
    if (diff.inMinutes < 60) {
      return context.t('lastSeenMin').replaceAll('{n}', '${diff.inMinutes}');
    }
    final days = daysAgo(t);
    if (days <= 0) {
      return context.t('lastSeenToday').replaceAll('{t}', _hm(t));
    }
    if (days == 1) {
      return context.t('lastSeenYesterday').replaceAll('{t}', _hm(t));
    }
    // The year only earns its place once it isn't the current one.
    final sameYear = t.year == DateTime.now().year;
    final date = sameYear
        ? '${t.day} ${_month(context, t.month)}'
        : '${t.day} ${_month(context, t.month)} ${t.year}';
    return context
        .t('lastSeenOn')
        .replaceAll('{d}', date)
        .replaceAll('{t}', _hm(t));
  }
}
