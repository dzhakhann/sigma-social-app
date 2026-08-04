import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/chat_wallpaper.dart';
import '../services/pro_state.dart';
import '../theme/brutal_theme.dart';

/// Wallpaper chooser sheet, shared by 1:1 and group chat.
///
/// Replaces two near-identical private copies — the group one only ever offered
/// presets while 1:1 also had the gallery option, and they had already drifted
/// apart in layout.
///
/// Returns the chosen wallpaper map, `{}` to clear it, or null if dismissed.
/// The caller persists it, since 1:1 and groups key storage differently.
Future<Map?> showWallpaperPicker(
  BuildContext context, {
  /// Offer "pick from gallery". Group chat passes false — a shared background
  /// from one member's camera roll isn't a thing other members would see.
  required bool allowGallery,
  required VoidCallback onPickGallery,
  required VoidCallback onOpenPro,
}) {
  final c = context.k;
  return showModalBottomSheet<Map?>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetCtx) => _PickerBody(
      allowGallery: allowGallery,
      onPickGallery: onPickGallery,
      onOpenPro: onOpenPro,
    ),
  );
}

class _PickerBody extends StatelessWidget {
  final bool allowGallery;
  final VoidCallback onPickGallery;
  final VoidCallback onOpenPro;

  const _PickerBody({
    required this.allowGallery,
    required this.onPickGallery,
    required this.onOpenPro,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ValueListenableBuilder<bool>(
      valueListenable: ProState.isPro,
      builder: (_, hasPro, __) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: c.inkSoft.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Text(context.t('chatWallpaperTitle'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.62,
              children: [
                for (final p in ChatWallpaper.catalog)
                  _swatch(context, c, p, hasPro),
              ],
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (allowGallery)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Gallery photos are Pro — a plain colour set stays free.
                      if (!hasPro) {
                        Navigator.pop(context);
                        onOpenPro();
                        return;
                      }
                      Navigator.pop(context);
                      onPickGallery();
                    },
                    icon: Icon(
                        hasPro
                            ? Icons.photo_library_outlined
                            : Icons.lock_rounded,
                        size: 18),
                    label: Text(context.t('fromGallery')),
                  ),
                ),
              if (allowGallery) const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  // `{}` means "clear", distinct from null = "dismissed".
                  onPressed: () => Navigator.pop(context, <String, dynamic>{}),
                  child: Text(context.t('resetWallpaper'),
                      style: TextStyle(color: c.inkSoft)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _swatch(BuildContext context, BrutalColors c, ChatWallpaperPreset p,
      bool hasPro) {
    final locked = p.pro && !hasPro;
    return GestureDetector(
      onTap: () {
        if (locked) {
          Navigator.pop(context);
          onOpenPro();
          return;
        }
        Navigator.pop(context, {'type': 'gradient', 'id': p.id});
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          // The swatch is the real thing at thumbnail size — pattern included,
          // so what you pick is what you get.
          ChatBackgroundPreview(preset: p),
          if (locked)
            Container(
              color: Colors.black.withOpacity(0.35),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_rounded,
                  color: Colors.white, size: 18),
            ),
        ]),
      ),
    );
  }
}

/// A preset rendered as a thumbnail. Kept here rather than in ChatBackground so
/// the picker doesn't have to fake a wallpaper map just to draw a swatch.
class ChatBackgroundPreview extends StatelessWidget {
  final ChatWallpaperPreset preset;

  const ChatBackgroundPreview({super.key, required this.preset});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: preset.colors.map((v) => Color(v)).toList(),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}
