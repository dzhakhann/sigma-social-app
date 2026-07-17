import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// Telegram-style story video editor: scrub the timeline, drag the handles to
/// pick any section (max 60s), mute or set the volume, preview, publish.
///
/// The cut is done with a stream copy where possible — no re-encode, so it's
/// fast and lossless. Output goes to the temp dir and is deleted by the OS;
/// nothing extra is cached or copied.
class StoryVideoEditorScreen extends StatefulWidget {
  final String path;
  const StoryVideoEditorScreen({Key? key, required this.path})
      : super(key: key);

  @override
  State<StoryVideoEditorScreen> createState() => _StoryVideoEditorScreenState();
}

class _StoryVideoEditorScreenState extends State<StoryVideoEditorScreen> {
  static const _maxLen = Duration(seconds: 60);

  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _exporting = false;

  Duration _total = Duration.zero;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  double _volume = 1.0;

  /// Transforms applied on export. Preview shows them live via Transform.
  int _quarterTurns = 0; // 0..3 → 0/90/180/270°
  bool _mirrored = false;
  double _speed = 1.0; // 0.5 / 1 / 1.5 / 2

  static const _speeds = [0.5, 1.0, 1.5, 2.0];

  void _rotate() {
    HapticFeedback.selectionClick();
    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
  }

  void _flip() {
    HapticFeedback.selectionClick();
    setState(() => _mirrored = !_mirrored);
  }

  Future<void> _cycleSpeed() async {
    HapticFeedback.selectionClick();
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    await _ctrl?.setPlaybackSpeed(next);
  }

  /// ffmpeg -vf chain for the chosen rotate / mirror / speed.
  String _videoFilters() {
    final parts = <String>[];
    for (var i = 0; i < _quarterTurns; i++) {
      parts.add('transpose=1'); // 90° clockwise, applied repeatedly
    }
    if (_mirrored) parts.add('hflip');
    if (_speed != 1.0) parts.add('setpts=${(1 / _speed).toStringAsFixed(4)}*PTS');
    return parts.join(',');
  }

