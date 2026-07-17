import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'package:screen_brightness/screen_brightness.dart';
import '../services/api_service.dart';
import 'sigma_gallery_screen.dart';

/// Un-mirror a front-camera shot (runs in an isolate — decoding a full-res
/// JPEG on the UI thread would jank). Android's camera plugin saves the front
/// lens mirrored, matching the preview; Telegram/Instagram save it the way
/// other people see you, so we flip it back horizontally.
Uint8List _flipHorizontally(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  return Uint8List.fromList(
      img.encodeJpg(img.flipHorizontal(decoded), quality: 92));
}

/// What a capture produced: a photo (bytes, ready for the editor) or a video
/// (a file PATH — a 60s clip is far too large to pass around as bytes, and
/// copying it would double the storage for no reason).
class StoryCapture {
  final Uint8List? photo;
  final String? videoPath;

  /// Tappable link stickers: {label, url, x, y, scale, style}. They are NOT
  /// baked into the media — the viewer draws them as real buttons.
  final List<Map> links;

  /// The story's ONE music track (Rhythm link + fragment + sticker placement),
  /// or null. Never audio bytes — the viewer streams from the catalog.
  final Map? music;

  const StoryCapture.photo(Uint8List bytes, {this.links = const [], this.music})
      : photo = bytes,
        videoPath = null;
  const StoryCapture.video(String path, {this.links = const [], this.music})
      : videoPath = path,
        photo = null;

  bool get isVideo => videoPath != null;
}

/// Telegram-style in-app story camera: full-screen preview, shutter, flash,
/// front/back flip and a gallery shortcut. Tap = photo, hold = video (max 60s).
/// Returns a [StoryCapture] via Navigator.pop — the caller opens the editor.
class StoryCameraScreen extends StatefulWidget {
  /// Hold-to-record. Off for pickers that only accept a photo (avatar, chat).
  final bool allowVideo;
  const StoryCameraScreen({Key? key, this.allowVideo = true})
      : super(key: key);

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  int _camIdx = 0; // back camera first, like Telegram
  bool _flash = false;
  bool _busy = false;

  /// Screen-flash overlay: the front camera has no LED on nearly every Android
  /// phone, so — like Instagram/Telegram/Snapchat — we blast the screen white
  /// at full brightness for the exposure, then restore it.
  bool _screenFlash = false;

  bool get _isFront =>
      _cameras.isNotEmpty &&
      _cameras[_camIdx].lensDirection == CameraLensDirection.front;

  /// Whether this lens can drive a real LED. Front lenses on Android almost
  /// never can — we probe once and fall back to the screen flash.
  bool _lensHasTorch = true;

  // ── Video: hold the shutter to record, release to stop (Instagram) ────────
  static const _maxVideo = Duration(seconds: 60);
  bool _recording = false;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;


  Future<void> _applyFlashMode(CameraController ctrl) async {
    if (!_flash) {
      try { await ctrl.setFlashMode(FlashMode.off); } catch (_) {}
      _lensHasTorch = true;
      return;
    }
    // Torch = constant LED, on until toggled off (what the button promises).
    try {
      await ctrl.setFlashMode(FlashMode.torch);
      _lensHasTorch = true;
    } catch (_) {
      // No LED on this lens → screen flash at capture time instead.
      _lensHasTorch = false;
      try { await ctrl.setFlashMode(FlashMode.off); } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _start(_camIdx);
    } catch (_) {}
  }

