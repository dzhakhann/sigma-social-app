import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../l10n/app_strings.dart';

/// Instagram-style story editor: full-screen preview of the picked photo with
/// a draggable / scalable text overlay and a colour palette. The final story
/// is rendered (photo + text) into one image, so the text is visible for every
/// viewer on every device. Returns the composed PNG bytes via Navigator.pop.
class StoryEditorScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const StoryEditorScreen({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final _boundaryKey = GlobalKey();
  final _textCtrl = TextEditingController();

  double? _imgAspect; // width / height of the picked photo
  String _text = '';
  Offset _textPos = const Offset(0.5, 0.5); // relative (0..1)
  double _textScale = 1.0;
  double _baseScale = 1.0;
  int _colorIdx = 0;
  bool _editingText = false;
  bool _publishing = false;

  static const _colors = [
    Colors.white, Colors.black, Color(0xFFFF5252), Color(0xFFFFD740),
    Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB),
  ];

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.imageBytes).then((img) {
      if (mounted) setState(() => _imgAspect = img.width / img.height);
      img.dispose();
    });
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() {
      _publishing = true;
      _editingText = false;
    });
    // Give the frame a tick to hide the editing UI before capture.
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (mounted && data != null) {
        Navigator.pop(context, data.buffer.asUint8List());
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _publishing = false);
  }

  void _openTextInput() {
    _textCtrl.text = _text;
    setState(() => _editingText = true);
  }

  void _commitText() {
    setState(() {
      _text = _textCtrl.text.trim();
      _editingText = false;
    });
  }

  // The photo starts in "cover" framing and the user can pinch-zoom (up to 5x)
  // and pan to choose the visible area, exactly like Instagram stories.
  Widget _zoomablePhoto(Size size) {
    final aspect = _imgAspect;
    if (aspect == null) {
      return Image.memory(widget.imageBytes, fit: BoxFit.cover);
    }
    final screenAspect = size.width / size.height;
    double childW, childH;
    if (aspect >= screenAspect) {
      childH = size.height;
      childW = size.height * aspect;
    } else {
      childW = size.width;
      childH = size.width / aspect;
    }
    return InteractiveViewer(
      constrained: false,
      minScale: 1,
      maxScale: 5,
      boundaryMargin: EdgeInsets.zero,
      child: SizedBox(
        width: childW,
        height: childH,
        child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── The story canvas (captured on publish) ─────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: Colors.black),
              // Instagram-style: pinch to zoom / drag to reframe the photo.
              _zoomablePhoto(size),
              if (_text.isNotEmpty && !_editingText)
                Positioned(
                  left: _textPos.dx * size.width - 150,
                  top: _textPos.dy * size.height - 40,
                  child: GestureDetector(
                    onScaleStart: (_) => _baseScale = _textScale,
                    onScaleUpdate: (d) => setState(() {
                      _textScale = (_baseScale * d.scale).clamp(0.5, 3.0);
                      _textPos = Offset(
                        (_textPos.dx + d.focalPointDelta.dx / size.width)
                            .clamp(0.05, 0.95),
                        (_textPos.dy + d.focalPointDelta.dy / size.height)
                            .clamp(0.05, 0.95),
                      );
                    }),
                    onTap: _openTextInput,
                    child: SizedBox(
                      width: 300,
                      child: Text(
                        _text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _colors[_colorIdx],
                          fontSize: 26 * _textScale,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),

        // ── Top bar ────────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.text_fields_rounded,
                  color: Colors.white, size: 26),
              onPressed: _openTextInput,
            ),
          ]),
        ),

        // ── Text input overlay ─────────────────────────────────────────
        if (_editingText)
          Positioned.fill(
            child: GestureDetector(
              onTap: _commitText,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _textCtrl,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _colors[_colorIdx],
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(border: InputBorder.none),
                      onSubmitted: (_) => _commitText(),
                    ),
                    const SizedBox(height: 20),
                    // colour palette
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_colors.length, (i) {
                        final sel = i == _colorIdx;
                        return GestureDetector(
                          onTap: () => setState(() => _colorIdx = i),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            width: sel ? 32 : 26,
                            height: sel ? 32 : 26,
                            decoration: BoxDecoration(
                              color: _colors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white,
                                  width: sel ? 3 : 1.5),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _commitText,
                      child: Text(context.t('done'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Publish button ─────────────────────────────────────────────
        if (!_editingText)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 16,
            child: GestureDetector(
              onTap: _publish,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.t('publishBtn'),
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  const SizedBox(width: 6),
                  _publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.arrow_forward_rounded,
                          color: Colors.black, size: 18),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }
}
