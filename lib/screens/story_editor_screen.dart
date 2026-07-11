import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../l10n/app_strings.dart';

/// Instagram-style story editor:
///  · pinch-zoom / drag the photo (in AND out — black canvas around);
///  · multiple draggable & scalable overlays: text and emoji stickers;
///  · freehand drawing with a colour palette and undo;
///  · long-press an overlay to delete it.
/// The result (photo + overlays + drawing) is rendered into one image, so it
/// looks identical for every viewer. Returns PNG bytes via Navigator.pop.
class StoryEditorScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const StoryEditorScreen({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryItem {
  String text;
  int colorIdx;
  Offset pos; // relative 0..1
  double scale;
  final bool isEmoji;
  _StoryItem({
    required this.text,
    required this.isEmoji,
    this.colorIdx = 0,
    this.pos = const Offset(0.5, 0.45),
    this.scale = 1.0,
  });
}

class _Stroke {
  final List<Offset> points = [];
  final Color color;
  _Stroke(this.color);
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final _boundaryKey = GlobalKey();
  final _textCtrl = TextEditingController();

  double? _imgAspect;
  final List<_StoryItem> _items = [];
  final List<_Stroke> _strokes = [];
  int _colorIdx = 0;
  bool _editingText = false;
  bool _drawing = false;
  bool _publishing = false;
  _StoryItem? _editTarget; // overlay being re-edited
  double _baseScale = 1.0;

  static const _colors = [
    Colors.white, Colors.black, Color(0xFFFF5252), Color(0xFFFFD740),
    Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB),
  ];

  static const _emojis = [
    '😀','😂','😍','🥳','😎','🔥','❤️','💯','👍','🙌','✨','⭐',
    '🎉','💪','🚀','🌈','☀️','🌙','🍕','⚽','🎵','😜','🥰','😇',
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
      _drawing = false;
    });
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

  void _openTextInput({_StoryItem? edit}) {
    _editTarget = edit;
    _textCtrl.text = edit?.text ?? '';
    if (edit != null) _colorIdx = edit.colorIdx;
    setState(() {
      _editingText = true;
      _drawing = false;
    });
  }

  void _commitText() {
    final t = _textCtrl.text.trim();
    setState(() {
      if (_editTarget != null) {
        if (t.isEmpty) {
          _items.remove(_editTarget);
        } else {
          _editTarget!
            ..text = t
            ..colorIdx = _colorIdx;
        }
      } else if (t.isNotEmpty) {
        _items.add(_StoryItem(text: t, isEmoji: false, colorIdx: _colorIdx));
      }
      _editTarget = null;
      _editingText = false;
    });
  }

  void _addEmoji(String e) {
    setState(() {
      _items.add(_StoryItem(
          text: e, isEmoji: true, pos: const Offset(0.5, 0.45), scale: 1.4));
    });
  }

  void _showEmojiStrip() {
    setState(() => _drawing = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      barrierColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 200,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(10),
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _addEmoji(e);
                      },
                      child: Center(
                          child:
                              Text(e, style: const TextStyle(fontSize: 34))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

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
      minScale: 0.4,
      maxScale: 5,
      boundaryMargin: EdgeInsets.symmetric(
          horizontal: size.width, vertical: size.height),
      child: SizedBox(
        width: childW,
        height: childH,
        child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
      ),
    );
  }

  Widget _overlay(_StoryItem it, Size size) {
    return Positioned(
      left: it.pos.dx * size.width - 150,
      top: it.pos.dy * size.height - 40,
      child: GestureDetector(
        onScaleStart: (_) => _baseScale = it.scale,
        onScaleUpdate: (d) => setState(() {
          it.scale = (_baseScale * d.scale).clamp(0.4, 4.0);
          it.pos = Offset(
            (it.pos.dx + d.focalPointDelta.dx / size.width)
                .clamp(0.02, 0.98),
            (it.pos.dy + d.focalPointDelta.dy / size.height)
                .clamp(0.02, 0.98),
          );
        }),
        onTap: it.isEmoji ? null : () => _openTextInput(edit: it),
        onLongPress: () => setState(() => _items.remove(it)),
        child: SizedBox(
          width: 300,
          child: Text(
            it.text,
            textAlign: TextAlign.center,
            style: it.isEmoji
                ? TextStyle(fontSize: 44 * it.scale)
                : TextStyle(
                    color: _colors[it.colorIdx],
                    fontSize: 26 * it.scale,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black54),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Canvas captured on publish ─────────────────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: Colors.black),
              _zoomablePhoto(size),
              // Drawing layer (on top of the photo, below stickers).
              IgnorePointer(
                ignoring: !_drawing,
                child: GestureDetector(
                  onPanStart: _drawing
                      ? (d) => setState(() => _strokes
                          .add(_Stroke(_colors[_colorIdx])
                            ..points.add(d.localPosition)))
                      : null,
                  onPanUpdate: _drawing
                      ? (d) => setState(
                          () => _strokes.last.points.add(d.localPosition))
                      : null,
                  child: CustomPaint(
                    painter: _DrawPainter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (!_editingText)
                ..._items.map((it) => _overlay(it, size)),
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
            if (_strokes.isNotEmpty && _drawing)
              IconButton(
                icon: const Icon(Icons.undo_rounded,
                    color: Colors.white, size: 26),
                onPressed: () =>
                    setState(() => _strokes.removeLast()),
              ),
            IconButton(
              icon: Icon(Icons.brush_rounded,
                  color: _drawing ? Colors.amberAccent : Colors.white,
                  size: 26),
              onPressed: () => setState(() {
                _drawing = !_drawing;
                _editingText = false;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.emoji_emotions_rounded,
                  color: Colors.white, size: 26),
              onPressed: _showEmojiStrip,
            ),
            IconButton(
              icon: const Icon(Icons.text_fields_rounded,
                  color: Colors.white, size: 26),
              onPressed: () => _openTextInput(),
            ),
          ]),
        ),

        // ── Colour palette (visible while drawing) ─────────────────────
        if (_drawing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
            child: _palette(),
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
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                      onSubmitted: (_) => _commitText(),
                    ),
                    const SizedBox(height: 20),
                    _palette(),
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

  Widget _palette() {
    return Row(
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
              border: Border.all(color: Colors.white, width: sel ? 3 : 1.5),
            ),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }
}

class _DrawPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _DrawPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}
