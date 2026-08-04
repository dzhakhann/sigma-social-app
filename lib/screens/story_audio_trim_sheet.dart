import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../services/music_preview.dart';
import '../theme/brutal_theme.dart';

/// Instagram-style audio trimmer: the selection WINDOW sits right on the
/// waveform — drag the window to move the fragment, drag its edge handles to
/// resize. The chosen fragment plays looped while you adjust, with a sweeping
/// playhead inside the window, so you hear AND see exactly what will be
/// published. Returns `(startSec, lengthSec)` via Navigator.pop.
///
/// Bars are generated deterministically from the title — decoding the whole
/// file for a decorative strip would burn CPU for nothing. The TRIM is real:
/// ffmpeg seeks to the chosen second on export.
class AudioTrimSheet extends StatefulWidget {
  final String title;
  final String artist;
  final String artwork;
  final int totalSec;
  final int startSec;
  final int lenSec;

  /// Track source (http url or local file path) — played as a live preview.
  final String? audioUrl;

  /// Upper bound on the fragment length. For a video story this is the video's
  /// own length (the music can't outlast the clip); 60 for photo stories.
  final int maxLen;

  /// Shown under the length presets when [maxLen] is capped by the video's
  /// own length — explains why the longer presets are missing instead of
  /// leaving the user wondering why the trim "can't be changed".
  final String? capHint;

  const AudioTrimSheet({
    Key? key,
    required this.title,
    this.artist = '',
    this.artwork = '',
    required this.totalSec,
    required this.startSec,
    required this.lenSec,
    this.audioUrl,
    this.maxLen = 60,
    this.capHint,
  }) : super(key: key);

  @override
  State<AudioTrimSheet> createState() => _AudioTrimSheetState();
}

