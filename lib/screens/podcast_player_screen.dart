import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/podcast_store.dart';
import '../services/podcast_audio.dart';

/// Full-screen "now playing", bound to the app-wide [PodcastAudio] player.
/// Collapsing (down arrow) just pops this screen — audio keeps playing and the
/// mini-player stays at the bottom.
class PodcastPlayerScreen extends StatefulWidget {
  const PodcastPlayerScreen({Key? key}) : super(key: key);

  /// Spotify/Apple-style: the now-playing screen slides up from the bottom.
  static Route<void> route() => PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const PodcastPlayerScreen(),
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      );

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  final _audio = PodcastAudio.instance;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _audio.current.addListener(_onEp);
    _refreshFav();
  }

  void _onEp() {
    _refreshFav();
    if (mounted) setState(() {});
  }

  Future<void> _refreshFav() async {
    final ep = _audio.current.value;
    if (ep == null) return;
    final f = await PodcastStore.isFavorite(ep['audio'].toString());
    if (mounted) setState(() => _fav = f);
  }

  Future<void> _toggleFav() async {
    final ep = _audio.current.value;
    if (ep == null) return;
    final now = await PodcastStore.toggleFavorite(ep);
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _fav = now);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final ep = _audio.current.value;
    if (ep == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
            child: Text(context.t('nothingPlaying'),
                style: TextStyle(color: c.inkSoft))),
      );
    }
    final art = (ep['artwork'] ?? '').toString();
    final player = _audio.player;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text((ep['showTitle'] ?? context.t('podcastFallback')).toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: Icon(
                _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _fav ? c.danger : c.ink),
            onPressed: _toggleFav,
          ),
          IconButton(
            icon: Icon(Icons.playlist_add_rounded, color: c.ink),
            onPressed: _addToPlaylist,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: art.isEmpty
                  ? Container(
                      width: 280, height: 280, color: c.surface2,
                      child: Icon(Icons.podcasts_rounded,
                          size: 80, color: c.inkSoft))
                  : CachedNetworkImage(
                      imageUrl: art, width: 280, height: 280, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          width: 280, height: 280, color: c.surface2),
                      errorWidget: (_, __, ___) => Container(
                          width: 280, height: 280, color: c.surface2)),
            ),
            const SizedBox(height: 28),
            Text((ep['title'] ?? context.t('episode')).toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text((ep['artist'] ?? ep['showTitle'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.inkSoft, fontSize: 14)),
            const Spacer(),
            // Progress bar (position + duration streams)
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = player.duration ?? Duration.zero;
                final total = dur.inMilliseconds > 0
                    ? dur.inMilliseconds.toDouble()
                    : 1.0;
                final value =
                    pos.inMilliseconds.clamp(0, total.toInt()).toDouble();
                return Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: c.accent,
                      inactiveTrackColor: c.ink.withOpacity(0.12),
                      thumbColor: c.accent,
                    ),
                    child: Slider(
                      min: 0,
                      max: total,
                      value: value,
                      onChanged: (v) =>
                          player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos),
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 12)),
                        Text(_fmt(dur),
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 12)),
                      ],
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 12),
            _controls(c, player),
            const SizedBox(height: 6),
            _extraControls(c),
            const Spacer(),
          ]),
        ),
      ),
    );
  }

  Widget _controls(BrutalColors c, AudioPlayer player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous_rounded, color: c.ink),
          iconSize: 34,
          onPressed: _audio.prev,
        ),
        IconButton(
          icon: Icon(Icons.replay_10_rounded, color: c.ink),
          iconSize: 32,
          onPressed: () => player
              .seek(player.position - const Duration(seconds: 10)),
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (_, snap) {
            final st = snap.data;
            final playing = st?.playing ?? false;
            final loading = st?.processingState == ProcessingState.loading ||
                st?.processingState == ProcessingState.buffering;
            return GestureDetector(
              onTap: _audio.toggle,
              child: Container(
                width: 72, height: 72,
                decoration:
                    BoxDecoration(color: c.accent, shape: BoxShape.circle),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(22),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: c.onAccent))
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: c.onAccent, size: 40),
              ),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.forward_30_rounded, color: c.ink),
          iconSize: 32,
          onPressed: () =>
              player.seek(player.position + const Duration(seconds: 30)),
        ),
        IconButton(
          icon: Icon(Icons.skip_next_rounded,
              color: _audio.hasNext ? c.ink : c.inkSoft.withOpacity(0.4)),
          iconSize: 30,
          onPressed: _audio.hasNext ? _audio.next : null,
        ),
      ],
    );
  }

  // Second row: shuffle · speed · sleep timer · repeat (Spotify-style).
  Widget _extraControls(BrutalColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _audio.shuffleOn,
          builder: (_, on, __) => IconButton(
            icon: Icon(Icons.shuffle_rounded,
                color: on ? c.accent : c.inkSoft, size: 22),
            onPressed: _audio.toggleShuffle,
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _audio.speed,
          builder: (_, s, __) => GestureDetector(
            onTap: _pickSpeed,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: s != 1.0 ? c.accent.withOpacity(0.15) : c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: s != 1.0
                        ? c.accent
                        : c.ink.withOpacity(0.1)),
              ),
              child: Text('${s}x',
                  style: TextStyle(
                      color: s != 1.0 ? c.accent : c.inkSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _audio.sleepMinutes,
          builder: (_, m, __) => IconButton(
            icon: Icon(
                m > 0
                    ? Icons.bedtime_rounded
                    : Icons.bedtime_outlined,
                color: m > 0 ? c.accent : c.inkSoft,
                size: 22),
            onPressed: _pickSleepTimer,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _audio.repeatOn,
          builder: (_, on, __) => IconButton(
            icon: Icon(Icons.repeat_rounded,
                color: on ? c.accent : c.inkSoft, size: 22),
            onPressed: _audio.toggleRepeat,
          ),
        ),
      ],
    );
  }

  void _pickSpeed() {
    final c = context.k;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Text(ctx.t('speedTitle'),
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0].map((s) {
              final sel = _audio.speed.value == s;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ChoiceChip(
                  label: Text('${s}x'),
                  selected: sel,
                  selectedColor: c.accent.withOpacity(0.2),
                  onSelected: (_) {
                    _audio.setSpeed(s);
                    Navigator.pop(ctx);
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _pickSleepTimer() {
    final c = context.k;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Text(ctx.t('sleepTimer'),
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          ...[0, 15, 30, 60].map((m) => ListTile(
                dense: true,
                leading: Icon(
                    m == 0
                        ? Icons.close_rounded
                        : Icons.bedtime_outlined,
                    color: c.inkSoft,
                    size: 20),
                title: Text(
                    m == 0
                        ? ctx.t('timerOff')
                        : ctx.t('inMinutes').replaceAll('{n}', '$m'),
                    style: TextStyle(color: c.ink)),
                trailing: _audio.sleepMinutes.value == m && m > 0
                    ? Icon(Icons.check_rounded, color: c.accent, size: 20)
                    : null,
                onTap: () {
                  _audio.setSleepTimer(m);
                  Navigator.pop(ctx);
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _addToPlaylist() async {
    final c = context.k;
    final ep = _audio.current.value;
    if (ep == null) return;
    final playlists = await PodcastStore.playlists();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.t('addToPlaylist'),
                  style: TextStyle(
                      color: c.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: c.accent),
            title: Text(context.t('createNewPlaylist'),
                style:
                    TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
            onTap: () async {
              Navigator.pop(context);
              await _createAndAdd(ep);
            },
          ),
          ...playlists.map((p) => ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: c.ink),
                title: Text((p['name'] ?? '').toString(),
                    style: TextStyle(color: c.ink)),
                subtitle: Text(context.t('episodesSuffix').replaceAll('{n}', '${(p['episodes'] as List).length}'),
                    style: TextStyle(color: c.inkSoft, fontSize: 12)),
                onTap: () async {
                  await PodcastStore.addToPlaylist(
                      (p['name'] ?? '').toString(), ep);
                  if (mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.t('addedToPlaylist').replaceAll('{name}', '${p['name']}'))));
                  }
                },
              )),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  Future<void> _createAndAdd(Map ep) async {
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
    await PodcastStore.addToPlaylist(name, ep);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('playlistCreated').replaceAll('{name}', name))));
    }
  }

  @override
  void dispose() {
    _audio.current.removeListener(_onEp);
    super.dispose();
  }
}
