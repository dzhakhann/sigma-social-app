import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Shared music visuals: the animated equalizer, the Instagram-style story
/// sticker card and a marquee for long titles. One implementation everywhere —
/// editor, story viewer and profile — so the look never drifts apart and the
/// animation keeps running wherever the widget is mounted (each instance owns
/// its controller, which is what keeps it alive AFTER publishing too).
class EqualizerBars extends StatefulWidget {
  final double scale;
  final Color color;
  const EqualizerBars({Key? key, this.scale = 1.0, this.color = Colors.white})
      : super(key: key);

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  static const _phases = [0.9, 0.45, 0.75];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _phases.length; i++) ...[
            Container(
              width: 5 * s,
              height: (8 + 16 * _phases[i] * (0.35 + 0.65 * _c.value)) * s,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(3 * s),
              ),
            ),
            if (i != _phases.length - 1) SizedBox(width: 3.5 * s),
          ],
        ],
      ),
    );
  }
}

/// The white story music card: artwork with pulsing bars, bold title, artist.
class MusicStickerCard extends StatelessWidget {
  final String title;
  final String artist;
  final String artUrl;
  final double scale;
  const MusicStickerCard({
    Key? key,
    required this.title,
    required this.artist,
    required this.artUrl,
    this.scale = 1.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.all(9 * s),
      constraints: BoxConstraints(maxWidth: 240 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18 * s),
        boxShadow: [BoxShadow(blurRadius: 16 * s, color: Colors.black26)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12 * s),
          child: SizedBox(
            width: 52 * s,
            height: 52 * s,
            child: Stack(fit: StackFit.expand, children: [
              artUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: artUrl, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFF222327),
                      child: Icon(Icons.music_note_rounded,
                          size: 22 * s, color: Colors.white70)),
              Container(color: Colors.black26),
              Center(child: EqualizerBars(scale: s)),
            ]),
          ),
        ),
        SizedBox(width: 10 * s),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: const Color(0xFF101012),
                      fontSize: 15 * s,
                      fontWeight: FontWeight.w800)),
              if (artist.isNotEmpty) ...[
                SizedBox(height: 2 * s),
                Text(artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: const Color(0xFF7A7C85),
                        fontSize: 12.5 * s,
                        fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// Endless horizontal marquee for long track names (profile pill). Short text
/// just sits still — no pointless motion.
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double maxWidth;
  const Marquee(
      {Key? key, required this.text, required this.style, this.maxWidth = 160})
      : super(key: key);

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final overflows = painter.width > widget.maxWidth;
    if (!overflows) {
      return SizedBox(
        width: painter.width,
        child: Text(widget.text, style: widget.style, maxLines: 1),
      );
    }
    const gap = 42.0;
    final span = painter.width + gap;
    return ClipRect(
      child: SizedBox(
        width: widget.maxWidth,
        height: painter.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(children: [
            Positioned(
              left: -span * _c.value,
              child: Text(widget.text, style: widget.style, maxLines: 1),
            ),
            Positioned(
              left: span - span * _c.value,
              child: Text(widget.text, style: widget.style, maxLines: 1),
            ),
          ]),
        ),
      ),
    );
  }
}
