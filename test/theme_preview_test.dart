import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigma_social_app/theme/brutal_theme.dart';

/// Renders every palette to `test/goldens/themes.png` so the colours can be
/// eyeballed without a device. Run with:
///   flutter test --update-goldens test/theme_preview_test.dart
/// Text renders as boxes here (tests ship no real font) — that's fine, the
/// point is the COLOUR of each block against its background, which is exactly
/// what the "invisible text" bugs come down to.
void main() {
  testWidgets('theme swatches', (tester) async {
    tester.view.physicalSize = const Size(1240, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget column(BrutalTheme t) {
      final c = t.c;
      Widget line(Color col, double w, double h) => Container(
          width: w, height: h, margin: const EdgeInsets.only(bottom: 6),
          color: col);
      return Container(
        width: 300,
        color: c.bg,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.nameEn,
              style: TextStyle(color: c.ink, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          // card with primary + muted text
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              line(c.ink, 170, 12),
              line(c.inkSoft, 130, 9),
              const SizedBox(height: 4),
              // accentFill, not accent — that's what real buttons paint.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    color: c.accentFill, borderRadius: BorderRadius.circular(10)),
                child: line(c.onAccent, 62, 10),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          // input chip + accent/danger dots
          Container(
            width: double.infinity,
            height: 34,
            decoration: BoxDecoration(
                color: c.surface2, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: line(c.inkSoft, 110, 9),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final col in [c.accent, c.accent2, c.accent3, c.danger])
              Container(
                  width: 30, height: 30,
                  margin: const EdgeInsets.only(right: 8),
                  decoration:
                      BoxDecoration(color: col, shape: BoxShape.circle)),
          ]),
        ]),
      );
    }

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Row(children: [for (final t in kThemes) column(t)]),
    ));
    await tester.pumpAndSettle();

    await expectLater(
        find.byType(Row).first, matchesGoldenFile('goldens/themes.png'));
  });
}
