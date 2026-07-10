import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Telegram-style full-screen photo viewer: pinch-to-zoom, double-tap to zoom,
/// and swipe down to dismiss. Opens with a Hero from the source avatar.
class PhotoViewScreen extends StatefulWidget {
  final String url;
  final String heroTag;
  const PhotoViewScreen({Key? key, required this.url, this.heroTag = ''})
      : super(key: key);

  static Route<void> route(String url, {String heroTag = ''}) =>
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) =>
            PhotoViewScreen(url: url, heroTag: heroTag),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      );

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  final _tc = TransformationController();
  TapDownDetails? _doubleTapPos;
  double _dragDy = 0;

  bool get _zoomed => _tc.value.getMaxScaleOnAxis() > 1.05;

  void _handleDoubleTap() {
    if (_zoomed) {
      _tc.value = Matrix4.identity();
    } else {
      final p = _doubleTapPos?.localPosition ?? Offset.zero;
      _tc.value = Matrix4.identity()
        ..translate(-p.dx * 1.5, -p.dy * 1.5)
        ..scale(2.5);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final opacity =
        (1 - (_dragDy.abs() / 400)).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(opacity),
      body: Stack(children: [
        GestureDetector(
          // Swipe-to-dismiss only when not zoomed in.
          onVerticalDragUpdate: _zoomed
              ? null
              : (d) => setState(() => _dragDy += d.delta.dy),
          onVerticalDragEnd: _zoomed
              ? null
              : (_) {
                  if (_dragDy.abs() > 110) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _dragDy = 0);
                  }
                },
          onDoubleTapDown: (d) => _doubleTapPos = d,
          onDoubleTap: _handleDoubleTap,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, _dragDy),
              child: Hero(
                tag: widget.heroTag.isEmpty ? widget.url : widget.heroTag,
                child: InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 4,
                  onInteractionEnd: (_) => setState(() {}),
                  child: CachedNetworkImage(
                    imageUrl: widget.url,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                    errorWidget: (_, __, ___) => const Icon(Icons.person,
                        color: Colors.white54, size: 120),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }
}
