import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../l10n/app_strings.dart';

/// Telegram-style avatar crop editor. The user pans and pinch-zooms the photo
/// under a fixed circular window; whatever is inside the square is saved.
/// Works with any source aspect ratio (3×10, 9×16, panoramas, …) — the result
/// is always a square crop. Returns PNG bytes via Navigator.pop.
class AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const AvatarCropScreen({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final _boundaryKey = GlobalKey();
  double? _imgAspect; // width / height
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final img = await decodeImageFromList(widget.imageBytes);
    if (mounted) {
      setState(() => _imgAspect = img.width / img.height);
    }
    img.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Let the frame settle before capturing.
    await Future.delayed(const Duration(milliseconds: 40));
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // Capture at a ratio that yields ~800px squares on typical phones.
      final square = MediaQuery.of(context).size.width;
      final ratio = (800 / square).clamp(1.0, 3.0);
      final img = await boundary.toImage(pixelRatio: ratio);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (mounted && data != null) {
        Navigator.pop(context, data.buffer.asUint8List());
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final square = size.width;
    final aspect = _imgAspect;

    // "Cover" dimensions: the shortest side of the photo fills the square,
    // the rest overflows and can be panned into view.
    double childW = square, childH = square;
    if (aspect != null) {
      if (aspect >= 1) {
        childH = square;
        childW = square * aspect;
      } else {
        childW = square;
        childH = square / aspect;
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: aspect == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Stack(children: [
              // Crop area centered vertically
              Center(
                child: SizedBox(
                  width: square,
                  height: square,
                  child: Stack(fit: StackFit.expand, children: [
                    // The captured square: photo pans/zooms inside it.
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: ClipRect(
                        child: InteractiveViewer(
                          constrained: false,
                          minScale: 1,
                          maxScale: 6,
                          boundaryMargin: EdgeInsets.zero,
                          child: SizedBox(
                            width: childW,
                            height: childH,
                            child: Image.memory(widget.imageBytes,
                                fit: BoxFit.fill),
                          ),
                        ),
                      ),
                    ),
                    // Circular mask overlay (visual only — not captured,
                    // because it sits outside the RepaintBoundary).
                    IgnorePointer(
                      child: CustomPaint(painter: _CircleMaskPainter()),
                    ),
                  ]),
                ),
              ),

              // Top bar
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // Bottom bar: hint + save
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                left: 24,
                right: 24,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.t('cropHint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : Text(context.t('saveBtn'),
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}

/// Darkens everything outside the inscribed circle, Telegram-style.
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final circle = Path()
      ..addOval(Rect.fromCircle(
          center: size.center(Offset.zero), radius: size.width / 2));
    final mask = Path.combine(PathOperation.difference, full, circle);
    canvas.drawPath(mask, Paint()..color = Colors.black.withOpacity(0.55));
    canvas.drawCircle(size.center(Offset.zero), size.width / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white38);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
