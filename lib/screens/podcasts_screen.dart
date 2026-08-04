import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/catalog_cache.dart';
import '../services/podcast_store.dart';
import '../services/podcast_audio.dart';
import '../services/download_store.dart';
import '../services/sigma_link.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/download_button.dart';
import 'podcast_player_screen.dart';
import 'video_podcast_screen.dart';

/// Spotify-style colourful playlist cover derived from the playlist name, so
/// each playlist gets a consistent, pleasant gradient.
List<Color> _coverGradient(String seed) {
  int h = 0;
  for (final r in seed.runes) {
    h = (h * 31 + r) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  final c1 = HSVColor.fromAHSV(1, hue, 0.55, 0.9).toColor();
  final c2 = HSVColor.fromAHSV(1, (hue + 45) % 360, 0.65, 0.5).toColor();
  return [c1, c2];
}

/// "Подкасты" — free podcasts from around the world. Tabs: Обзор · История ·
/// Плейлист (which also holds the auto "Нравится" list). History / favourites /
/// playlists live only on the device (no backend storage).
class PodcastsScreen extends StatefulWidget {
  final Map user;
  const PodcastsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends State<PodcastsScreen> {
  int _seg = 0; // 0 Обзор, 1 История, 2 Плейлист

  final _search = TextEditingController();
  List<Map> _shows = [];
  bool _loading = false;
  bool _failed = false;
  String _lastTerm = '';
  String _active = 'pc_top';

  List<Map> _fav = [];
  List<Map> _hist = [];
  List<Map> _playlists = [];

  static const _cats = [
    'pc_top', 'pc_news', 'pc_business', 'pc_tech', 'pc_sport',
    'pc_health', 'pc_comedy', 'pc_education', 'pc_motivation',
  ];

  // Rotates which category "Top" opens to by default each week, instead of
  // the exact same literal "podcast"/"подкаст" search every time — iTunes'
  // /search endpoint has no offset/pagination to lean on instead.
  String _weeklyCat() {
    final pool = _cats.skip(1).toList(); // skip 'pc_top' itself
    final week = DateTime.now().difference(DateTime(2026)).inDays ~/ 7;
    return context.t(pool[week % pool.length]);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadShows(_weeklyCat());
    });
  }

  Future<void> _loadShows(String term) async {
    _lastTerm = term;
    // Cached copy first (instant open), then refresh from the network.
    final cached = CatalogCache.get('podcasts_$term');
    if (cached != null) {
      setState(() { _shows = cached; _loading = false; _failed = false; });
    } else {
      setState(() { _loading = true; _failed = false; });
    }
    List<Map> data = [];
    try {
      data = await ApiService.searchPodcasts(term);
      // The backend sleeps on Render's free tier, so the FIRST call after an
      // idle period can exceed the request timeout and come back empty. Retry
      // once — by then the server is awake — instead of showing the user a
      // "nothing found" that really meant "the server was still waking up".
      if (data.isEmpty) data = await ApiService.searchPodcasts(term);
    } finally {
      if (data.isNotEmpty) CatalogCache.put('podcasts_$term', data);
      if (mounted && (data.isNotEmpty || cached == null)) {
        setState(() {
          _shows = data;
          _loading = false;
          _failed = data.isEmpty;
        });
      }
    }
  }

  Future<void> _loadLocal() async {
    final f = await PodcastStore.favorites();
    final h = await PodcastStore.history();
    final pl = await PodcastStore.playlists();
    // Podcasts tab shows ONLY podcast history / favourites — music and
    // audiobooks each keep their own separate lists.
    if (mounted) {
      setState(() {
        _fav = f.where((e) => e['kind'] == 'podcast').toList();
        _hist = h.where((e) => e['kind'] == 'podcast').toList();
        _playlists = pl;
      });
    }
  }

  /// Play an episode: video → video screen; audio → global player + now-playing.
  void _openEpisode(List<Map> list, int i) {
    final ep = list[i];
    if (PodcastAudio.isVideo(ep)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPodcastScreen(episode: ep)),
      );
      return;
    }
    PodcastAudio.instance.playList(list, i);
    Navigator.push(context, PodcastPlayerScreen.route())
        .then((_) => _loadLocal());
  }

  // 0 Музыка · 1 Подкасты · 2 Аудиокниги ("Ритм" — the media hub)
  int _mediaTab = 1;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Icon(Icons.graphic_eq_rounded, color: c.accent, size: 26),
              const SizedBox(width: 8),
              Text(context.t('rhythm'),
                  style: TextStyle(
                      color: c.ink, fontSize: 24, fontWeight: FontWeight.w800)),
            ]),
          ),
          _mediaTabs(c),
          if (_mediaTab == 1) _segments(c),
          Expanded(
            child: _mediaTab == 0
                ? MusicTab(key: const PageStorageKey('music'), openEpisode: _openEpisode)
                : _mediaTab == 2
                    ? BooksTab(
                        key: const PageStorageKey('books'),
                        openEpisode: _openEpisode)
                    : _bodyTab(c),
          ),
        ]),
      ),
    );
  }

  Widget _mediaTabs(BrutalColors c) {
    final tabs = [
      [Icons.music_note_rounded, context.t('tabMusic')],
      [Icons.podcasts_rounded, context.t('tabPodcastsR')],
      [Icons.menu_book_rounded, context.t('tabBooks')],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final sel = _mediaTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mediaTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tabs[i][0] as IconData,
                          size: 16, color: sel ? c.onAccent : c.inkSoft),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(tabs[i][1] as String,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: sel ? c.onAccent : c.inkSoft,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
                      ),
                    ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _segments(BrutalColors c) {
    final labels = [
      context.t('pBrowse'),
      context.t('pHistory'),
      context.t('pPlaylist'),
      context.t('mDownloads'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = _seg == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _seg = i);
                if (i != 0) _loadLocal();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(labels[i],
                      maxLines: 1,
                      style: TextStyle(
                          color: sel ? c.onAccent : c.inkSoft,
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

  Widget _bodyTab(BrutalColors c) {
    switch (_seg) {
      case 1:
        return _episodeList(c, _hist, Icons.history_rounded,
            context.t('pHistoryEmpty'));
      case 2:
        return _playlistsTab(c);
      case 3:
        return ValueListenableBuilder<int>(
          valueListenable: DownloadStore.version,
          builder: (_, __, ___) => _episodeList(
              c,
              DownloadStore.all(kind: 'podcast'),
              Icons.download_done_rounded,
              context.t('emptyDownloads')),
        );
      default:
        return _browse(c);
    }
  }

  // ─── Обзор ─────────────────────────────────────────────────────────────────
  Widget _browse(BrutalColors c) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            setState(() => _active = '');
            _loadShows(v);
          },
          decoration: InputDecoration(
            hintText: context.t('pSearch'),
            prefixIcon: Icon(Icons.search_rounded, color: c.inkSoft),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: _cats.map((cat) {
            final sel = _active == cat;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _active = cat);
                  _search.clear();
                  _loadShows(cat == 'pc_top' ? _weeklyCat() : context.t(cat));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? c.accent : c.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.t(cat),
                      style: TextStyle(
                          color: sel ? c.onAccent : c.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _shows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _failed
                                ? Icons.cloud_off_rounded
                                : Icons.search_off_rounded,
                            color: c.inkSoft,
                            size: 44),
                        const SizedBox(height: 10),
                        Text(
                            _failed
                                ? context.t('loadFailedRetry')
                                : context.t('pNothing'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.inkSoft)),
                        if (_failed) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            style:
                                FilledButton.styleFrom(backgroundColor: c.accentFill),
                            onPressed: () => _loadShows(_lastTerm),
                            child: Text(context.t('retryBtn')),
                          ),
                        ],
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _shows.length,
                    itemBuilder: (_, i) => _showCard(c, _shows[i]),
                  ),
      ),
    ]);
  }

  Widget _showCard(BrutalColors c, Map s) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PodcastEpisodesScreen(show: s)),
      ).then((_) => _loadLocal()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (s['artwork'] as String).isEmpty
                    ? Container(color: c.surface2)
                    : CachedNetworkImage(
                        imageUrl: s['artwork'],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(s['title'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
          Text(s['artist'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkSoft, fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Shared episode list (history / playlist detail) ───────────────────────
  Widget _episodeList(
      BrutalColors c, List<Map> list, IconData emptyIcon, String emptyText) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(emptyIcon, size: 48, color: c.inkSoft),
              const SizedBox(height: 14),
              Text(emptyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, height: 1.4)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: c.ink.withOpacity(0.05)),
      itemBuilder: (_, i) => _episodeTile(c, list, i),
    );
  }

  Widget _episodeTile(BrutalColors c, List<Map> list, int i) {
    final ep = list[i];
    final art = (ep['artwork'] ?? '').toString();
    final video = PodcastAudio.isVideo(ep);
    return ListTile(
      onTap: () => _openEpisode(list, i),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: art.isEmpty
            ? Container(width: 48, height: 48, color: c.surface2)
            : CachedNetworkImage(
                imageUrl: art, width: 48, height: 48, fit: BoxFit.cover),
      ),
      title: Text((ep['title'] ?? context.t('episode')).toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text((ep['showTitle'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.inkSoft, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!video) ...[
          DownloadButton(track: ep, size: 20),
          const SizedBox(width: 12),
        ],
        Icon(
            video
                ? Icons.play_circle_outline_rounded
                : Icons.play_circle_fill_rounded,
            color: c.accent),
      ]),
    );
  }

  // ─── Плейлист (Нравится + named playlists) ─────────────────────────────────
  Widget _playlistsTab(BrutalColors c) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: GestureDetector(
          onTap: _createPlaylist,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                gradient: c.buttonGradient,
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, color: c.onAccent, size: 20),
              const SizedBox(width: 8),
              Text(context.t('pCreatePlaylist'),
                  style: TextStyle(
                      color: c.onAccent, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            // "Нравится" auto-playlist
            _playlistTile(
              c,
              icon: Icons.favorite_rounded,
              iconColor: c.danger,
              cover: _fav.isNotEmpty ? (_fav.first['artwork'] ?? '') : '',
              title: context.t('pLiked'),
              count: _fav.length,
              onTap: () => _openPlaylist(context.t('pLiked'), _fav),
            ),
            if (_playlists.isEmpty && _fav.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                    child: Text(context.t('pFirstPlaylist'),
                        style: TextStyle(color: c.inkSoft))),
              ),
            ..._playlists.map((p) {
              final eps =
                  (p['episodes'] as List).map((e) => Map.from(e)).toList();
              return _playlistTile(
                c,
                icon: Icons.queue_music_rounded,
                iconColor: c.inkSoft,
                cover: eps.isNotEmpty ? (eps.first['artwork'] ?? '') : '',
                title: (p['name'] ?? '').toString(),
                count: eps.length,
                onTap: () =>
                    _openPlaylist((p['name'] ?? '').toString(), eps.cast<Map>()),
                onLongPress: () =>
                    _deletePlaylist((p['name'] ?? '').toString()),
              );
            }),
          ],
        ),
      ),
    ]);
  }

  Widget _playlistTile(BrutalColors c,
      {required IconData icon,
      required Color iconColor,
      required Object cover,
      required String title,
      required int count,
      required VoidCallback onTap,
      VoidCallback? onLongPress}) {
    final coverUrl = cover.toString();
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: coverUrl.isEmpty
            ? Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _coverGradient(title),
                  ),
                ),
                child: Icon(icon, color: Colors.white))
            : CachedNetworkImage(
                imageUrl: coverUrl, width: 52, height: 52, fit: BoxFit.cover),
      ),
      title: Text(title,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
      subtitle: Text(context.t('episodesCount').replaceAll('{n}', '$count'),
          style: TextStyle(color: c.inkSoft, fontSize: 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: c.inkSoft),
    );
  }

  void _openPlaylist(String title, List<Map> episodes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlaylistDetailScreen(
          title: title,
          episodes: episodes,
          onPlay: _openEpisode,
        ),
      ),
    ).then((_) => _loadLocal());
  }

  Future<void> _createPlaylist() async {
    final c = context.k;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('newPlaylistTitle'), style: TextStyle(color: c.ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.ink),
          decoration: InputDecoration(hintText: context.t('playlistNameHint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(context.t('ok'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await PodcastStore.createPlaylist(name);
    await _loadLocal();
  }

  Future<void> _deletePlaylist(String name) async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('deletePlaylistQ').replaceAll('{name}', name), style: TextStyle(color: c.ink)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('deleteBtn'), style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok == true) {
      await PodcastStore.deletePlaylist(name);
      await _loadLocal();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ─── Playlist detail (episodes of one playlist) ──────────────────────────────
class _PlaylistDetailScreen extends StatelessWidget {
  final String title;
  final List<Map> episodes;
  final void Function(List<Map>, int) onPlay;
  const _PlaylistDetailScreen(
      {required this.title, required this.episodes, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: c.bg, title: Text(title)),
      body: episodes.isEmpty
          ? Center(
              child: Text(context.t('playlistEmptyHint'),
                  style: TextStyle(color: c.inkSoft)))
          : ListView.separated(
              itemCount: episodes.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: c.ink.withOpacity(0.05)),
              itemBuilder: (_, i) {
                final ep = episodes[i];
                final art = (ep['artwork'] ?? '').toString();
                return ListTile(
                  onTap: () => onPlay(episodes, i),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: art.isEmpty
                        ? Container(width: 48, height: 48, color: c.surface2)
                        : CachedNetworkImage(
                            imageUrl: art,
                            width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  title: Text((ep['title'] ?? context.t('episode')).toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text((ep['showTitle'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  trailing:
                      Icon(Icons.play_circle_fill_rounded, color: c.accent),
                );
              },
            ),
    );
  }
}

/// Episode list for one podcast show. Tapping an episode plays it (audio →
/// global player, video → video screen), with the whole list as the queue.
class PodcastEpisodesScreen extends StatefulWidget {
  final Map show;
  const PodcastEpisodesScreen({Key? key, required this.show}) : super(key: key);
  @override
  State<PodcastEpisodesScreen> createState() => _PodcastEpisodesScreenState();
}

class _PodcastEpisodesScreenState extends State<PodcastEpisodesScreen> {
  List<Map> _episodes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<Map> raw = [];
    try {
      raw = await ApiService.fetchEpisodes(widget.show['feedUrl']);
    } catch (_) {}
    final eps = raw
        .map((e) => {
              ...e,
              'showTitle': widget.show['title'],
              'artist': widget.show['artist'],
              'artwork': widget.show['artwork'],
              'feedUrl': widget.show['feedUrl'],
              // Inherit the show's media kind ('podcast' | 'book') so it lands in
              // the right History / Favourites section when played.
              'kind': widget.show['kind'] ?? 'podcast',
            })
        .toList();
    if (mounted) setState(() { _episodes = eps; _loading = false; });
  }

  void _play(int i) {
    final ep = _episodes[i];
    if (PodcastAudio.isVideo(ep)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPodcastScreen(episode: ep)),
      );
      return;
    }
    PodcastAudio.instance.playList(_episodes, i);
    Navigator.push(context, PodcastPlayerScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final s = widget.show;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title:
            Text(s['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (s['artwork'] as String).isEmpty
                  ? Container(width: 72, height: 72, color: c.surface2)
                  : CachedNetworkImage(
                      imageUrl: s['artwork'],
                      width: 72, height: 72, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s['title'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(s['artist'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 13)),
                ],
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: c.ink.withOpacity(0.07)),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: c.accent))
              : _episodes.isEmpty
                  ? Center(
                      child: Text(context.t('pEpisodesNone'),
                          style: TextStyle(color: c.inkSoft)))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: _episodes.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, color: c.ink.withOpacity(0.05)),
                      itemBuilder: (_, i) {
                        final ep = _episodes[i];
                        final video = PodcastAudio.isVideo(ep);
                        return ListTile(
                          onTap: () => _play(i),
                          leading: Icon(
                              video
                                  ? Icons.play_circle_outline_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: c.accent, size: 34),
                          title: Text(ep['title'] ?? context.t('episode'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              (ep['duration'] ?? '').toString().isNotEmpty
                                  ? '⏱ ${ep['duration']}'
                                  : (ep['date'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: c.inkSoft, fontSize: 12)),
                          trailing:
                              video ? null : DownloadButton(track: ep, size: 22),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ─── МУЗЫКА (Audius — legal free streaming, commercial use allowed) ──────────
// Structure: Главная (track of week, genres, trending) · История · Избранное ·
// Плейлисты. Likes/history/playlists are local-only (zero backend load).
class MusicTab extends StatefulWidget {
  final void Function(List<Map>, int) openEpisode;
  const MusicTab({Key? key, required this.openEpisode}) : super(key: key);
  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> {
  final _search = TextEditingController();
  List<Map> _tracks = [];
  bool _loading = true;
  int _sub = 0; // 0 home · 1 history · 2 liked · 3 playlists
  String _genre = _weeklyGenre();
  List<String> _recentQueries = [];
  Set<String> _favIds = {};
  List<Map> _hist = [];
  List<Map> _favs = [];
  List<Map> _playlists = [];

  static const _genres = [
    ['', 'gAll'], ['Pop', 'gPop'], ['Hip-Hop/Rap', 'gHipHop'],
    ['Electronic', 'gElectronic'], ['Rock', 'gRock'], ['Jazz', 'gJazz'],
    ['Classical', 'gClassical'], ['R&B/Soul', 'gRnb'], ['Latin', 'gLatin'],
    ['Ambient', 'gAmbient'], ['Folk', 'gFolk'],
  ];

  // Rotates which genre the trending list opens to by default each week,
  // instead of always the exact same unfiltered global chart (Audius'
  // /tracks/trending has no seed/offset of its own) — same week-seed
  // formula as _weekPick below, so both rotate together.
  static String _weeklyGenre() {
    final week = DateTime.now().difference(DateTime(2026)).inDays ~/ 7;
    return _genres[1 + week % (_genres.length - 1)][0];
  }

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _loadLocal();
    _loadQueries();
  }

  Future<void> _loadQueries() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() =>
          _recentQueries = p.getStringList('music_queries') ?? []);
    }
  }

  Future<void> _saveQuery(String q) async {
    if (q.trim().isEmpty) return;
    final p = await SharedPreferences.getInstance();
    _recentQueries.remove(q);
    _recentQueries.insert(0, q);
    if (_recentQueries.length > 8) {
      _recentQueries = _recentQueries.take(8).toList();
    }
    await p.setStringList('music_queries', _recentQueries);
  }

  Future<void> _loadLocal() async {
    final f = await PodcastStore.favorites();
    final h = await PodcastStore.history();
    final pl = await PodcastStore.playlists();
    if (mounted) {
      setState(() {
        _favs = f.where((e) => e['kind'] == 'music').toList();
        _hist = h.where((e) => e['kind'] == 'music').toList();
        _playlists = pl;
        _favIds = f.map((e) => e['audio'].toString()).toSet();
      });
    }
  }

  Future<void> _loadTrending() async {
    // Cached copy first (instant open), then refresh from the network.
    final cached = CatalogCache.get('music_$_genre');
    if (cached != null) {
      setState(() { _tracks = cached; _loading = false; });
    } else {
      setState(() => _loading = true);
    }
    final data = await ApiService.musicTrending(genre: _genre);
    if (data.isNotEmpty) CatalogCache.put('music_$_genre', data);
    if (mounted && (data.isNotEmpty || cached == null)) {
      setState(() { _tracks = data; _loading = false; });
    }
  }

  Future<void> _run(String q) async {
    if (q.trim().isEmpty) return _loadTrending();
    _saveQuery(q.trim());
    setState(() => _loading = true);
    final data = await ApiService.musicSearch(q.trim());
    if (mounted) setState(() { _tracks = data; _loading = false; });
  }

  Future<void> _toggleFav(Map t) async {
    HapticFeedback.selectionClick();
    await PodcastStore.toggleFavorite(t);
    _loadLocal();
  }

  // ⋮ track actions: like · add to playlist · share
  void _trackMenu(Map t) {
    final c = context.k;
    final fav = _favIds.contains(t['audio'].toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: Icon(
                fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: c.danger),
            title: Text(fav ? ctx.t('removeFromFav') : ctx.t('addToFav')),
            onTap: () {
              Navigator.pop(ctx);
              _toggleFav(t);
            },
          ),
          ListTile(
            leading: Icon(Icons.playlist_add_rounded, color: c.ink),
            title: Text(ctx.t('addToPlaylist')),
            onTap: () async {
              Navigator.pop(ctx);
              await _addToPlaylistSheet(t);
            },
          ),
          Builder(builder: (_) {
            final dl = DownloadStore.isDownloaded(t['audio']?.toString());
            return ListTile(
              leading: Icon(
                  dl ? Icons.download_done_rounded : Icons.download_rounded,
                  color: dl ? c.accent : c.ink),
              title: Text(dl ? ctx.t('downloadRemove') : ctx.t('download')),
              onTap: () async {
                Navigator.pop(ctx);
                if (dl) {
                  await DownloadStore.remove(t['audio']?.toString());
                } else {
                  final ok = await DownloadStore.download(t);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.t('downloadFailed'))));
                  }
                }
              },
            );
          }),
          ListTile(
            leading: Icon(Icons.share_rounded, color: c.ink),
            title: Text(ctx.t('shareBtn')),
            onTap: () async {
              Navigator.pop(ctx);
              final musicId = t['id']?.toString() ?? '';
              String link;
              if (t['kind'] == 'music' && musicId.isNotEmpty) {
                link = SigmaLink(SigmaLinkKind.music, musicId).url;
              } else if (t['kind'] == 'podcast') {
                // Mints (or reuses) a stable id for this episode server-side —
                // there's no id to link to until this round-trip happens.
                final id = await ApiService.sharePodcastEpisode(t);
                link = id != null
                    ? SigmaLink(SigmaLinkKind.podcast, id).url
                    : t['audio'].toString();
              } else {
                // Audiobook chapters aren't resolvable by id yet.
                link = t['audio'].toString();
              }
              Share.share('${t['title']} — ${t['showTitle']}\n$link');
            },
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Future<void> _addToPlaylistSheet(Map t) async {
    final c = context.k;
    final pls = await PodcastStore.playlists();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.add_rounded, color: c.accent),
            title: Text(ctx.t('createNewPlaylist'),
                style: TextStyle(color: c.accent)),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await _newPlaylistDialog();
              if (name != null && name.isNotEmpty) {
                await PodcastStore.createPlaylist(name);
                await PodcastStore.addToPlaylist(name, t);
                _loadLocal();
              }
            },
          ),
          ...pls.map((p) => ListTile(
                leading: Icon(Icons.queue_music_rounded, color: c.ink),
                title: Text((p['name'] ?? '').toString()),
                onTap: () async {
                  await PodcastStore.addToPlaylist(
                      (p['name'] ?? '').toString(), t);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadLocal();
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<String?> _newPlaylistDialog() {
    final c = context.k;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(ctx.t('newPlaylistTitle')),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration:
                InputDecoration(hintText: ctx.t('playlistNameHint'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ctx.t('ok'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      _subTabs(c),
      Expanded(child: _body(c)),
    ]);
  }

  Widget _subTabs(BrutalColors c) {
    final labels = [
      context.t('mHome'), context.t('mHistory'),
      context.t('mFav'), context.t('mPlaylists'), context.t('mDownloads'),
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: List.generate(labels.length, (i) {
          final sel = _sub == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _sub = i);
                if (i != 0) _loadLocal();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        color: sel ? c.onAccent : c.inkSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _body(BrutalColors c) {
    switch (_sub) {
      case 1:
        return _trackList(c, _hist, context.t('emptyHistory'));
      case 2:
        return _trackList(c, _favs, context.t('emptyFav'));
      case 3:
        return _playlistsList(c);
      case 4:
        return ValueListenableBuilder<int>(
          valueListenable: DownloadStore.version,
          builder: (_, __, ___) => _trackList(
              c, DownloadStore.all(kind: 'music'), context.t('emptyDownloads')),
        );
      default:
        return _home(c);
    }
  }

  Widget _home(BrutalColors c) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          decoration: InputDecoration(
            hintText: context.t('musicSearch'),
            prefixIcon: Icon(Icons.search_rounded, color: c.inkSoft),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            isDense: true,
          ),
        ),
      ),
      // Recent searches
      if (_recentQueries.isNotEmpty && _search.text.trim().isEmpty)
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: _recentQueries
                .map((q) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(q,
                            style: TextStyle(
                                fontSize: 12, color: c.inkSoft)),
                        backgroundColor: c.surface,
                        onPressed: () {
                          _search.text = q;
                          _run(q);
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
      // Genre chips
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: _genres.map((g) {
            final sel = _genre == g[0];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () {
                  setState(() => _genre = g[0]);
                  _search.clear();
                  _loadTrending();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? c.accent : c.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(context.t(g[1]),
                      style: TextStyle(
                          color: sel ? c.onAccent : c.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _tracks.isEmpty
                ? Center(
                    child: Text(context.t('pNothing'),
                        style: TextStyle(color: c.inkSoft)))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      if (_search.text.trim().isEmpty &&
                          _genre.isEmpty &&
                          _tracks.isNotEmpty)
                        _weekPick(c),
                      ..._tracks.asMap().entries.map(
                          (e) => _trackRow(c, _tracks, e.key)),
                    ],
                  ),
      ),
    ]);
  }

  // "Track of the week" — deterministic weekly pick from trending.
  Widget _weekPick(BrutalColors c) {
    final week = DateTime.now().difference(DateTime(2026)).inDays ~/ 7;
    final t = _tracks[week % _tracks.length];
    final art = (t['artwork'] ?? '').toString();
    return GestureDetector(
      onTap: () => widget.openEpisode(_tracks, _tracks.indexOf(t)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            c.accent.withOpacity(0.25),
            c.accent3.withOpacity(0.15),
          ]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.accent.withOpacity(0.3)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: art.isEmpty
                ? Container(
                    width: 64, height: 64,
                    color: c.surface2,
                    child: Icon(Icons.music_note_rounded, color: c.inkSoft))
                : CachedNetworkImage(
                    imageUrl: art, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⭐ ${context.t('trackOfWeek')}',
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text((t['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  Text((t['showTitle'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ]),
          ),
          Icon(Icons.play_circle_fill_rounded, color: c.accent, size: 38),
        ]),
      ),
    );
  }

  Widget _trackList(BrutalColors c, List<Map> list, String emptyText) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, height: 1.4)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children:
          list.asMap().entries.map((e) => _trackRow(c, list, e.key)).toList(),
    );
  }

  Widget _trackRow(BrutalColors c, List<Map> list, int i) {
    final t = list[i];
    final art = (t['artwork'] ?? '').toString();
    final fav = _favIds.contains(t['audio'].toString());
    return ListTile(
      onTap: () => widget.openEpisode(list, i),
      onLongPress: () => _trackMenu(t),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: art.isEmpty
            ? Container(
                width: 52, height: 52,
                color: c.surface2,
                child: Icon(Icons.music_note_rounded, color: c.inkSoft))
            : CachedNetworkImage(
                imageUrl: art, width: 52, height: 52, fit: BoxFit.cover),
      ),
      title: Text((t['title'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: c.ink, fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text((t['showTitle'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.inkSoft, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => _toggleFav(t),
          child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: fav ? c.danger : c.inkSoft,
              size: 22),
        ),
        const SizedBox(width: 12),
        DownloadButton(track: t, size: 20),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _trackMenu(t),
          child: Icon(Icons.more_vert_rounded, color: c.inkSoft, size: 20),
        ),
      ]),
    );
  }

  Widget _playlistsList(BrutalColors c) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: c.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.add_rounded, color: c.accent),
          ),
          title: Text(context.t('pCreatePlaylist'),
              style:
                  TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
          onTap: () async {
            final name = await _newPlaylistDialog();
            if (name != null && name.isNotEmpty) {
              await PodcastStore.createPlaylist(name);
              _loadLocal();
            }
          },
        ),
        ..._playlists.map((p) {
          final eps =
              (p['episodes'] as List).map((e) => Map.from(e)).toList();
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors:
                          _coverGradient((p['name'] ?? '').toString())),
                ),
                child: const Icon(Icons.queue_music_rounded,
                    color: Colors.white),
              ),
            ),
            title: Text((p['name'] ?? '').toString(),
                style:
                    TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
            subtitle: Text(
                context
                    .t('episodesCount')
                    .replaceAll('{n}', '${eps.length}'),
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PlaylistDetailScreen(
                  title: (p['name'] ?? '').toString(),
                  episodes: eps.cast<Map>(),
                  onPlay: widget.openEpisode,
                ),
              ),
            ).then((_) => _loadLocal()),
            onLongPress: () async {
              await PodcastStore.deletePlaylist(
                  (p['name'] ?? '').toString());
              _loadLocal();
            },
          );
        }),
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ─── АУДИОКНИГИ (LibriVox — public domain, EN + RU catalogs) ─────────────────
class BooksTab extends StatefulWidget {
  final void Function(List<Map>, int) openEpisode;
  const BooksTab({Key? key, required this.openEpisode}) : super(key: key);
  @override
  State<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<BooksTab> {
  final _search = TextEditingController();
  List<Map> _books = [];
  bool _loading = true;
  String _genre = _weeklyGenre();
  String _language = 'English';

  int _sub = 0; // 0 catalog · 1 history · 2 liked · 3 downloaded
  List<Map> _hist = [];
  List<Map> _favs = [];
  Set<String> _favIds = {};
  bool _retriedCold = false;

  static const _genresList = [
    ['', 'bAll'], ['General Fiction', 'bFiction'], ['Classics', 'bClassics'],
    ['Detective Fiction', 'bMystery'], ['Fantastic Fiction', 'bFantasy'],
    ['Biography & Autobiography', 'bBio'], ['Science', 'bScience'],
    ['Philosophy', 'bPhilosophy'], ['Poetry', 'bPoetry'],
    ['History', 'bHistory'], ["Children's Fiction", 'bChildren'],
  ];

  // Same reasoning as MusicTab: archive.org's default (no-term) sort is
  // deterministic "most downloaded", so the catalog opens to a rotating
  // genre each week instead of the exact same top-40 every time.
  static String _weeklyGenre() {
    final week = DateTime.now().difference(DateTime(2026)).inDays ~/ 7;
    return _genresList[1 + week % (_genresList.length - 1)][0];
  }

  @override
  void initState() {
    super.initState();
    _loadLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Default catalog language follows the app language.
        _language =
            AppScope.of(context).lang == 'ru' ? 'Russian' : 'English';
        _run('');
      }
    });
  }

  Future<void> _run(String q) async {
    // The default catalog (empty query) is cached on disk — instant open.
    final key = q.trim().isEmpty ? 'books_${_genre}_$_language' : null;
    final cached = key == null ? null : CatalogCache.get(key);
    if (cached != null) {
      setState(() { _books = cached; _loading = false; });
    } else {
      setState(() => _loading = true);
    }
    var data = await ApiService.searchAudiobooks(q.trim(),
        genre: _genre, language: _language);
    // Cold-start safety: the free-tier backend may still be waking on the very
    // first open — give it one more try before showing an empty catalog.
    if (data.isEmpty && !_retriedCold) {
      _retriedCold = true;
      await Future.delayed(const Duration(seconds: 2));
      data = await ApiService.searchAudiobooks(q.trim(),
          genre: _genre, language: _language);
    }
    if (key != null && data.isNotEmpty) CatalogCache.put(key, data);
    if (mounted && (data.isNotEmpty || cached == null)) {
      setState(() { _books = data; _loading = false; });
    }
  }

  // Audiobooks keep their OWN history / favourites, separate from music and
  // podcasts — filtered by kind == 'book'.
  Future<void> _loadLocal() async {
    final f = await PodcastStore.favorites();
    final h = await PodcastStore.history();
    if (mounted) {
      setState(() {
        _favs = f.where((e) => e['kind'] == 'book').toList();
        _hist = h.where((e) => e['kind'] == 'book').toList();
        _favIds = f.map((e) => e['audio'].toString()).toSet();
      });
    }
  }

  Future<void> _toggleFav(Map ep) async {
    HapticFeedback.selectionClick();
    await PodcastStore.toggleFavorite(ep);
    _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      _subTabs(c),
      Expanded(child: _body(c)),
    ]);
  }

  Widget _subTabs(BrutalColors c) {
    final labels = [
      context.t('bCatalog'), context.t('bHistoryTab'), context.t('bFavTab'),
      context.t('mDownloads'),
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: List.generate(labels.length, (i) {
          final sel = _sub == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _sub = i);
                if (i != 0) _loadLocal();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        color: sel ? c.onAccent : c.inkSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _body(BrutalColors c) {
    switch (_sub) {
      case 1:
        return _chapterList(c, _hist, context.t('emptyBookHistory'));
      case 2:
        return _chapterList(c, _favs, context.t('emptyBookFav'));
      case 3:
        return ValueListenableBuilder<int>(
          valueListenable: DownloadStore.version,
          builder: (_, __, ___) => _chapterList(
              c, DownloadStore.all(kind: 'book'), context.t('emptyDownloads')),
        );
      default:
        return _catalog(c);
    }
  }

  // ─── A saved audiobook chapter row (History / Liked) ───────────────────────
  Widget _chapterList(BrutalColors c, List<Map> list, String emptyText) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, height: 1.4)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: c.ink.withOpacity(0.05)),
      itemBuilder: (_, i) {
        final ep = list[i];
        final art = (ep['artwork'] ?? '').toString();
        final fav = _favIds.contains(ep['audio'].toString());
        final video = PodcastAudio.isVideo(ep);
        return ListTile(
          onTap: () => widget.openEpisode(list, i),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: art.isEmpty
                ? Container(
                    width: 48, height: 48,
                    color: c.surface2,
                    child: Icon(Icons.menu_book_rounded, color: c.inkSoft))
                : CachedNetworkImage(
                    imageUrl: art, width: 48, height: 48, fit: BoxFit.cover),
          ),
          title: Text((ep['title'] ?? context.t('episode')).toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.ink, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text((ep['showTitle'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkSoft, fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => _toggleFav(ep),
              child: Icon(
                  fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: fav ? c.danger : c.inkSoft,
                  size: 22),
            ),
            if (!video) ...[
              const SizedBox(width: 12),
              DownloadButton(track: ep, size: 20),
            ],
          ]),
        );
      },
    );
  }

  Widget _catalog(BrutalColors c) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: _run,
              decoration: InputDecoration(
                hintText: context.t('booksSearch'),
                prefixIcon: Icon(Icons.search_rounded, color: c.inkSoft),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Catalog language toggle (architecture allows adding more later).
          GestureDetector(
            onTap: () {
              setState(() => _language =
                  _language == 'English' ? 'Russian' : 'English');
              _run(_search.text);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.accent.withOpacity(0.4)),
              ),
              child: Text(_language == 'English' ? '🇺🇸 EN' : '🇷🇺 RU',
                  style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ),
          ),
        ]),
      ),
      SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: _genresList.map((g) {
            final sel = _genre == g[0];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () {
                  setState(() => _genre = g[0]);
                  _run(_search.text);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? c.accent : c.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(context.t(g[1]),
                      style: TextStyle(
                          color: sel ? c.onAccent : c.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _books.isEmpty
                ? Center(
                    child: Text(context.t('pNothing'),
                        style: TextStyle(color: c.inkSoft)))
                : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _books.length,
                    itemBuilder: (_, i) => _bookCard(c, _books[i]),
                  ),
      ),
    ]);
  }

  Widget _bookCard(BrutalColors c, Map b) {
    final art = (b['artwork'] ?? '').toString();
    final title = (b['title'] ?? '').toString();
    // Pretty gradient cover with the book title when LibriVox has no artwork.
    Widget fallbackCover() => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _coverGradient(title),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 34, color: Colors.white70),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.25)),
            ],
          ),
        );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PodcastEpisodesScreen(show: b)),
      ).then((_) => _loadLocal()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: art.isEmpty
                  ? fallbackCover()
                  : CachedNetworkImage(
                      imageUrl: art,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: c.surface2),
                      errorWidget: (_, __, ___) => fallbackCover(),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
          Text((b['artist'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkSoft, fontSize: 11)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