  /// Audio has to be sped up separately; atempo only accepts 0.5–2.0 per pass.
  String _audioFilters() => _speed == 1.0 ? '' : 'atempo=$_speed';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
    } catch (_) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _total = c.value.duration;
    _start = Duration.zero;
    // Pre-trim anything longer than the 60s story limit.
    _end = _total > _maxLen ? _maxLen : _total;
    c.setLooping(false);
    c.addListener(_watch);
    await c.setVolume(_volume);
    await c.play();
    if (mounted) setState(() { _ctrl = c; _ready = true; });
  }

  // Keep playback inside the selected range.
  void _watch() {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    if (pos >= _end) {
      c.seekTo(_start);
      c.play();
    }
    if (mounted) setState(() {});
  }

  Duration get _selected => _end - _start;

  void _setStart(double v) {
    final s = Duration(milliseconds: (v * _total.inMilliseconds).round());
    setState(() {
      _start = s;
      if (_end <= _start) _end = _start + const Duration(seconds: 1);
      if (_selected > _maxLen) _end = _start + _maxLen;
      if (_end > _total) _end = _total;
    });
    _ctrl?.seekTo(_start);
  }

  void _setEnd(double v) {
    final e = Duration(milliseconds: (v * _total.inMilliseconds).round());
    setState(() {
      _end = e;
      if (_end <= _start) _start = _end - const Duration(seconds: 1);
      if (_start < Duration.zero) _start = Duration.zero;
      if (_selected > _maxLen) _start = _end - _maxLen;
    });
    _ctrl?.seekTo(_start);
  }

  Future<void> _setVolume(double v) async {
    setState(() => _volume = v);
    await _ctrl?.setVolume(v);
  }

  /// Cut the selected range (and apply mute) into a temp file, then hand the
  /// path back. Stream copy — no re-encode — unless the audio has to be dropped.
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    HapticFeedback.mediumImpact();
    await _ctrl?.pause();
    try {
      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ss = (_start.inMilliseconds / 1000).toStringAsFixed(3);
      final t = (_selected.inMilliseconds / 1000).toStringAsFixed(3);
      final vf = _videoFilters();
      final af = _audioFilters();
      final muted = _volume == 0;

      String cmd;
      if (vf.isEmpty && af.isEmpty) {
        // Nothing to transform → stream copy: lossless and instant.
        cmd = '-y -ss $ss -i "${widget.path}" -t $t -c:v copy '
            '${muted ? '-an' : '-c:a copy'} "$out"';
      } else {
        // Rotate / mirror / speed need a re-encode.
        cmd = '-y -ss $ss -i "${widget.path}" -t $t '
            '${vf.isNotEmpty ? '-vf "$vf" ' : ''}'
            '${(!muted && af.isNotEmpty) ? '-af "$af" ' : ''}'
            '-c:v libx264 -preset veryfast -pix_fmt yuv420p '
            '${muted ? '-an' : '-c:a aac -b:a 128k'} "$out"';
      }
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        // Stream copy can fail if the cut lands off a keyframe — re-encode.
        final fallback = '-y -ss $ss -i "${widget.path}" -t $t '
            '${vf.isNotEmpty ? '-vf "$vf" ' : ''}'
            '${(!muted && af.isNotEmpty) ? '-af "$af" ' : ''}'
            '-c:v libx264 -preset veryfast -pix_fmt yuv420p '
            '${muted ? '-an' : '-c:a aac -b:a 128k'} "$out"';
        final s2 = await FFmpegKit.execute(fallback);
        if (!ReturnCode.isSuccess(await s2.getReturnCode())) {
          throw Exception('export failed');
        }
      }
      if (mounted) Navigator.pop(context, out);
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('videoExportFailed'))),
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_watch);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Text(context.t('videoEditTitle'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_fmt(_selected),
                  style: TextStyle(
                      color: _selected > _maxLen ? Colors.redAccent : c.accent2,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          // ── Preview ──────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: !_ready || ctrl == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : GestureDetector(
                      onTap: () => setState(() =>
                          ctrl.value.isPlaying ? ctrl.pause() : ctrl.play()),
                      // Live preview of rotate + mirror.
                      child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..scale(_mirrored ? -1.0 : 1.0, 1.0),
                          child: AspectRatio(
                            aspectRatio: ctrl.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(ctrl),
                                if (!ctrl.value.isPlaying)
                                  const Icon(Icons.play_circle_fill_rounded,
                                      size: 64, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (_ready) _controls(c),
        ]),
      ),
    );
  }

  Widget _controls(BrutalColors c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        color: Colors.black,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Trim timeline ──────────────────────────────────────────
          Text(context.t('videoTrimHint'),
              style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          const SizedBox(height: 6),
          RangeSlider(
            values: RangeValues(
              _start.inMilliseconds / (_total.inMilliseconds == 0 ? 1 : _total.inMilliseconds),
              _end.inMilliseconds / (_total.inMilliseconds == 0 ? 1 : _total.inMilliseconds),
            ),
            activeColor: c.accent,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              if (v.start != _start.inMilliseconds / _total.inMilliseconds) {
                _setStart(v.start);
              }
              if (v.end != _end.inMilliseconds / _total.inMilliseconds) {
                _setEnd(v.end);
              }
            },
          ),
          Row(children: [
            Text(_fmt(_start),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const Spacer(),
            Text(_fmt(_total),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          // ── Rotate / mirror / speed ────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _toolChip(c, Icons.rotate_90_degrees_cw_rounded,
                context.t('vRotate'), _rotate, on: _quarterTurns != 0),
            _toolChip(c, Icons.flip_rounded, context.t('vFlip'), _flip,
                on: _mirrored),
            _toolChip(c, Icons.speed_rounded, '${_speed}x', _cycleSpeed,
                on: _speed != 1.0),
          ]),
          const SizedBox(height: 6),
          // ── Volume ─────────────────────────────────────────────────
          Row(children: [
            IconButton(
              icon: Icon(
                  _volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white),
              onPressed: () => _setVolume(_volume == 0 ? 1.0 : 0.0),
            ),
            Expanded(
              child: Slider(
                value: _volume,
                activeColor: c.accent,
                inactiveColor: Colors.white24,
                onChanged: _setVolume,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // ── Publish ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _exporting ? null : _export,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.t('next'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ]),
      );

  Widget _toolChip(BrutalColors c, IconData icon, String label,
          VoidCallback onTap, {bool on = false}) =>
      Material(
        color: on ? c.accent.withOpacity(0.22) : Colors.white10,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: on ? c.accent : Colors.white24, width: 0.9),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: on ? c.accent : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: on ? c.accent : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
