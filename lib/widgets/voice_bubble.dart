import 'package:flutter/material.dart';

import '../theme/brutal_theme.dart';

/// Voice-message body: play/pause disc, waveform and duration.
///
/// Shared by 1:1 and group chat. Group chat had no renderer for the `voice`
/// message type at all, so anything recorded there would have arrived as an
/// empty bubble.
class VoiceBubble extends StatelessWidget {
  final String? mediaUrl;

  /// Duration label as stored on the message (`content`, e.g. `"7s"`).
  final String duration;
  final bool isOwn;
  final bool isPlaying;
  final VoidCallback? onTap;

  const VoiceBubble({
    super.key,
    required this.mediaUrl,
    required this.duration,
    required this.isOwn,
    required this.isPlaying,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: mediaUrl != null ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: isOwn ? c.accent.withOpacity(0.2) : c.surface2,
                shape: BoxShape.circle),
            child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: c.accent,
                size: 22),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: List.generate(
              16,
              (i) => Container(
                width: 3,
                height: (4 + (i % 5) * 3).toDouble(),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isPlaying ? c.accent : c.inkSoft.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(duration, style: TextStyle(color: c.inkSoft, fontSize: 11)),
        ]),
      ]),
    );
  }
}
