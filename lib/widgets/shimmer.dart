import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

/// Dependency-free loading skeleton (a gentle pulse). Use in place of spinners
/// for a modern feel.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
    this.circle = false,
  });
  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.35 + 0.35 * _ctrl.value,
        child: Container(
          width: widget.circle ? widget.height : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: c.surface2,
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius:
                widget.circle ? null : BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// A few skeleton "posts" for the feed loading state.
class FeedSkeleton extends StatelessWidget {
  final int count;
  const FeedSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBox(height: 36, circle: true),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 120, height: 12),
                    SizedBox(height: 8),
                    ShimmerBox(height: 12),
                    SizedBox(height: 6),
                    ShimmerBox(width: 200, height: 12),
                    SizedBox(height: 10),
                    ShimmerBox(height: 150, radius: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
