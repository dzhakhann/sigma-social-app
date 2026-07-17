import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/brutal_theme.dart';

/// Telegram-style audio editor: pick WHICH part of the track plays and for how
/// long. Returns `(startSec, lengthSec)` via Navigator.pop.
///
/// The waveform bars are generated deterministically from the title — real
/// amplitude analysis would mean decoding the whole file on-device for a purely
/// decorative strip. The trim itself is real: ffmpeg seeks to the chosen second.
class AudioTrimSheet extends StatefulWidget {
  final String title;
  final int totalSec;
  final int startSec;
  final int lenSec;
  const AudioTrimSheet({
    Key? key,
    required this.title,
    required this.totalSec,
    required this.startSec,
    required this.lenSec,
  }) : super(key: key);

  @override
  State<AudioTrimSheet> createState() => _AudioTrimSheetState();
}

class _AudioTrimSheetState extends State<AudioTrimSheet> {
  late int _start = widget.startSec;
  late int _len = widget.lenSec;
  // Rhythm doesn't always report a duration — assume 3 min so the UI still works.
  late final int _total = widget.totalSec > 0 ? widget.totalSec : 180;

  int get _maxStart => (_total - _len).clamp(0, _total);

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
            color: const Color(0xFF121316).withOpacity(0.86),
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
                const SizedBox(height: 16),
                // Waveform with the selected window lit up.
                SizedBox(
                  height: 56,
                  child: CustomPaint(
                    size: const Size(double.infinity, 56),
                    painter: _WavePainter(
                      seed: widget.title.hashCode,
                      from: _start / _total,
                      to: ((_start + _len) / _total).clamp(0.0, 1.0),
                      accent: c.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Slide the window across the track.
                Slider(
                  value: _start.toDouble().clamp(0, _maxStart.toDouble()),
                  max: _maxStart <= 0 ? 1 : _maxStart.toDouble(),
                  activeColor: c.accent,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _start = v.round()),
                ),
                Row(children: [
                  Text(_fmt(0),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                  const Spacer(),
                  Text('${_fmt(_start)} – ${_fmt(_start + _len)}',
                      style: TextStyle(
                          color: c.accent2,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(_fmt(_total),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
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
                        onSelected: (_) => setState(() {
                          _len = s;
                          if (_start > _maxStart) _start = _maxStart;
                        }),
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
                    onPressed: () => Navigator.pop(context, (_start, _len)),
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
      // Deterministic pseudo-random: organic-looking but stable across repaints.
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
