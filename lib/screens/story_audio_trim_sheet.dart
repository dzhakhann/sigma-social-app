import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../services/music_preview.dart';
import '../theme/brutal_theme.dart';

/// Telegram-style audio trimmer (Пункт 4): the selection WINDOW sits right on
/// the waveform — drag the window to move the fragment, drag its edge handles
/// to resize. No playhead line, no separate slider. The chosen fragment plays
/// looped while you adjust, so you hear exactly what will be published.
/// Returns `(startSec, lengthSec)` via Navigator.pop.
///
/// Bars are generated deterministically from the title — decoding the whole
/// file for a decorative strip would burn CPU for nothing. The TRIM is real:
/// ffmpeg seeks to the chosen second on export.
class AudioTrimSheet extends StatefulWidget {
  final String title;
  final int totalSec;
  final int startSec;
  final int lenSec;

  /// Track source (http url or local file path) — played as a live preview.
  final String? audioUrl;

  const AudioTrimSheet({
    Key? key,
    required this.title,
    required this.totalSec,
    required this.startSec,
    required this.lenSec,
    this.audioUrl,
  }) : super(key: key);

  @override
  State<AudioTrimSheet> createState() => _AudioTrimSheetState();
}

class _AudioTrimSheetState extends State<AudioTrimSheet> {
  late double _start = widget.startSec.toDouble();
  late int _len = widget.lenSec;
  // Rhythm doesn't always report a duration — assume 3 min so the UI works.
  late final int _total = widget.totalSec > 0 ? widget.totalSec : 180;

  bool _dragging = false;
  bool _soundFailed = false;

  double get _maxStart => (_total - _len).clamp(0, _total).toDouble();

  @override
  void initState() {
    super.initState();
    _restartPreview();
  }

  @override
  void dispose() {
    // The shared player belongs to the editor flow — the editor restarts its
    // own preview right after this sheet closes, so just stop here.
    MusicPreview.i.stop();
    super.dispose();
  }

  /// (Re)plays the currently selected fragment, looped — through the ONE
  /// shared preview player (several players fight under just_audio_background;
  /// that was the silent-trim bug).
  Future<void> _restartPreview() async {
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
            color: const Color(0xFF121316).withOpacity(0.88),
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
                Row(children: [
                  const Icon(Icons.music_note_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
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
                  final winW = (_len / _total * w).clamp(24.0, w);
                  final winX = (_start / _total * w)
                      .clamp(0.0, (w - winW).clamp(0.0, w));
                  const handleW = 22.0;
                  return SizedBox(
                    height: 72,
                    child: Stack(children: [
                      // waves
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WavePainter(
                            seed: widget.title.hashCode,
                            from: _start / _total,
                            to: ((_start + _len) / _total).clamp(0.0, 1.0),
                            accent: c.accent,
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
                                  .withOpacity(_dragging ? 0.16 : 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ),
                            // edge handles (visual)
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                _handle(),
                                _handle(),
                              ],
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
                            _len = (endSec - ns).round().clamp(5, 60);
                            _start = (endSec - _len).toDouble().clamp(0, _maxStart);
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
                            final ne = (_start + _len + d.delta.dx / w * _total)
                                .clamp(_start + 5, _total.toDouble());
                            _len = (ne - _start).round().clamp(5, 60);
                          }),
                          onHorizontalDragEnd: (_) => _restartPreview(),
                        ),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 10),
                // range readout: «0:36 – 0:51»
                Row(children: [
                  Text(_fmt(0),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                  const Spacer(),
                  Text(
                      '${_fmt(_start.round())} – ${_fmt(_start.round() + _len)}',
                      style: TextStyle(
                          color: c.accent2,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
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
                    for (final s in [5, 10, 15, 30, 60])
                      ChoiceChip(
                        label: Text('$s ${context.t('secShort')}'),
                        selected: _len == s,
                        onSelected: (_) {
                          setState(() {
                            _len = s;
                            if (_start > _maxStart) _start = _maxStart;
                          });
                          _restartPreview();
                        },
                        labelStyle: TextStyle(
                            color: _len == s ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5),
                        selectedColor: Colors.white,
                        backgroundColor: Colors.white12,
                        side: const BorderSide(color: Colors.white24),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
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
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _WavePainter extends CustomPainter {
  final int seed;
  final double from, to;
  final Color accent;
  _WavePainter({
    required this.seed,
    required this.from,
    required this.to,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0, gap = 2.0;
    final n = (size.width / (barW + gap)).floor();
    if (n <= 0) return;
    var s = seed.abs() % 100000;
    for (var i = 0; i < n; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final h = (0.18 + (s % 1000) / 1000 * 0.82) * size.height;
      final x = i * (barW + gap);
      final t = i / n;
      final inSel = t >= from && t <= to;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        Paint()
          ..color = inSel ? accent : Colors.white24
          ..strokeCap = StrokeCap.round
          ..strokeWidth = barW,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.from != from || o.to != to || o.seed != seed;
}
