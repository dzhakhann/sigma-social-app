import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Instagram-style photo carousel for a post: swipeable PageView, dot
/// indicator, "1/N" badge top-right. Falls back to a single static image
/// when the post has only one photo (or the old single `image_url` shape).
class PostMediaCarousel extends StatefulWidget {
  final Map post;
  final double? height;
  final BorderRadius borderRadius;

  const PostMediaCarousel({
    super.key,
    required this.post,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  /// The post's photo list, oldest-shape-safe: prefers `media_urls` (array),
  /// falls back to the single `image_url`.
  static List<String> urlsOf(Map post) {
    final arr = post['media_urls'];
    if (arr is List && arr.isNotEmpty) {
      return arr.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final single = (post['image_url'] ?? '').toString();
    return single.isEmpty ? const [] : [single];
  }

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel> {
  final _pageCtrl = PageController();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final urls = PostMediaCarousel.urlsOf(widget.post);
    if (urls.isEmpty) return const SizedBox.shrink();

    Widget photo(String url) => CachedNetworkImage(
          imageUrl: url,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.black12,
            child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.black12,
            child: const Center(
                child: Icon(Icons.broken_image_outlined, size: 40)),
          ),
        );

    final body = urls.length == 1
        ? photo(urls.first)
        : Stack(children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => photo(urls[i]),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_index + 1}/${urls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: active ? 7 : 6,
                    height: active ? 7 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? Colors.white : Colors.white38,
                    ),
                  );
                }),
              ),
            ),
          ]);

    final clipped = ClipRRect(borderRadius: widget.borderRadius, child: body);
    return widget.height != null
        ? SizedBox(height: widget.height, width: double.infinity, child: clipped)
        : AspectRatio(aspectRatio: 1, child: clipped);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }
}
