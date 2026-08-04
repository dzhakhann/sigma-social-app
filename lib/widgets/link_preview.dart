import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

final _urlReg = RegExp(r'(https?:\/\/[^\s]+)');

/// Returns the first http(s) URL found in [text], or null.
String? firstUrl(String text) => _urlReg.firstMatch(text)?.group(0);

/// Brand colour + icon for a handful of platforms we can recognise even when
/// there's no scraped title/image (e.g. Instagram, which gates real content
/// behind a login wall for server-side requests).
(Color, IconData)? _brand(String site, String url) {
  final s = site.toLowerCase();
  final u = url.toLowerCase();
  if (s.contains('instagram') || u.contains('instagram.com')) {
    return (const Color(0xFFE1306C), Icons.camera_alt_rounded);
  }
  if (s.contains('youtube') || u.contains('youtu.be') || u.contains('youtube.com')) {
    return (const Color(0xFFFF0000), Icons.play_arrow_rounded);
  }
  if (s.contains('tiktok') || u.contains('tiktok.com')) {
    return (const Color(0xFF000000), Icons.music_note_rounded);
  }
  if (s.contains('twitter') || s == 'x.com' || u.contains('x.com') || u.contains('twitter.com')) {
    return (const Color(0xFF1DA1F2), Icons.alternate_email_rounded);
  }
  return null;
}

/// Telegram-style rich preview card for a link (Open Graph via backend).
class LinkPreviewCard extends StatefulWidget {
  final String url;
  const LinkPreviewCard({super.key, required this.url});
  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  Map _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await ApiService.linkPreview(widget.url);
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (_loading) return const SizedBox.shrink();
    final title = (_data['title'] ?? '').toString();
    final image = (_data['image'] ?? '').toString();
    final desc = (_data['description'] ?? '').toString();
    final site = (_data['siteName'] ?? '').toString();
    final brand = _brand(site, widget.url);
    // Recognised platform but nothing to show (Instagram's login wall) — a
    // clean branded card beats hiding the preview entirely.
    if (title.isEmpty && image.isEmpty) {
      if (brand == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration:
                BoxDecoration(color: brand.$1, shape: BoxShape.circle),
            child: Icon(brand.$2, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(site.isEmpty ? 'Link' : site,
                    style: TextStyle(
                        color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                Text(context.t('openInApp'),
                    style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded, color: c.inkSoft, size: 16),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.ink.withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.surface),
                  errorWidget: (_, __, ___) => Container(color: c.surface),
                ),
                // A little play badge makes a YouTube thumbnail instantly
                // recognisable as a video, not just a photo.
                if (brand != null && brand.$2 == Icons.play_arrow_rounded)
                  Center(
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (site.isNotEmpty)
                  Row(children: [
                    if (brand != null) ...[
                      Container(
                        width: 14, height: 14,
                        decoration:
                            BoxDecoration(color: brand.$1, shape: BoxShape.circle),
                        child: Icon(brand.$2, color: Colors.white, size: 9),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(site.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ),
                  ]),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.inkSoft, fontSize: 12.5, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
