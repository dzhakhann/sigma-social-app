import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

/// The message input bar — emoji toggle, text field, send/mic button and the
/// full Telegram-style voice-recording overlay.
///
/// Single implementation shared by 1:1 and group chat. Group chat previously
/// had its own cut-down copy with no microphone at all, so voice messages
/// simply did not exist there; anything added here now lands in both.
///
/// Sending stays with the caller — the two screens post to different
/// endpoints — so a finished recording is uploaded here and handed back via
/// [onVoiceReady] as a URL plus its length.
class ChatComposer extends StatefulWidget {
  final TextEditingController msgCtrl;
  final TextEditingController editCtrl;
  final FocusNode focusNode;
  final bool showEmoji;
  final bool isEditing;

  /// Uploads are attributed to this user.
  final String userId;

  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;
  final VoidCallback onSaveEdit;

  /// Fired the moment recording stops, with the LOCAL file path — show the
  /// bubble now, don't wait for the network.
  final void Function(String localPath, int secs) onVoiceRecorded;

  /// Fired when the upload finishes. `url` is null if it failed, so the caller
  /// can mark that bubble as failed instead of leaving it pending forever.
  final void Function(String localPath, String? url, int secs) onVoiceUploaded;

  const ChatComposer({
    super.key,
    required this.msgCtrl,
    required this.editCtrl,
    required this.focusNode,
    required this.showEmoji,
    required this.isEditing,
    required this.userId,
    required this.onToggleEmoji,
    required this.onSend,
    required this.onSaveEdit,
    required this.onVoiceRecorded,
    required this.onVoiceUploaded,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordSecs = 0;
  Timer? _recordTimer;
  double _dragOffset = 0;
  bool _dragCancelled = false;

  /// Hands-free recording: swiping up past [_lockThreshold] latches it, so
  /// lifting the finger no longer sends. Telegram's behaviour, and the reason
  /// long messages don't require holding the phone still.
  bool _locked = false;
  double _dragUp = 0;
  static const _lockThreshold = 56.0;

  /// Rolling amplitude history, newest last — drives the live waveform.
  /// Capped, so it can't grow for the length of the recording.
  final List<double> _levels = [];
  StreamSubscription? _ampSub;
  static const _maxLevels = 34;

  /// Bumped on every captured sample. shouldRepaint can't rely on the list's
  /// LENGTH: once the buffer is full it stops changing while the values keep
  /// moving, which froze the meter a few seconds into every recording.
  int _levelRev = 0;

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _pulseAnim = Tween<double>(begin: 1, end: 1.35)
      .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl.dispose();
    // Fire-and-forget: the widget is going away, we just must not leave the
    // microphone held open.
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    // record_web ignores `path` entirely — it records to an in-memory Blob
    // and hands back a blob: URL from stop() — so path_provider (no web
    // build at all) is only needed on native, where the path is real.
    final path = kIsWeb
        ? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'
        : '${(await getTemporaryDirectory()).path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordSecs = 0;
      _dragOffset = 0;
      _dragUp = 0;
      _locked = false;
      _dragCancelled = false;
    });
    _pulseCtrl.repeat(reverse: true);
    _levels.clear();
    // The recorder reports dBFS (negative, 0 = loudest). Map roughly -45..0 dB
    // onto 0..1 so quiet speech still moves the bars visibly — a linear read of
    // the raw value leaves them almost flat.
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((amp) {
      if (!mounted) return;
      final norm = ((amp.current + 45) / 45).clamp(0.05, 1.0);
      setState(() {
        _levels.add(norm);
        if (_levels.length > _maxLevels) _levels.removeAt(0);
        _levelRev++;
      });
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSecs++);
    });
  }

  void _updateDrag(Offset d) {
    if (!_isRecording || _locked) return;
    setState(() {
      _dragOffset = d.dx.clamp(-150.0, 0.0);
      _dragUp = (-d.dy).clamp(0.0, 120.0);
      // Past this point releasing discards the clip instead of sending it.
      if (_dragOffset < -100) _dragCancelled = true;
      // Upward wins over sideways: a diagonal swipe should latch rather than
      // half-arm a cancel the user can no longer complete.
      if (_dragUp > _lockThreshold && !_dragCancelled) {
        _locked = true;
        _dragOffset = 0;
        HapticFeedback.mediumImpact();
      }
    });
  }

  /// Discards the clip without sending — the trash button while locked.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl
      ..stop()
      ..reset();
    await _recorder.cancel();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _locked = false;
      });
    }
  }

  Future<void> _stopAndSend() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl
      ..stop()
      ..reset();

    if (_dragCancelled) {
      await _recorder.cancel();
      if (mounted) setState(() => _isRecording = false);
      return;
    }

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _locked = false;
    });
    if (path == null) return;

    final secs = _recordSecs;
    // Hand the LOCAL file path over immediately so the bubble appears the
    // instant the finger lifts, then upload in the background and swap in the
    // URL. Awaiting the upload first is what made sending feel slow — the whole
    // UI sat behind a snackbar for as long as the network took.
    widget.onVoiceRecorded(path, secs);

    // stop() hands back a blob: URL on web, not a real file path — dart:io
    // File can't read that, but it IS a normal fetchable URL.
    final bytes = kIsWeb
        ? (await http.get(Uri.parse(path))).bodyBytes
        : await File(path).readAsBytes();
    final url = await ApiService.uploadMedia(
      bytes,
      folder: 'voice',
      ext: 'm4a',
      contentType: 'audio/m4a',
      userId: widget.userId,
    );
    widget.onVoiceUploaded(path, url, secs);
  }

  String _fmt(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return _isRecording ? _recordingBar(c) : _normalBar(c);
  }

  Widget _recordingBar(BrutalColors c) {
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.danger.withOpacity(0.4),
                      blurRadius: 6 * _pulseAnim.value,
                      spreadRadius: 2 * (_pulseAnim.value - 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _fmt(_recordSecs),
              style: TextStyle(
                  color: c.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (_locked) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock_rounded, size: 15, color: c.accent),
            ],
            const SizedBox(width: 10),
            // Live level meter: scrolls right-to-left as you talk.
            Expanded(
              child: SizedBox(
                height: 26,
                child: CustomPaint(
                  painter: _LiveWavePainter(
                      levels: _levels,
                      rev: _levelRev,
                      color: c.accent,
                      max: _maxLevels),
                ),
              ),
            ),
            if (_locked)
              // Hands-free: an explicit trash button replaces slide-to-cancel,
              // since there's no finger on screen to slide with any more.
              GestureDetector(
                onTap: _cancelRecording,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.delete_outline_rounded,
                      color: c.danger, size: 24),
                ),
              )
            else
              AnimatedOpacity(
                opacity: _dragCancelled ? 0.3 : 0.7,
                duration: const Duration(milliseconds: 150),
                child: Transform.translate(
                  offset: Offset(_dragOffset * 0.3, 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_left_rounded,
                        color: c.inkSoft, size: 18),
                    Text(context.t('slideCancel'),
                        style: TextStyle(color: c.inkSoft, fontSize: 13)),
                  ]),
                ),
              ),
            const SizedBox(width: 12),
            // Lock hint floats above the send button while unlocked, and the
            // button itself takes over once latched.
            Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              if (!_locked)
                Positioned(
                  bottom: 46,
                  child: Opacity(
                    // Fades in as the finger climbs, so the affordance appears
                    // exactly when the gesture starts to make sense.
                    opacity: (0.35 + _dragUp / _lockThreshold * 0.65)
                        .clamp(0.0, 1.0),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock_outline_rounded,
                          color: c.inkSoft, size: 17),
                      Icon(Icons.keyboard_arrow_up_rounded,
                          color: c.inkSoft, size: 15),
                    ]),
                  ),
                ),
              GestureDetector(
                onTap: _stopAndSend,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      gradient: c.buttonGradient, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _normalBar(BrutalColors c) {
    final active = widget.isEditing ? widget.editCtrl : widget.msgCtrl;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: SafeArea(
        top: false,
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
                widget.showEmoji
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                color: c.inkSoft),
            onPressed: widget.onToggleEmoji,
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                  color: c.surface2, borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller: active,
                focusNode: widget.focusNode,
                onTap: () {
                  if (widget.showEmoji) widget.onToggleEmoji();
                },
                maxLines: null,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: InputDecoration(
                  hintText: context.t('messageHint'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: false,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: active,
            builder: (_, __) {
              final hasText = active.text.trim().isNotEmpty;
              if (hasText) {
                return GestureDetector(
                  onTap: widget.isEditing ? widget.onSaveEdit : widget.onSend,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        gradient: c.buttonGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                );
              }
              // Hold to record, slide left to cancel — Telegram behaviour.
              return GestureDetector(
                onLongPressStart: (_) {
                  HapticFeedback.mediumImpact();
                  _startRecording();
                },
                onLongPressMoveUpdate: (d) =>
                    _updateDrag(d.localOffsetFromOrigin),
                // Once locked, lifting the finger must NOT send — the user
                // carries on talking and presses the send button themselves.
                onLongPressEnd: (_) {
                  if (!_locked) _stopAndSend();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_rounded, color: c.accent, size: 22),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}

/// Recording level meter: one rounded bar per captured amplitude sample,
/// oldest at the left. Bars are drawn straight from the sample list rather than
/// animated individually — the list changing IS the animation, so there's no
/// controller and no per-bar widget.
class _LiveWavePainter extends CustomPainter {
  final List<double> levels;
  final int rev;
  final Color color;
  final int max;

  _LiveWavePainter(
      {required this.levels,
      required this.rev,
      required this.color,
      required this.max});

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = size.width / max;
    final barW = (slot * 0.5).clamp(1.5, 3.0);
    final mid = size.height / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < levels.length; i++) {
      // Fade the oldest bars so the meter trails off instead of ending abruptly.
      paint.color = color.withOpacity(0.35 + 0.65 * (i / levels.length));
      final h = (levels[i] * size.height).clamp(2.0, size.height);
      final x = i * slot;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, barW, h),
          Radius.circular(barW),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter o) =>
      o.rev != rev || o.color != color;
}
