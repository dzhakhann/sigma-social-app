import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigma_social_app/theme/brutal_theme.dart';

/// Objective readability check for every palette in [kThemes] — catches the
/// "text is technically there but you can't see it" class of bug (the post
/// music bar shipped white-on-white on the light theme once) without needing
/// a device or a human eyeball.
///
/// Ratios are WCAG 2.1 contrast: 4.5:1 is the floor for body text, 3:1 for
/// large text and UI chrome like icons/borders.
double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.red / 255) +
    0.7152 * _lin(c.green / 255) +
    0.0722 * _lin(c.blue / 255);

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Empty on purpose — every pair below must genuinely pass. The one waiver
/// this used to hold (white on Sigma's #4F7CFF at 3.71:1) is gone: buttons
/// now paint `accentFill` instead, so the brand blue keeps its identity as
/// text/icons while labels sit on a shade that actually clears AA.
/// **Fix the colour, don't add entries here.**
const _knownExceptions = <String>{};

void main() {
  test('every theme keeps text and chrome readable', () {
    final failures = <String>[];

    for (final t in kThemes) {
      final c = t.c;
      // pair label, foreground, background, minimum required ratio
      final checks = <(String, Color, Color, double)>[
        ('body text on page', c.ink, c.bg, 4.5),
        ('body text on card', c.ink, c.surface, 4.5),
        ('body text on input', c.ink, c.surface2, 4.5),
        ('muted text on page', c.inkSoft, c.bg, 4.5),
        ('muted text on card', c.inkSoft, c.surface, 4.5),
        ('accent on page', c.accent, c.bg, 3.0),
        ('accent on card', c.accent, c.surface, 3.0),
        // Buttons use `accentFill` (the accent darkened just enough to carry
        // a white label); `accent` itself stays vivid for text/icons. One
        // shade cannot do both — see the comment on accentFill.
        ('label on accent button', c.onAccent, c.accentFill, 4.5),
        ('accent AS TEXT on page', c.accent, c.bg, 4.5),
        ('danger on card', c.danger, c.surface, 3.0),
        ('card edge vs page', c.surface, c.bg, 1.05),
      ];

      for (final (label, fg, bg, min) in checks) {
        final r = contrast(fg, bg);
        final key = '${t.nameEn}: $label';
        final ok = r >= min;
        final waived = !ok && _knownExceptions.contains(key);
        // ignore: avoid_print
        print('${ok ? 'ok  ' : (waived ? 'WAIV' : 'FAIL')} ${t.nameEn.padRight(6)} '
            '${label.padRight(24)} ${r.toStringAsFixed(2)}:1 (need $min:1)');
        if (!ok && !waived) failures.add('$key = ${r.toStringAsFixed(2)}:1');
      }
    }

    expect(failures, isEmpty, reason: 'unreadable colour pairs:\n${failures.join('\n')}');
  });
}
