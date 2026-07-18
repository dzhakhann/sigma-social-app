import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../services/music_preview.dart';
import '../theme/brutal_theme.dart';
import 'music_widgets.dart';

/// Telegram-style «♫ NF – MISTAKE ›» row for the profile (Раздел 2).
/// Animated while visible; tap opens the mini player. The track is ONLY a
/// Rhythm catalog reference — playback streams from the catalog.
class FavTrackPill extends StatelessWidget {
  final Map track; // {url, title, artist, art, dur}
  final VoidCallback onTap;
  const FavTrackPill({Key? key, required this.track, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final title = (track['title'] ?? '').toString();
    final artist = (track['artist'] ?? '').toString();
    final label = artist.isEmpty ? title : '$title – $artist';
    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.ink.withOpacity(0.08)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.music_note_rounded, size: 15, color: c.accent),
            const SizedBox(width: 7),
            Marquee(
              text: label,
              maxWidth: 170,
              style: TextStyle(
                  color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const EqualizerBars(scale: 0.45),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 17, color: c.inkSoft),
          ]),
        ),
      ),
    );
  }
}

/// Subtle owner-only button when no track is set yet.
class FavTrackAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const FavTrackAddButton({Key? key, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.music_note_rounded, size: 16, color: c.inkSoft),
        label: Text(context.t('favTrackAdd'),
            style: TextStyle(color: c.inkSoft, fontSize: 13)),
      ),
    );
  }
}

/// Mini player sheet: artwork, title/artist, play-pause, seek — like tapping
/// the music row in a Telegram profile. Owner also gets change/remove.
class FavTrackPlayerSheet extends StatefulWidget {
  final Map track;
  final bool isOwner;

  /// Owner actions; both close the sheet themselves.
  final VoidCallback? onChange;
  final VoidCallback? onRemove;

  const FavTrackPlayerSheet({
    Key? key,
    required this.track,
    required this.isOwner,
    this.onChange,
    this.onRemove,
  }) : super(key: key);

  @override
  State<FavTrackPlayerSheet> createState() => _FavTrackPlayerSheetState();
}

class _FavTrackPlayerSheetState extends State<FavTrackPlayerSheet> {
  // The ONE shared preview player (audioplayers — doesn't grab the system
  // media session, so no phone-notification player and no conflicts).
  final _player = MusicPreview.i.player;
  bool _ready = false;
  bool _error = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _init();
  }

  Future<void> _init() async {
    setState(() { _error = false; _ready = false; });
    try {
      await MusicPreview.i.playUrl(
        (widget.track['url'] ?? '').toString(),
        title: (widget.track['title'] ?? '').toString(),
        artist: (widget.track['artist'] ?? '').toString(),
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('fav track load failed: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    MusicPreview.i.stop(); // no sound survives the sheet
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final art = (widget.track['art'] ?? '').toString();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121316).withOpacity(0.9),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),
                // Artwork with a soft live equalizer overlay.
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(fit: StackFit.expand, children: [
                      art.isNotEmpty
                          ? CachedNetworkImage(imageUrl: art, fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFF222327),
                              child: const Icon(Icons.music_note_rounded,
                                  size: 48, color: Colors.white54)),
                      ValueListenableBuilder<bool>(
                        valueListenable: MusicPreview.i.isPlaying,
                        builder: (_, playing, __) => playing
                            ? Container(
                                color: Colors.black26,
                                child: const Center(
                                    child: EqualizerBars(scale: 1.1)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text((widget.track['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text((widget.track['artist'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13.5)),
                const SizedBox(height: 10),
                // Seek bar driven by the position stream.
                StreamBuilder<Duration>(
                  stream: _player.onPositionChanged,
                  builder: (_, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final total = _duration;
                    final max = total.inMilliseconds.toDouble();
                    return Column(children: [
                      Slider(
                        value: pos.inMilliseconds
                            .toDouble()
                            .clamp(0, max <= 0 ? 1 : max),
                        max: max <= 0 ? 1 : max,
                        activeColor: c.accent,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            _player.seek(Duration(milliseconds: v.round())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          Text(_fmt(total),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ]);
                  },
                ),
                const SizedBox(height: 4),
                // Play / pause.
                ValueListenableBuilder<bool>(
                  valueListenable: MusicPreview.i.isPlaying,
                  builder: (_, playing, __) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        MusicPreview.i.toggle();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                            color: c.accent, shape: BoxShape.circle),
                        child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34),
                      ),
                    );
                  },
                ),
                if (_error)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(children: [
                      Text(context.t('trackLoadFailed'),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      TextButton(
                        onPressed: _init,
                        child: Text(context.t('retryBtn'),
                            style: TextStyle(
                                color: c.accent2,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  )
                else if (!_ready)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white38)),
                  ),
                if (widget.isOwner) ...[
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton.icon(
                      onPressed: widget.onChange,
                      icon: Icon(Icons.swap_horiz_rounded,
                          size: 17, color: c.accent2),
                      label: Text(context.t('favTrackChange'),
                          style:
                              TextStyle(color: c.accent2, fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 17, color: Colors.redAccent),
                      label: Text(context.t('favTrackRemove'),
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
