import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sigma_social_app/l10n/human_time.dart';
import 'package:sigma_social_app/theme/brutal_theme.dart';

/// Pins the calendar-day logic. The bug this replaces compared ELAPSED HOURS,
/// so "yesterday 20:54" read at 11:25 the next morning was under 24h and never
/// showed a date at all.
void main() {
  Future<String> label(WidgetTester tester, DateTime t) async {
    String? out;
    await tester.pumpWidget(AppScope(
      config: const AppConfig(lang: 'en'),
      child: MaterialApp(
        home: Builder(builder: (ctx) {
          out = HumanTime.lastSeen(ctx, t);
          return const SizedBox();
        }),
      ),
    ));
    return out!;
  }

  testWidgets('a few minutes ago stays relative', (tester) async {
    final t = DateTime.now().subtract(const Duration(minutes: 5));
    expect(await label(tester, t), contains('5'));
  });

  testWidgets('earlier today says today', (tester) async {
    final now = DateTime.now();
    // Only meaningful when "earlier today" exists — skip just after midnight
    // rather than asserting something the clock makes impossible.
    if (now.hour < 3) return;
    final t = DateTime(now.year, now.month, now.day, 1, 5);
    expect(await label(tester, t), contains('today'));
  });

  testWidgets('yesterday says yesterday, not a bare time', (tester) async {
    final now = DateTime.now();
    final y = now.subtract(const Duration(days: 1));
    final t = DateTime(y.year, y.month, y.day, 20, 54);
    final out = await label(tester, t);
    expect(out, contains('yesterday'));
    expect(out, contains('20:54'));
  });

  testWidgets('older this year shows a day and month', (tester) async {
    final t = DateTime(DateTime.now().year, 1, 15, 20, 54);
    // January of the current year is >2 days back unless we're in early January.
    if (HumanTime.daysAgo(t) < 2) return;
    final out = await label(tester, t);
    expect(out, contains('15'));
    expect(out, contains('Jan'));
    expect(out, isNot(contains('${DateTime.now().year}')));
  });

  testWidgets('a previous year includes the year', (tester) async {
    final t = DateTime(DateTime.now().year - 1, 7, 15, 20, 54);
    final out = await label(tester, t);
    expect(out, contains('${DateTime.now().year - 1}'));
  });

  test('daysAgo counts calendar days, not elapsed hours', () {
    final now = DateTime.now();
    final justAfterMidnight = DateTime(now.year, now.month, now.day, 0, 30);
    expect(HumanTime.daysAgo(justAfterMidnight), 0);

    final y = now.subtract(const Duration(days: 1));
    // 23:50 yesterday can be only minutes ago in elapsed time, yet it is still
    // a different calendar day — the exact case the old code got wrong.
    expect(HumanTime.daysAgo(DateTime(y.year, y.month, y.day, 23, 50)), 1);
  });
}
