import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/catalog_cache.dart';
import '../services/music_preview.dart';
import '../theme/brutal_theme.dart';

/// Unified Rhythm picker for a "favourite" or a post attachment: pick a
/// **track** (Audius), a **podcast episode** or an **audiobook chapter**.
/// Returns the chosen item Map ({audio,title,showTitle,artwork,duration,kind})
/// via Navigator.pop — the same shape the music picker returned, so callers
/// don't change.
class MediaPickerSheet extends StatefulWidget {
  const MediaPickerSheet({Key? key}) : super(key: key);

  @override
  State<MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<MediaPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  int _seg = 0; // 0 music · 1 podcasts · 2 audiobooks
  List<Map> _items = []; // tracks (music) or shows (podcast/book)
  bool _loading = true;

  // Drill-down: when a podcast/audiobook show is opened we list its episodes.
  Map? _openShow;
  List<Map> _episodes = [];
  bool _loadingEps = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    // Silence the "tap to listen before picking" preview — this sheet (unlike
    // the story music picker) never hands off to a screen that keeps playing
    // the same clip, so nothing else will ever stop it. Left playing before,
    // this would run forever: MusicPreview's player no longer loses Android
    // audio focus to anything since AndroidAudioFocus.none was set (fixing
    // the story "video freezes when music starts" bug), so there's no longer
    // an accidental interruption to rely on.
    MusicPreview.i.stop();
    super.dispose();
  }

  bool get _isMusic => _seg == 0;

  Future<void> _load(String q) async {
    // Default (empty-query) catalogs are cached on disk by the Rhythm screens
    // — show the cached copy instantly and refresh in the background.
    final seg = _seg;
    String? cacheKey;
    switch (seg) {
      case 1:
        final term = q.isEmpty ? context.t('pc_default_term') : q;
        cacheKey = q.isEmpty ? 'podcasts_$term' : null;
        break;
      case 2:
        final lang = AppScope.of(context).lang == 'ru' ? 'Russian' : 'English';
        cacheKey = q.isEmpty ? 'books__$lang' : null;
        break;
      default:
        cacheKey = q.isEmpty ? 'music_' : null;
    }
    final cached = cacheKey == null ? null : CatalogCache.get(cacheKey);
    if (cached != null) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    } else {
      setState(() => _loading = true);
    }

    List<Map> res;
    switch (seg) {
      case 1:
        res = await ApiService.searchPodcasts(
            q.isEmpty ? context.t('pc_default_term') : q);
        break;
      case 2:
        final lang = AppScope.of(context).lang == 'ru' ? 'Russian' : 'English';
        res = await ApiService.searchAudiobooks(q, language: lang);
        break;
      default:
        res = q.isEmpty
            ? await ApiService.musicTrending()
            : await ApiService.musicSearch(q);
    }
    if (cacheKey != null && res.isNotEmpty) CatalogCache.put(cacheKey, res);
    if (!mounted || _seg != seg) return;
    if (res.isEmpty && cached != null) return; // keep the cached copy
    setState(() {
      _items = res;
      _loading = false;
    });
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(q.trim()));
    setState(() {});
  }

  void _switchSeg(int i) {
    if (_seg == i) return;
    setState(() {
      _seg = i;
      _openShow = null;
      _episodes = [];
      _searchCtrl.clear();
    });
    _load('');
  }

  Future<void> _openShowEpisodes(Map show) async {
    setState(() {
      _openShow = show;
      _loadingEps = true;
      _episodes = [];
    });
    List<Map> raw = [];
    try {
      raw = await ApiService.fetchEpisodes((show['feedUrl'] ?? '').toString());
    } catch (_) {}
    final kind = _seg == 2 ? 'book' : 'podcast';
    final eps = raw
        .map((e) => {
              ...e,
              'showTitle': show['title'],
              'artist': show['artist'],
              'artwork': show['artwork'],
              'feedUrl': show['feedUrl'],
              'kind': kind,
            })
        .toList();
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _loadingEps = false;
    });
  }

  void _pick(Map item) {
    // Preview music instantly (like the story picker); episodes are long so we
    // just return them to the caller.
    if (_isMusic) {
      final url = (item['audio'] ?? '').toString();
      if (url.isNotEmpty) {
        MusicPreview.i.playUrl(url,
            title: (item['title'] ?? '').toString(),
            artist: (item['showTitle'] ?? '').toString());
      }
    }
    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final h = MediaQuery.of(context).size.height * 0.78;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF121316).withOpacity(0.9),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.10))),
          ),
          child: SafeArea(
            top: false,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              _segments(c),
              const SizedBox(height: 10),
              if (_openShow == null) _searchField(c),
              if (_openShow != null) _showHeader(c),
              const SizedBox(height: 6),
              Expanded(child: _body(c)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _segments(BrutalColors c) {
    final labels = [
      context.t('tabMusic'),
      context.t('tabPodcastsR'),
      context.t('tabBooks'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = _seg == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchSeg(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? c.accent : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(labels[i],
                      style: TextStyle(
                          color: sel ? c.onAccent : Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _searchField(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onQuery,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: _isMusic
              ? context.t('musicSearchHint')
              : _seg == 1
                  ? context.t('pSearch')
                  : context.t('booksSearch'),
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white54, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onQuery('');
                  },
                ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _showHeader(BrutalColors c) {
    final s = _openShow!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => setState(() {
            _openShow = null;
            _episodes = [];
          }),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: (s['artwork'] ?? '').toString().isEmpty
              ? Container(width: 38, height: 38, color: Colors.white12)
              : CachedNetworkImage(
                  imageUrl: s['artwork'], width: 38, height: 38,
                  fit: BoxFit.cover),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text((s['title'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _body(BrutalColors c) {
    if (_openShow != null) {
      if (_loadingEps) {
        return Center(child: CircularProgressIndicator(color: c.accent));
      }
      if (_episodes.isEmpty) {
        return _empty(context.t('pEpisodesNone'));
      }
      return ListView.builder(
        itemCount: _episodes.length,
        itemBuilder: (_, i) => _episodeTile(_episodes[i]),
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_items.isEmpty) {
      return _empty(context.t('musicNotFound'));
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) =>
          _isMusic ? _trackTile(_items[i]) : _showTile(_items[i]),
    );
  }

  Widget _empty(String text) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.music_off_rounded, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ]),
      );

  Widget _art(String url, IconData fallback) => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: url.isEmpty
            ? Container(
                width: 44,
                height: 44,
                color: Colors.white12,
                child: Icon(fallback, color: Colors.white54))
            : CachedNetworkImage(
                imageUrl: url, width: 44, height: 44, fit: BoxFit.cover),
      );

  Widget _trackTile(Map t) => ListTile(
        leading: _art((t['artwork'] ?? '').toString(), Icons.music_note_rounded),
        title: Text((t['title'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600)),
        subtitle: Text((t['showTitle'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        onTap: () => _pick(t),
      );

  Widget _showTile(Map s) => ListTile(
        leading: _art((s['artwork'] ?? '').toString(),
            _seg == 2 ? Icons.menu_book_rounded : Icons.podcasts_rounded),
        title: Text((s['title'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600)),
        subtitle: Text((s['artist'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () => _openShowEpisodes(s),
      );

  Widget _episodeTile(Map e) => ListTile(
        leading: Icon(Icons.play_circle_fill_rounded,
            color: context.k.accent, size: 32),
        title: Text((e['title'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: Text((e['duration'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        onTap: () => _pick(e),
      );
}
