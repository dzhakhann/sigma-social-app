import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Telegram-style round video recorder.
/// Push this screen, it returns a [File] with the recorded .mp4 or null.
class VideoCircleRecorderScreen extends StatefulWidget {
  const VideoCircleRecorderScreen({super.key});

  @override
  State<VideoCircleRecorderScreen> createState() =>
      _VideoCircleRecorderScreenState();
}

class _VideoCircleRecorderScreenState
    extends State<VideoCircleRecorderScreen>
    with TickerProviderStateMixin {
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];

  bool _ready = false;
  bool _recording = false;
  int _facingIdx = 1; // 1 = front by default (like Telegram)

  // Timer
  int _elapsed = 0;
  Timer? _timer;
  static const _maxSecs = 60;

  // Progress ring animation
  late AnimationController _ringCtrl;
  late Animation<double> _ringAnim;

  // Record button pulse
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _maxSecs),
    );
    _ringAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_ringCtrl);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_facingIdx.clamp(0, _cameras.length - 1));
    } catch (_) {}
  }

  Future<void> _startCamera(int idx) async {
    await _ctrl?.dispose();
    final cam = _cameras[idx];
    _ctrl = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _ctrl!.initialize();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording) return;
    setState(() => _ready = false);
    _facingIdx = (_facingIdx + 1) % _cameras.length;
    await _startCamera(_facingIdx);
  }

  Future<void> _startRecording() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _recording) return;
    try {
      await _ctrl!.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsed = 0;
      });
      _ringCtrl.forward(from: 0);
      _pulseCtrl.repeat(reverse: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        if (_elapsed >= _maxSecs) _stopAndSend();
      });
    } catch (_) {}
  }

  Future<void> _stopAndSend() async {
    if (!_recording) return;
    _timer?.cancel();
    _ringCtrl.stop();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    setState(() => _recording = false);
    try {
      final xFile = await _ctrl!.stopVideoRecording();
      if (mounted) Navigator.pop(context, File(xFile.path));
    } catch (_) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  void _cancel() {
    if (_recording) {
      _timer?.cancel();
      _ringCtrl.stop();
      _pulseCtrl.stop();
      _ctrl?.stopVideoRecording().catchError((_) {});
    }
    Navigator.pop(context, null);
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer?.cancel();
    _ringCtrl.dispose();
    _pulseCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = min(size.width, size.height) * 0.82;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // ── Background blur overlay ──────────────────────────────────
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.85)),
          ),

          // ── Round camera preview ──────────────────────────────────────
          Center(
            child: SizedBox(
              width: circleSize,
              height: circleSize,
              child: Stack(alignment: Alignment.center, children: [
                // Progress ring
                AnimatedBuilder(
                  animation: _ringAnim,
                  builder: (_, __) => CustomPaint(
                    size: Size(circleSize, circleSize),
                    painter: _RingPainter(
                      progress: _ringAnim.value,
                      color: _recording
                          ? const Color(0xFF4F7CFF)
                          : Colors.white24,
                      strokeWidth: 3.5,
                    ),
                  ),
                ),

                // Camera circle
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: ClipOval(
                    child: _ready && _ctrl != null
                        ? _buildPreview(circleSize - 10)
                        : Container(
                            width: circleSize - 10,
                            height: circleSize - 10,
                            color: const Color(0xFF1A1A1A),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF4F7CFF),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                  ),
                ),

                // Recording red dot (top-left of circle)
                if (_recording)
                  Positioned(
                    top: 18,
                    left: 18,
                    child: _RecordingDot(),
                  ),
              ]),
            ),
          ),

          // ── Timer ──────────────────────────────────────────────────────
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _recording ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _fmt(_elapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom controls ────────────────────────────────────────────
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Hint text
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  _recording
                      ? 'Отпустите, чтобы отправить'
                      : 'Зажмите кнопку для записи',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Cancel button
                  GestureDetector(
                    onTap: _cancel,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),

                  // Record button — press and HOLD to record, release to send.
                  GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopAndSend(),
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) => Transform.scale(
                        scale: _recording ? _pulseAnim.value : 1.0,
                        child: child,
                      ),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _recording
                              ? const Color(0xFF4F7CFF)
                              : Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: (_recording
                                      ? const Color(0xFF4F7CFF)
                                      : Colors.white)
                                  .withOpacity(0.35),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: _recording
                            ? const Icon(Icons.stop_rounded,
                                color: Colors.white, size: 36)
                            : Container(
                                margin: const EdgeInsets.all(14),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE53E3E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                      ),
                    ),
                  ),

                  // Flip camera button
                  GestureDetector(
                    onTap: _flipCamera,
                    child: AnimatedOpacity(
                      opacity: _recording ? 0.3 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white24, width: 1),
                        ),
                        child: const Icon(Icons.flip_camera_ios_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPreview(double size) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      return Container(width: size, height: size, color: Colors.black);
    }
    final camAspect = _ctrl!.value.aspectRatio;
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size,
          height: size / camAspect,
          child: CameraPreview(_ctrl!),
        ),
      ),
    );
  }
}

// ── Progress ring painter ────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  const _RingPainter(
      {required this.progress,
      required this.color,
      required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress <= 0) return;

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Blinking red dot ─────────────────────────────────────────────────────────
class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFE53E3E),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
