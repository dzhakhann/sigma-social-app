import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'chat_extras_panel.dart';

/// Compact badge chooser: an emoji grid and a GIF search, side by side in a
/// small sheet.
///
/// Emoji is the first tab on purpose — it's the common case (one tap, nothing to
/// load) and it works with no network at all, whereas the GIF tab needs Giphy to
/// answer.
///
/// Returns the chosen value, `''` to reset to the default chip, or null when
/// dismissed. An emoji and a GIF URL share one field; [isEmojiBadge] tells them
/// apart at render time.
Future<String?> showProBadgePicker(BuildContext context) {
  final c = context.k;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          // Deliberately not full-height: this is a small decision, and a
          // sheet that covers the profile makes it feel like a bigger one.
          height: MediaQuery.of(sheetCtx).size.height * 0.52,
          decoration: BoxDecoration(
            color: c.surface.withOpacity(c.isDark ? 0.88 : 0.96),
            border: Border(
                top: BorderSide(color: c.ink.withOpacity(0.08), width: 1)),
          ),
          child: SafeArea(top: false, child: const _PickerBody()),
        ),
      ),
    ),
  );
}

/// True when a stored badge value is an emoji rather than a Giphy URL.
bool isEmojiBadge(String? value) =>
    value != null && value.isNotEmpty && !value.startsWith('http');

class _PickerBody extends StatefulWidget {
  const _PickerBody();

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  int _tab = 0;

  /// A curated set rather than the full ~1600-emoji keyboard: a status badge is
  /// a handful of recognisable marks, and scrolling thousands of them to pick
  /// one is worse than having fewer.
  static const _emoji = [
    '🔥', '⚡', '💎', '👑', '🌟', '✨', '💫', '🚀',
    '❤️', '🩷', '🌹', '🦋', '🐱', '🐻', '🦊', '🐼',
    '🎯', '🏆', '🥇', '💪', '🧠', '🎧', '🎮', '⚽',
    '🌙', '☀️', '🌈', '🍀', '💰', '📈', '🕶️', '🎭',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      const SizedBox(height: 10),
      Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
            color: c.inkSoft.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: Text(context.t('proBadgeTitle'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          TextButton(
            // Empty string, not null — the caller has to tell "reset" from
            // "cancelled".
            onPressed: () => Navigator.pop(context, ''),
            child: Text(context.t('proBadgeReset'),
                style: TextStyle(color: c.accent)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          _tabChip(c, 0, context.t('proBadgeTabEmoji')),
          const SizedBox(width: 8),
          _tabChip(c, 1, context.t('proBadgeTabGif')),
        ]),
      ),
      Expanded(
        child: _tab == 0
            ? GridView.count(
                crossAxisCount: 6,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in _emoji)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, e),
                      child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 27))),
                    ),
                ],
              )
            : GiphyGrid(
                stickers: false,
                onPick: (url) => Navigator.pop(context, url),
              ),
      ),
    ]);
  }

  Widget _tabChip(BrutalColors c, int index, String label) {
    final on = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? c.accent.withOpacity(0.16) : c.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? c.accent.withOpacity(0.5) : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? c.ink : c.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Applies a picker result, returning the new badge value (null = default chip)
/// or a localized error.
///
/// Lives beside the picker so every caller handles the server's refusal reasons
/// identically instead of inventing its own wording.
Future<({String? url, String? error})> applyProBadge(
    BuildContext context, String picked) async {
  final value = picked.isEmpty ? null : picked;
  final r = await ApiService.setProBadge(value);
  if (r['success'] == true) return (url: value, error: null);
  final reason = r['error']?.toString();
  final msg = switch (reason) {
    'pro_only' => context.t('proBadgeProOnly'),
    'bad_url' => context.t('proBadgeBadUrl'),
    'not_migrated' => context.t('proBadgeNotReady'),
    _ => context.t('proBadgeFailed'),
  };
  return (url: null, error: msg);
}