class _AudioTrimSheetState extends State<AudioTrimSheet>
    with SingleTickerProviderStateMixin {
  late double _start = widget.startSec.toDouble();
  late int _len = widget.lenSec;
  // Rhythm doesn't always report a duration — assume 3 min so the UI works.
  late final int _total = widget.totalSec > 0 ? widget.totalSec : 180;

  bool _dragging = false;
  bool _soundFailed = false;

  /// Sweeps 0→1 across the selected window in sync with the looped preview —
  /// the moving playhead that makes the trimmer feel like a real editor.
  late final AnimationController _play = AnimationController(
      vsync: this, duration: Duration(seconds: widget.lenSec.clamp(1, 60)))
    ..repeat();

  double get _maxStart => (_total - _len).clamp(0, _total).toDouble();

  @override
  void initState() {
    super.initState();
    // Play the SELECTED window looped from the moment the trimmer opens — you
    // hear exactly what will be published (Instagram behaviour). The picker was
    // playing the full track; switch it to the fragment now.
    _restartPreview();
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  // NOTE: no stop() on the preview in dispose — the music keeps flowing into
  // the editor (Instagram behaviour). Stopping here raced with the editor
  // restarting the preview and killed the sound after trimming.

  /// (Re)plays the currently selected fragment, looped — through the ONE
  /// shared preview player (several players fight under just_audio_background;
  /// that was the silent-trim bug).
  Future<void> _restartPreview() async {
    _play.duration = Duration(seconds: _len.clamp(1, 60));
    _play.repeat();
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    try {
      await MusicPreview.i.playClip(
        url,
        title: widget.title,
        startSec: _start.round(),
        lenSec: _len,
      );
      if (mounted && _soundFailed) setState(() => _soundFailed = false);
    } catch (_) {
      // Make the failure VISIBLE instead of silently trimming with no sound.
      if (mounted) setState(() => _soundFailed = true);
    }
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xEE17181D), Color(0xF20E0F13)],
            ),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.10))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                // ── Track header: artwork + title + artist ──
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: widget.artwork.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.artwork, fit: BoxFit.cover)
                          : Container(
                              color: Colors.white10,
                              child: const Icon(Icons.music_note_rounded,
                                  color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800)),
                          if (widget.artist.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(widget.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12.5)),
                          ],
                        ]),
                  ),
                  // live selection readout pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                        '${_fmt(_start.round())} – ${_fmt(_start.round() + _len)}',
                        style: TextStyle(
                            color: c.accent2,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                ]),
                if (_soundFailed) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.volume_off_rounded,
                        color: Colors.redAccent, size: 15),
                    const SizedBox(width: 6),
                    Text(context.t('trackLoadFailed'),
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12.5)),
                    TextButton(
                      onPressed: _restartPreview,
                      child: Text(context.t('retryBtn'),
                          style: TextStyle(
                              color: c.accent2,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ],
                const SizedBox(height: 18),
                // ── Waveform + draggable window (the whole interaction) ──
                LayoutBuilder(builder: (_, box) {
                  final w = box.maxWidth;
                  final winW = (_len / _total * w).clamp(30.0, w);
                  final winX = (_start / _total * w)
                      .clamp(0.0, (w - winW).clamp(0.0, w));
                  const handleW = 24.0;
                  return SizedBox(
                    height: 86,
                    child: AnimatedBuilder(
                      animation: _play,
                      builder: (_, __) => Stack(children: [
                        // mirrored waveform with dimmed out-of-selection bars
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _WavePainter(
                              seed: widget.title.hashCode,
                              from: _start / _total,
                              to: ((_start + _len) / _total).clamp(0.0, 1.0),
                              accent: c.accent,
                              accent2: c.accent2,
                              playhead: _dragging ? null : _play.value,
                            ),
                          ),
                        ),
                        // selection window — drag to move
                        Positioned(
                          left: winX,
                          top: 0,
                          bottom: 0,
                          width: winW,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (_) =>
                                setState(() => _dragging = true),
                            onHorizontalDragUpdate: (d) => setState(() {
                              _start = (_start + d.delta.dx / w * _total)
                                  .clamp(0.0, _maxStart);
                            }),
                            onHorizontalDragEnd: (_) {
                              setState(() => _dragging = false);
                              HapticFeedback.selectionClick();
                              _restartPreview();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withOpacity(_dragging ? 0.14 : 0.07),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white,
                                    width: _dragging ? 2.6 : 2.2),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withOpacity(0.35),
                                      blurRadius: 10),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [_handle(), _handle()],
                              ),
                            ),
                          ),
                        ),
                        // left edge — resize (shrinks/grows from the left)
                        Positioned(
                          left: winX - handleW / 2,
                          top: 0,
                          bottom: 0,
                          width: handleW,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (d) => setState(() {
                              final endSec = _start + _len;
                              final ns = (_start + d.delta.dx / w * _total)
                                  .clamp(0.0, endSec - 5);
                              _len = (endSec - ns)
                                  .round()
                                  .clamp(5, widget.maxLen);
                              _start = (endSec - _len)
                                  .toDouble()
                                  .clamp(0, _maxStart);
                            }),
                            onHorizontalDragEnd: (_) => _restartPreview(),
                          ),
                        ),
                        // right edge — resize
                        Positioned(
                          left: winX + winW - handleW / 2,
                          top: 0,
                          bottom: 0,
                          width: handleW,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (d) => setState(() {
                              final ne =
                                  (_start + _len + d.delta.dx / w * _total)
                                      .clamp(_start + 5, _total.toDouble());
                              _len = (ne - _start)
                                  .round()
                                  .clamp(5, widget.maxLen);
                            }),
                            onHorizontalDragEnd: (_) => _restartPreview(),
                          ),
                        ),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Row(children: [
                  Text(_fmt(0),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  Text('${_len}s',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(_fmt(_total),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    // Hand-rolled pills instead of ChoiceChip: the sheet is
                    // always dark, but in the LIGHT app theme ChoiceChip drew
                    // a white chip under our white label — invisible squares.
                    for (final s in <int>{
                      // A very short clip (< 5s) has no preset that fits —
                      // fall back to the clip's own length so at least one
                      // (selected, working) chip always renders.
                      if (widget.maxLen < 5) widget.maxLen,
                      ...const [5, 10, 15, 20, 30, 45, 60]
                          .where((v) => v <= widget.maxLen),
                    })
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _len = s;
                            if (_start > _maxStart) _start = _maxStart;
                          });
                          HapticFeedback.selectionClick();
                          _restartPreview();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _len == s ? Colors.white : Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _len == s
                                    ? Colors.white
                                    : Colors.white24),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (_len == s) ...[
                              const Icon(Icons.check_rounded,
                                  color: Colors.black, size: 14),
                              const SizedBox(width: 4),
                            ],
                            Text('$s ${context.t('secShort')}',
                                style: TextStyle(
                                    color: _len == s
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5)),
                          ]),
                        ),
                      ),
                  ],
                ),
                if (widget.capHint != null) ...[
                  const SizedBox(height: 8),
                  Text(widget.capHint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11.5)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accentFill,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    onPressed: () =>
                        Navigator.pop(context, (_start.round(), _len)),
                    child: Text(context.t('done'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle() => Container(
        width: 4,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Mirrored deterministic waveform: bright gradient bars inside the selection
/// (with a sweeping playhead), dimmed bars outside — like a real editor.
class _WavePainter extends CustomPainter {
  final int seed;
  final double from, to;
  final Color accent;
  final Color accent2;

  /// 0..1 across the SELECTION, or null while dragging.
  final double? playhead;

  _WavePainter({
    required this.seed,
    required this.from,
    required this.to,
    required this.accent,
    required this.accent2,
    this.playhead,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0, gap = 2.0;
    final n = (size.width / (barW + gap)).floor();
    if (n <= 0) return;
    final mid = size.height / 2;
    final ph = playhead == null ? null : from + (to - from) * playhead!;
    var s = seed.abs() % 100000;
    for (var i = 0; i < n; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final amp = 0.16 + (s % 1000) / 1000 * 0.84;
      final h = amp * (size.height - 14);
      final x = i * (barW + gap);
      final t = i / n;
      final inSel = t >= from && t <= to;
      final played = ph != null && inSel && t <= ph;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barW;
      if (played) {
        paint.color = Colors.white;
      } else if (inSel) {
        paint.shader = ui.Gradient.linear(
          Offset(x, mid - h / 2),
          Offset(x, mid + h / 2),
          [accent2, accent],
        );
      } else {
        paint.color = Colors.white.withOpacity(0.16);
      }
      canvas.drawLine(
          Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
    // thin playhead line
    if (ph != null && ph >= from && ph <= to) {
      final px = ph * size.width;
      canvas.drawLine(
          Offset(px, 4),
          Offset(px, size.height - 4),
          Paint()
            ..color = Colors.white.withOpacity(0.9)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.from != from || o.to != to || o.seed != seed || o.playhead != playhead;
}
