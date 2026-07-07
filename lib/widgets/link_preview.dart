import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

final _urlReg = RegExp(r'(https?:\/\/[^\s]+)');

/// Returns the first http(s) URL found in [text], or null.
String? firstUrl(String text) => _urlReg.firstMatch(text)?.group(0);

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
    if (title.isEmpty && image.isEmpty) return const SizedBox.shrink();

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
              child: CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: c.surface),
                errorWidget: (_, __, ___) => Container(color: c.surface),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (site.isNotEmpty)
                  Text(site.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
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
