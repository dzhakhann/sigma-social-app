import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Telegram-style in-app story camera: full-screen preview, shutter, flash,
/// front/back flip and a gallery shortcut. Returns the photo bytes via
/// Navigator.pop — the caller sends them into the story editor.
class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen({Key? key}) : super(key: key);

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
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(_flash ? FlashMode.auto : FlashMode.off);
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
    try {
      await _ctrl?.setFlashMode(_flash ? FlashMode.auto : FlashMode.off);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final xfile = await ctrl.takePicture();
      final bytes = await xfile.readAsBytes();
      if (mounted) {
        Navigator.pop(context, bytes);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _fromGallery() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (mounted) Navigator.pop(context, bytes);
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

        // ── Top bar: close / flash ─────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(children: [
            _round(Icons.close_rounded, () => Navigator.pop(context)),
            const Spacer(),
            _round(_flash ? Icons.flash_auto_rounded : Icons.flash_off_rounded,
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
              _round(Icons.photo_library_rounded, _fromGallery, size: 48),
              // Shutter
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: _busy ? Colors.white54 : Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              _round(Icons.flip_camera_ios_rounded, _flip, size: 48),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }
}
