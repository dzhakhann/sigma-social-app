import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/podcast_store.dart';
import '../services/podcast_audio.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
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
  String _active = 'pc_top';

  List<Map> _fav = [];
  List<Map> _hist = [];
  List<Map> _playlists = [];

  static const _cats = [
    'pc_top', 'pc_news', 'pc_business', 'pc_tech', 'pc_sport',
    'pc_health', 'pc_comedy', 'pc_education', 'pc_motivation',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadShows(context.t('pc_default_term'));
    });
  }

  Future<void> _loadShows(String term) async {
    setState(() => _loading = true);
    List<Map> data = [];
    try {
      data = await ApiService.searchPodcasts(term);
    } finally {
      if (mounted) setState(() { _shows = data; _loading = false; });
    }
  }

  Future<void> _loadLocal() async {
    final f = await PodcastStore.favorites();
    final h = await PodcastStore.history();
    final pl = await PodcastStore.playlists();
    if (mounted) setState(() { _fav = f; _hist = h; _playlists = pl; });
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
                    ? BooksTab(key: const PageStorageKey('books'))
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
      context.t('pPlaylist')
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

  Widget _bodyTab(BrutalColors c) {
    switch (_seg) {
      case 1:
        return _episodeList(c, _hist, Icons.history_rounded,
            context.t('pHistoryEmpty'));
      case 2:
        return _playlistsTab(c);
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
                  _loadShows(cat == 'pc_top'
                      ? context.t('pc_default_term')
                      : context.t(cat));
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
                    child: Text(context.t('pNothing'),
                        style: TextStyle(color: c.inkSoft)))
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
      trailing: Icon(
          video
              ? Icons.play_circle_outline_rounded
              : Icons.play_circle_fill_rounded,
          color: c.accent),
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
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ─── МУЗЫКА (Audius — legal free streaming, commercial use allowed) ──────────
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

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    final data = await ApiService.musicTrending();
    if (mounted) setState(() { _tracks = data; _loading = false; });
  }

  Future<void> _run(String q) async {
    if (q.trim().isEmpty) return _loadTrending();
    setState(() => _loading = true);
    final data = await ApiService.musicSearch(q.trim());
    if (mounted) setState(() { _tracks = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _search.text.trim().isEmpty ? context.t('trendingNow') : '',
            style: TextStyle(
                color: c.inkSoft, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _tracks.isEmpty
                ? Center(
                    child: Text(context.t('pNothing'),
                        style: TextStyle(color: c.inkSoft)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _tracks.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: c.ink.withOpacity(0.05)),
                    itemBuilder: (_, i) {
                      final t = _tracks[i];
                      final art = (t['artwork'] ?? '').toString();
                      return ListTile(
                        onTap: () => widget.openEpisode(_tracks, i),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: art.isEmpty
                              ? Container(
                                  width: 52, height: 52,
                                  color: c.surface2,
                                  child: Icon(Icons.music_note_rounded,
                                      color: c.inkSoft))
                              : CachedNetworkImage(
                                  imageUrl: art,
                                  width: 52, height: 52,
                                  fit: BoxFit.cover),
                        ),
                        title: Text((t['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5)),
                        subtitle: Text((t['showTitle'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 12)),
                        trailing: Icon(Icons.play_circle_fill_rounded,
                            color: c.accent, size: 30),
                      );
                    },
                  ),
      ),
    ]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ─── АУДИОКНИГИ (LibriVox — public domain) ───────────────────────────────────
class BooksTab extends StatefulWidget {
  const BooksTab({Key? key}) : super(key: key);
  @override
  State<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<BooksTab> {
  final _search = TextEditingController();
  List<Map> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final data = await ApiService.searchAudiobooks(q.trim());
    if (mounted) setState(() { _books = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
                    itemBuilder: (_, i) {
                      final b = _books[i];
                      final art = (b['artwork'] ?? '').toString();
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PodcastEpisodesScreen(show: b)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: art.isEmpty
                                    ? Container(
                                        width: double.infinity,
                                        color: c.surface2,
                                        child: Icon(
                                            Icons.menu_book_rounded,
                                            size: 44,
                                            color: c.inkSoft))
                                    : CachedNetworkImage(
                                        imageUrl: art,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) =>
                                            Container(color: c.surface2),
                                        errorWidget: (_, __, ___) =>
                                            Container(
                                                color: c.surface2,
                                                child: Icon(
                                                    Icons
                                                        .menu_book_rounded,
                                                    size: 44,
                                                    color: c.inkSoft)),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text((b['title'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                            Text((b['artist'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.inkSoft, fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
