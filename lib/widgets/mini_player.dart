import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/podcast_audio.dart';
import '../screens/podcast_player_screen.dart';

/// Spotify-style persistent mini-player. Shows whenever a podcast is loaded,
/// sits just above the bottom nav, and keeps playing across the whole app.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final audio = PodcastAudio.instance;
    return ValueListenableBuilder<Map?>(
      valueListenable: audio.current,
      builder: (_, ep, __) {
        if (ep == null) return const SizedBox.shrink();
        final art = (ep['artwork'] ?? '').toString();
        final player = audio.player;
        return GestureDetector(
          onTap: () =>
              Navigator.push(context, PodcastPlayerScreen.route()),
          child: Container(
            height: 58,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            padding: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: art.isEmpty
                    ? Container(width: 46, height: 46, color: c.surface)
                    : CachedNetworkImage(
                        imageUrl: art,
                        width: 46, height: 46, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((ep['title'] ?? context.t('episode')).toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text((ep['showTitle'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.inkSoft, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(Icons.skip_previous_rounded, color: c.ink, size: 26),
                onPressed: audio.prev,
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (_, snap) {
                  final st = snap.data;
                  final playing = st?.playing ?? false;
                  final loading =
                      st?.processingState == ProcessingState.loading ||
                          st?.processingState == ProcessingState.buffering;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 38, minHeight: 38),
                    icon: loading
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.accent))
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: c.ink, size: 30),
                    onPressed: audio.toggle,
                  );
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(Icons.skip_next_rounded, color: c.ink, size: 26),
                onPressed: audio.next,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(Icons.close_rounded, color: c.inkSoft, size: 20),
                onPressed: audio.stop,
              ),
              const SizedBox(width: 2),
            ]),
          ),
        );
      },
    );
  }
}
