import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/ffmpeg_web.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// Web's video story trim screen — the same job as StoryVideoEditorScreen,
/// cut down to what ffmpeg.wasm can do at a reasonable speed and what fits a
/// first web version: pick the in/out points, optionally mute, publish.
///
/// Deliberately NOT a port of the native screen: no rotate/mirror/speed, no
/// filmstrip thumbnails (each frame would be its own ffmpeg.wasm call — on a
/// WASM build that already takes real time just to load, that's minutes, not
/// the instant scrub the native version gives you for free from a real
/// decoder). A plain range slider over a live-seeking preview is what's
/// actually deliverable without either lying about the UI or shipping
/// something slow enough to feel broken.
///
/// Takes and returns bytes — web has no filesystem path to hand around, and
/// nothing here is written to disk anywhere.
class StoryVideoTrimWebScreen extends StatefulWidget {
  final Uint8List bytes;
  const StoryVideoTrimWebScreen({super.key, required this.bytes});

  @override
  State<StoryVideoTrimWebScreen> createState() =>
      _StoryVideoTrimWebScreenState();
}

class _StoryVideoTrimWebScreenState extends State<StoryVideoTrimWebScreen> {
  static const _maxLen = Duration(seconds: 60);

  VideoPlayerController? _ctrl;
  String? _objectUrl;
  bool _ready = false;
  bool _exporting = false;
  String? _error;

  Duration _total = Duration.zero;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  bool _muted = false;

  Timer? _loopWatch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = FfmpegWeb.bytesToObjectUrl(widget.bytes);
    _objectUrl = url;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      final total = ctrl.value.duration;
      setState(() {
        _ctrl = ctrl;
        _total = total;
        _start = Duration.zero;
        _end = total > _maxLen ? _maxLen : total;
        _ready = true;
      });
      ctrl.setLooping(false);
      ctrl.addListener(_onTick);
      await ctrl.play();
    } catch (_) {
      if (mounted) setState(() => _error = context.t('videoExportFailed'));
    }
  }

  // Loops playback within [_start, _end] so trimming what you hear/see is
  // exactly what you get — jumping back to _start the instant the preview
  // reaches _end, same as scrubbing a real trim handle would feel like.
  void _onTick() {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized || _exporting) return;
    if (c.value.position >= _end) {
      c.seekTo(_start);
    }
  }

  @override
  void dispose() {
    _loopWatch?.cancel();
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    if (_objectUrl != null) FfmpegWeb.revokeObjectUrl(_objectUrl!);
    super.dispose();
  }

  void _onRangeChanged(RangeValues v) {
    final start = Duration(milliseconds: v.start.round());
    var end = Duration(milliseconds: v.end.round());
    if (end - start > _maxLen) end = start + _maxLen;
    setState(() {
      _start = start;
      _end = end;
    });
    _ctrl?.seekTo(start);
  }

  Future<void> _export() async {
    if (_exporting) return;
    HapticFeedback.mediumImpact();
    setState(() => _exporting = true);
    await _ctrl?.pause();

    final ss = (_start.inMilliseconds / 1000).toStringAsFixed(3);
    final t = ((_end - _start).inMilliseconds / 1000).toStringAsFixed(3);

    final copyArgs = _buildArgs(copy: true, ss: ss, t: t, muted: _muted);
    var out = await FfmpegWeb.run(
      files: {'in.mp4': widget.bytes},
      args: copyArgs,
      outputName: 'out.mp4',
    );
    // Stream copy can fail if the cut lands off a keyframe — re-encode.
    out ??= await FfmpegWeb.run(
      files: {'in.mp4': widget.bytes},
      args: _buildArgs(copy: false, ss: ss, t: t, muted: _muted),
      outputName: 'out.mp4',
    );

    if (!mounted) return;
    if (out == null) {
      setState(() {
        _exporting = false;
        _error = context.t('videoExportFailed');
      });
      return;
    }
    Navigator.pop(context, out);
  }

  List<String> _buildArgs({
    required bool copy,
    required String ss,
    required String t,
    required bool muted,
  }) {
    final args = ['-y', '-ss', ss, '-i', 'in.mp4', '-t', t];
    if (copy) {
      args.addAll(['-c:v', 'copy']);
      muted ? args.add('-an') : args.addAll(['-c:a', 'copy']);
    } else {
      args.addAll(
          ['-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p']);
      muted ? args.add('-an') : args.addAll(['-c:a', 'aac', '-b:a', '128k']);
    }
    args.add('out.mp4');
    return args;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _topBar(c),
          Expanded(child: Center(child: _preview())),
          if (_ready) _trimBar(c),
        ]),
      ),
    );
  }

  Widget _topBar(BrutalColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: _exporting ? null : () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white),
            onPressed: _exporting
                ? null
                : () {
                    setState(() => _muted = !_muted);
                    _ctrl?.setVolume(_muted ? 0 : 1);
                  },
          ),
          TextButton(
            onPressed: _exporting ? null : _export,
            child: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(context.t('done'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
      );

  Widget _preview() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!,
            style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
      );
    }
    final ctrl = _ctrl;
    if (!_ready || ctrl == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return GestureDetector(
      onTap: () => setState(() => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play()),
      child: AspectRatio(
        aspectRatio: ctrl.value.aspectRatio == 0 ? 9 / 16 : ctrl.value.aspectRatio,
        child: VideoPlayer(ctrl),
      ),
    );
  }

  Widget _trimBar(BrutalColors c) => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        color: Colors.black,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_start),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              Text(_fmt(_end - _start),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              Text(_fmt(_end),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: c.accent,
              overlayColor: c.accent.withOpacity(0.2),
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: RangeSlider(
              min: 0,
              max: _total.inMilliseconds.toDouble().clamp(1, double.infinity),
              values: RangeValues(
                _start.inMilliseconds.toDouble(),
                _end.inMilliseconds.toDouble(),
              ),
              onChanged: _exporting ? null : (v) => _onRangeChanged(v),
            ),
          ),
        ]),
      );
}
