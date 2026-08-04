import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/brutal_theme.dart';

/// The "pinned message" strip that sits directly under the chat AppBar.
///
/// Shared by 1:1 and group chat. Renders a jsonb snapshot (see
/// migrations/pinned_messages.sql), not a live message — the original row is
/// gone from the server as soon as it's delivered, so there is nothing to
/// look up.
class PinnedBar extends StatelessWidget {
  /// Snapshot: {id, sender_name, content, message_type, …}. Null renders nothing.
  final Map? pinned;

  /// Jump to the original if it's still in this device's local history.
  final VoidCallback onTap;

  /// Unpin. Null hides the button — used in groups when the viewer isn't an
  /// admin and therefore may look but not change it.
  final VoidCallback? onUnpin;

  const PinnedBar({
    super.key,
    required this.pinned,
    required this.onTap,
    this.onUnpin,
  });

  /// Media messages have no text worth showing, so label them by type — the
  /// same treatment the chat-list preview uses.
  String _preview(BuildContext context, Map p) {
    final type = (p['message_type'] ?? 'text').toString();
    final content = (p['content'] ?? '').toString();
    switch (type) {
      case 'image':
        return '📷 ${context.t('photoLabel')}';
      case 'video':
        return '🎥 ${context.t('videoLabel')}';
      case 'voice':
        return '🎤 ${context.t('voiceLabel')}';
      case 'gif':
        return 'GIF';
      case 'sticker':
        return '💟 ${context.t('stickerLabel')}';
      default:
        return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pinned;
    if (p == null) return const SizedBox.shrink();
    final c = context.k;
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: c.ink.withOpacity(0.06), width: 1)),
          ),
          child: Row(children: [
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.push_pin_rounded, size: 15, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('pinnedLabel'),
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                  Text(_preview(context, p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
            if (onUnpin != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: c.inkSoft),
                onPressed: onUnpin,
              ),
          ]),
        ),
      ),
    );
  }
}
