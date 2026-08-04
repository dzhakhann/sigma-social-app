import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'emoji_picker.dart';

/// Emoji | GIF tabbed panel that replaces the keyboard — shared by 1:1 and
/// group chat so both have the same input extras (group chat used to have a
/// plain emoji-only panel with no GIF tab).
class ExtrasPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final VoidCallback onBackspace;
  final ValueChanged<String> onGif;
  const ExtrasPanel({
    super.key,
    required this.onEmoji,
    required this.onBackspace,
    required this.onGif,
  });

  @override
  State<ExtrasPanel> createState() => _ExtrasPanelState();
}

class _ExtrasPanelState extends State<ExtrasPanel> {
  int _tab = 0; // 0 emoji · 1 gif
  // NOTE: Giphy's sticker search returned near-identical results to its GIF
  // search for most queries (indistinguishable to the user) — dropped the
  // tab rather than ship a confusing duplicate.

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      height: 316,
      color: c.surface,
      child: Column(children: [
        SizedBox(
          height: 40,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _seg(c, 0, Icons.emoji_emotions_outlined, 'Emoji'),
            _seg(c, 1, Icons.gif_box_outlined, 'GIF'),
          ]),
        ),
        Divider(height: 1, color: c.ink.withOpacity(0.06)),
        Expanded(
          child: switch (_tab) {
            1 => GiphyGrid(stickers: false, onPick: widget.onGif),
            _ => EmojiPanel(
                onEmoji: widget.onEmoji,
                onBackspace: widget.onBackspace,
                height: 275),
          },
        ),
      ]),
    );
  }

  Widget _seg(BrutalColors c, int i, IconData icon, String label) {
    final sel = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? c.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: sel ? c.accent : c.inkSoft),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: sel ? c.accent : c.inkSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class GiphyGrid extends StatefulWidget {
  final bool stickers;
  final ValueChanged<String> onPick;
  const GiphyGrid({super.key, required this.stickers, required this.onPick});

  @override
  State<GiphyGrid> createState() => _GiphyGridState();
}

class _GiphyGridState extends State<GiphyGrid> {
  // Trending lists survive tab switches — no refetch each time.
  static final Map<bool, List> _trendingCache = {};

  final _ctrl = TextEditingController();
  Timer? _debounce;
  List _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = _trendingCache[widget.stickers];
    if (cached != null && cached.isNotEmpty) {
      _items = cached;
      _loading = false;
    }
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (_items.isEmpty) setState(() => _loading = true);
    final data = await ApiService.searchGifs(q, stickers: widget.stickers);
    if (!mounted) return;
    if (q.isEmpty && data.isNotEmpty) _trendingCache[widget.stickers] = data;
    setState(() {
      if (data.isNotEmpty || q.isNotEmpty) _items = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: SizedBox(
          height: 38,
          child: TextField(
            controller: _ctrl,
            onChanged: (q) {
              _debounce?.cancel();
              _debounce = Timer(
                  const Duration(milliseconds: 350), () => _search(q.trim()));
            },
            style: TextStyle(color: c.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.stickers ? context.t('stickersSearch') : 'GIF…',
              hintStyle: TextStyle(color: c.inkSoft, fontSize: 14),
              prefixIcon:
                  Icon(Icons.search_rounded, color: c.inkSoft, size: 19),
              filled: true,
              fillColor: c.surface2,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? Center(
                child:
                    CircularProgressIndicator(color: c.accent, strokeWidth: 2))
            : _items.isEmpty
                ? Center(
                    child: Text(context.t('musicNotFound'),
                        style: TextStyle(color: c.inkSoft, fontSize: 13)))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final g = _items[i];
                      final preview =
                          (g['preview'] ?? g['full'] ?? '').toString();
                      final full = (g['full'] ?? '').toString();
                      return GestureDetector(
                        onTap: full.isEmpty ? null : () => widget.onPick(full),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: preview,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: c.surface2),
                            errorWidget: (_, __, ___) =>
                                Container(color: c.surface2),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
