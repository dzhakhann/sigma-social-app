import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/download_store.dart';
import '../theme/brutal_theme.dart';

/// A single tappable control for offline downloads, shared by music tracks,
/// podcast episodes and audiobook chapters. It reflects three states live:
///   • not downloaded  → ↓ outline  (tap = download)
///   • downloading      → ring with progress
///   • downloaded       → ✓ accent   (tap = remove, after a confirm)
class DownloadButton extends StatelessWidget {
  final Map track;
  final double size;
  const DownloadButton({Key? key, required this.track, this.size = 22})
      : super(key: key);

  Future<void> _onTap(BuildContext context) async {
    final audio = (track['audio'] ?? '').toString();
    if (audio.isEmpty) return;
    if (DownloadStore.isDownloaded(audio)) {
      final c = context.k;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(ctx.t('downloadRemoveQ'), style: TextStyle(color: c.ink)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.t('cancelBtn'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.t('deleteBtn'),
                    style: TextStyle(color: c.danger))),
          ],
        ),
      );
      if (ok == true) await DownloadStore.remove(audio);
      return;
    }
    final ok = await DownloadStore.download(track);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('downloadFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final audio = (track['audio'] ?? '').toString();
    return ValueListenableBuilder<int>(
      valueListenable: DownloadStore.version,
      builder: (_, __, ___) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: DownloadStore.progress,
        builder: (_, prog, ___) {
          final downloading = prog.containsKey(audio);
          final done = DownloadStore.isDownloaded(audio);
          if (downloading) {
            final p = prog[audio] ?? 0;
            return SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: p <= 0 ? null : p,
                strokeWidth: 2,
                color: c.accent,
                backgroundColor: c.inkSoft.withOpacity(0.2),
              ),
            );
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onTap(context),
            child: Icon(
              done ? Icons.download_done_rounded : Icons.download_rounded,
              color: done ? c.accent : c.inkSoft,
              size: size,
            ),
          );
        },
      ),
    );
  }
}