  Future<void> _start(int idx) async {
    final old = _ctrl;
    _ctrl = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final ctrl = CameraController(
      _cameras[idx],
      ResolutionPreset.high,
      // Audio on from the start: hold-to-record needs a sound track, and
      // re-creating the controller at the moment you press would lose the first
      // second of the clip.
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      // Locking orientation skips a re-orientation pass on every shot — part of
      // making the shutter feel instant.
      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      _camIdx = idx;
      await _applyFlashMode(ctrl);
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
          _camIdx = idx;
        });
      }
    } catch (_) {}
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    HapticFeedback.selectionClick();
    await _start((_camIdx + 1) % _cameras.length);
  }

  Future<void> _toggleFlash() async {
    _flash = !_flash;
    HapticFeedback.selectionClick();
    final ctrl = _ctrl;
    if (ctrl != null) await _applyFlashMode(ctrl);
    if (mounted) setState(() {});
  }

  /// Light the screen white at max brightness for the exposure, then restore.
  /// Used when the active lens has no LED (front camera on most phones).
  Future<double?> _beginScreenFlash() async {
    double? prev;
    try {
      prev = await ScreenBrightness().application;
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {}
    setState(() => _screenFlash = true);
    // Let the white frame actually render and the sensor meter for it.
    await Future.delayed(const Duration(milliseconds: 260));
    return prev;
  }

  Future<void> _endScreenFlash(double? prev) async {
    if (mounted) setState(() => _screenFlash = false);
    try {
      if (prev != null) {
        await ScreenBrightness().setApplicationScreenBrightness(prev);
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (_) {}
  }

  // ── Video recording ───────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!widget.allowVideo) return;
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _busy || _recording) return;
    try {
      await ctrl.startVideoRecording();
    } catch (_) {
      return;
    }
    HapticFeedback.mediumImpact();
    _recElapsed = Duration.zero;
    setState(() => _recording = true);
    // Drives the ring + timer, and hard-stops at 60s.
    _recTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() => _recElapsed += const Duration(milliseconds: 50));
      if (_recElapsed >= _maxVideo) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_recording) return;
    _recTimer?.cancel();
    _recTimer = null;
    setState(() { _recording = false; _busy = true; });
    HapticFeedback.selectionClick();
    try {
      final file = await ctrl.stopVideoRecording();
      if (mounted) {
        // Hand the clip back as a file path — video is far too big to pass
        // around as bytes, and copying it would double the storage.
        Navigator.pop(context, StoryCapture.video(file.path));
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  /// A quick tap while recording hasn't started yet = photo. The gesture layer
  /// decides; this only runs for taps.
  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _busy || _recording) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    // Flash on + no LED on this lens (front camera) → virtual screen flash.
    final useScreenFlash = _flash && !_lensHasTorch;
    double? prevBrightness;
    if (useScreenFlash) prevBrightness = await _beginScreenFlash();
    try {
      final xfile = await ctrl.takePicture();
      if (useScreenFlash) await _endScreenFlash(prevBrightness);
      var bytes = await xfile.readAsBytes();
      // Preview stays mirrored (natural for a selfie), but the SAVED photo is
      // un-mirrored — text reads correctly and you look like you do to others.
      if (_cameras[_camIdx].lensDirection == CameraLensDirection.front) {
        bytes = await compute(_flipHorizontally, bytes);
      }
      if (mounted) {
        Navigator.pop(context, StoryCapture.photo(bytes));
        return;
      }
    } catch (_) {}
    if (useScreenFlash) await _endScreenFlash(prevBrightness);
    if (mounted) setState(() => _busy = false);
  }

  // Sigmacta's own gallery, not the system picker. Photos AND videos, like
  // Telegram Stories. `allowCamera: false` — we're already in the camera.
  Future<void> _fromGallery() async {
    final files = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => const SigmaGalleryScreen(
            type: RequestType.common, allowCamera: false),
      ),
    );
    if (files is! List<File> || files.isEmpty) return;
    final f = files.first;
    final isVideo = ApiService.isVideoStory(f.path);
    if (!mounted) return;
    if (isVideo) {
      Navigator.pop(context, StoryCapture.video(f.path));
    } else {
      Navigator.pop(context, StoryCapture.photo(await f.readAsBytes()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _start(_camIdx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Preview ────────────────────────────────────────────────────
        Positioned.fill(
          child: ctrl != null && ctrl.value.isInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: ctrl.value.previewSize?.height ?? 1080,
                    height: ctrl.value.previewSize?.width ?? 1920,
                    child: CameraPreview(ctrl),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
        ),

        // ── Virtual front flash: white screen during the exposure ──────
        if (_screenFlash)
          const Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: Colors.white)),
          ),

        // ── Recording timer (red dot + mm:ss), Instagram-style ─────────
        if (_recording)
          Positioned(
            top: MediaQuery.of(context).padding.top + 18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Text(_fmt(_recElapsed),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                  ),
                ),
              ),
            ),
          ),

        // ── Top bar: close / flash ─────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(children: [
            _round(Icons.close_rounded, () => Navigator.pop(context)),
            const Spacer(),
            // Back lens = real LED torch, front lens = screen flash.
            _round(
                _flash
                    ? (_isFront
                        ? Icons.flash_on_rounded
                        : Icons.flashlight_on_rounded)
                    : Icons.flash_off_rounded,
                _toggleFlash),
          ]),
        ),

        // ── Bottom controls: gallery / shutter / flip ──────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Opacity(
                opacity: _recording ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _recording,
                  child: _round(Icons.photo_library_rounded, _fromGallery,
                      size: 48),
                ),
              ),
              // Shutter: tap = photo, press-and-hold = video (Instagram).
              GestureDetector(
                onTap: _shoot,
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
                // Releasing after dragging off the button must still stop.
                onLongPressCancel: () { if (_recording) _stopRecording(); },
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: Stack(alignment: Alignment.center, children: [
                    // Progress ring — fills over the 60s limit.
                    if (_recording)
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: CircularProgressIndicator(
                          value: (_recElapsed.inMilliseconds /
                                  _maxVideo.inMilliseconds)
                              .clamp(0.0, 1.0),
                          strokeWidth: 4,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Color(0xFFFF3B30)),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: _recording ? 76 : 76,
                      height: _recording ? 76 : 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _recording ? Colors.transparent : Colors.white,
                            width: 4),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: _recording
                              ? const Color(0xFFFF3B30)
                              : (_busy ? Colors.white54 : Colors.white),
                          borderRadius: BorderRadius.circular(_recording ? 8 : 40),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              Opacity(
                opacity: _recording ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _recording,
                  child: _round(Icons.flip_camera_ios_rounded, _flip, size: 48),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap, {double size = 42}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      );

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _recTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }
}
