import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// «Газета» — one mixed Tinder-style deck: articles + YouTube news videos.
/// · swipe left → next story, swipe right → previous (light, flick-friendly)
/// · double-tap → Instagram heart (pure visual, never stored)
/// · videos autoplay muted through the OFFICIAL YouTube player; tap = pause,
///   one 🔊 button; the sound choice persists across cards and sessions
/// · a story is "read" only after you swipe it away — never on display
/// · read stories are remembered by ID only and never shown again
/// · History re-lists what you've read (light text only, on-device)
class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({Key? key}) : super(key: key);

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen>
    with SingleTickerProviderStateMixin {
  List<Map> _deck = [];
  int _index = 0;
  bool _loading = true;

  // Swipe physics
  Offset _drag = Offset.zero;
  late final AnimationController _flyCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 230));
  Animation<Offset>? _flyAnim;
  bool _flyingBack = false; // true → after fly-out we go to previous

  // Heart (visual only — never persisted anywhere)
  bool _heartVisible = false;
  final Set<String> _hearted = {};

  // Sound preference for videos (persists across cards + sessions)
  static final ValueNotifier<bool> _soundOn = ValueNotifier(false);

  Set<String> _read = {};

  @override
  void initState() {
    super.initState();
    _init();
    _flyCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onFlyDone();
    });
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _read = (p.getStringList('news_read_v2') ?? []).toSet();
    _soundOn.value = p.getBool('news_sound') ?? false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _deck = [];
      _index = 0;
      _drag = Offset.zero;
    });
    final all = await ApiService.news();
    if (!mounted) return;
    // Never show what was already read — the next fetch brings new stories.
    final fresh = all.where((n) => !_read.contains(_id(n))).toList();
    setState(() {
      _deck = fresh;
      _loading = false;
    });
    _precache(1);
    _precache(2);
  }

  String _id(Map n) => (n['id'] ?? n['link'] ?? '').toString();

  void _precache(int i) {
    if (i < 0 || i >= _deck.length) return;
    final img = (_deck[i]['image'] ?? '').toString();
    if (img.isNotEmpty) {
      precacheImage(CachedNetworkImageProvider(img), context);
    }
  }

  Future<void> _markRead(Map n) async {
    final id = _id(n);
    if (id.isEmpty || _read.contains(id)) return;
    _read.add(id);
    final p = await SharedPreferences.getInstance();
    var list = _read.toList();
    if (list.length > 400) list = list.sublist(list.length - 400);
    await p.setStringList('news_read_v2', list);
    // History keeps light text metadata only (no media), on-device only.
    final hist = p.getStringList('news_hist_v1') ?? [];
    hist.insert(0, jsonEncode({
      'id': id,
      't': n['title'],
      's': n['source'],
      'l': n['link'],
      'ts': DateTime.now().toIso8601String(),
    }));
    if (hist.length > 200) hist.removeRange(200, hist.length);
    await p.setStringList('news_hist_v1', hist);
  }

  // ─── Swipe handling ─────────────────────────────────────────────────────────
  bool get _canGoBack => _index > 0;
  // Card is "at rest" → safe to mount the video WebView (no active transform).
  bool get _atRest => _drag == Offset.zero && !_flyCtrl.isAnimating;

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flyCtrl.isAnimating) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_flyCtrl.isAnimating) return;
    final w = MediaQuery.of(context).size.width;
    final dx = _drag.dx;
    final vx = d.velocity.pixelsPerSecond.dx;
    // Feather-light: a tiny flick (or a small drag) sends the card flying.
    // Velocity is the primary trigger, position is a low fallback.
    final goNext = vx < -90 || dx < -w * 0.06;
    final goPrev = (vx > 90 || dx > w * 0.06) && _canGoBack;
    if (goNext || goPrev) {
      _flyingBack = goPrev;
      final target = Offset(goNext ? -w * 1.4 : w * 1.4, _drag.dy * 2);
      _flyAnim = Tween(begin: _drag, end: target).animate(
          CurvedAnimation(parent: _flyCtrl, curve: Curves.easeOut));
      _flyCtrl.forward(from: 0);
      HapticFeedback.selectionClick();
    } else {
      // Spring back
      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 240));
      final anim = Tween(begin: _drag, end: Offset.zero).animate(
          CurvedAnimation(parent: ctrl, curve: Curves.easeOutBack));
      anim.addListener(() => setState(() => _drag = anim.value));
      ctrl.forward().whenComplete(ctrl.dispose);
    }
  }

  void _onFlyDone() {
    // "Read" only when the user actually swiped the card away — never on
    // display (marking on display used to silently drain the deck).
    if (!_flyingBack && _index < _deck.length) {
      _markRead(_deck[_index]);
    }
    setState(() {
      if (_flyingBack) {
        _index = math.max(0, _index - 1);
      } else {
        _index = math.min(_deck.length, _index + 1);
      }
      _drag = Offset.zero;
      _heartVisible = false;
    });
    _flyCtrl.reset();
    _flyAnim = null;
    _precache(_index + 1);
    _precache(_index + 2);
  }

  void _doubleTap() {
    final id = _index < _deck.length ? _id(_deck[_index]) : '';
    if (_hearted.contains(id)) return; // animate once per card
    _hearted.add(id);
    HapticFeedback.mediumImpact();
    setState(() => _heartVisible = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _heartVisible = false);
    });
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _toggleSound() async {
    _soundOn.value = !_soundOn.value;
    final p = await SharedPreferences.getInstance();
    p.setBool('news_sound', _soundOn.value);
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                onPressed: () => Navigator.pop(context),
              ),
              Text('🗞️ ${context.t('newsTitle')}',
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: context.t('newsHistory'),
                icon: Icon(Icons.history_rounded, color: c.inkSoft),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _NewsHistoryScreen()),
                ),
              ),
            ]),
          ),
          // Deck — one mixed stream, no categories
          Expanded(child: _buildDeck(c)),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _buildDeck(BrutalColors c) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_index >= _deck.length) return _caughtUp(c);

    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _flyCtrl,
      builder: (_, __) {
        final d = _flyAnim?.value ?? _drag;
        final a = d.dx / size.width * 0.35;
        final progress = (d.dx.abs() / (size.width * 0.5)).clamp(0.0, 1.0);
        return Stack(alignment: Alignment.center, children: [
          // Next card peeking underneath (scales up as you drag)
          if (_index + 1 < _deck.length)
            Transform.scale(
              scale: 0.93 + 0.07 * progress,
              child: Opacity(
                opacity: 0.6 + 0.4 * progress,
                child: _card(c, _deck[_index + 1], interactive: false),
              ),
            ),
          // Top card — follows the finger with rotation, Tinder-style
          Transform.translate(
            offset: d,
            child: Transform.rotate(
              angle: a,
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onDoubleTap: _doubleTap,
                child: _card(c, _deck[_index], interactive: true),
              ),
            ),
          ),
          // Instagram heart burst (visual only)
          IgnorePointer(
            child: AnimatedScale(
              scale: _heartVisible ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 350),
              curve: Curves.elasticOut,
              child: AnimatedOpacity(
                opacity: _heartVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.favorite_rounded,
                    size: 130,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 30, color: Colors.black54)]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _card(BrutalColors c, Map n, {required bool interactive}) {
    final size = MediaQuery.of(context).size;
    final img = (n['image'] ?? '').toString();
    final isVideo = (n['type'] ?? '') == 'video';
    final videoId = (n['videoId'] ?? '').toString();
    return Container(
      width: size.width - 28,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: c.surface,
        boxShadow: const [
          BoxShadow(blurRadius: 26, color: Colors.black38, offset: Offset(0, 10)),
        ],
      ),
      child: Stack(fit: StackFit.expand, children: [
        // Base layer: the real photo — ALWAYS shown, so a video card never
        // flashes gray while its player boots.
        if (img.isNotEmpty)
          CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: c.surface2),
            errorWidget: (_, __, ___) => _fallbackCover(c),
          )
        else
          _fallbackCover(c),
        // Video: overlay the official YouTube player only when the card is
        // at rest (not being dragged/flung) — WebViews glitch under Transform.
        if (isVideo && interactive && videoId.isNotEmpty)
          _CardYouTube(
              key: ValueKey('yt_$videoId'),
              videoId: videoId,
              active: _atRest,
              soundOn: _soundOn),
        // Play badge on the peeking (non-interactive) video card
        if (isVideo && !interactive)
          const Center(
            child: Icon(Icons.play_circle_fill_rounded,
                size: 74, color: Colors.white70),
          ),
        // Bottom darkening for readability
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        // Glass info panel
        Positioned(
          left: 14, right: 14, bottom: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isVideo) ...[
                            const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 13),
                            const SizedBox(width: 3),
                          ],
                          Text((n['source'] ?? '').toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const Spacer(),
                      Text(_timeAgo(n['date']),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ]),
                    const SizedBox(height: 10),
                    Text((n['title'] ?? '').toString(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            height: 1.25,
                            fontWeight: FontWeight.w800)),
                    if ((n['desc'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text((n['desc'] ?? '').toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              height: 1.4)),
                    ],
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: interactive
                          ? () => _openLink((n['link'] ?? '').toString())
                          : null,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(context.t('readMore'),
                            style: TextStyle(
                                color: c.accent2,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            color: c.accent2, size: 16),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Single sound button — only for videos
        if (isVideo && interactive)
          Positioned(
            top: 14, right: 14,
            child: ValueListenableBuilder<bool>(
              valueListenable: _soundOn,
              builder: (_, on, __) => GestureDetector(
                onTap: _toggleSound,
                child: Container(
                  width: 40, height: 40,
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  child: Icon(
                      on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _fallbackCover(BrutalColors c) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.accent.withOpacity(0.85), c.accent3.withOpacity(0.85)],
          ),
        ),
        child: const Center(
            child: Text('🗞️', style: TextStyle(fontSize: 72))),
      );

  Widget _caughtUp(BrutalColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(context.t('newsCaughtUp'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(context.t('newsCaughtUpSub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, height: 1.4)),
          ]),
        ),
      );

  String _timeAgo(dynamic raw) {
    if (raw == null) return '';
    DateTime? d = DateTime.tryParse(raw.toString());
    if (d == null) {
      // RFC 822 (RSS pubDate): "Tue, 15 Jul 2026 10:00:00 GMT"
      try {
        final parts = raw.toString().split(' ');
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        final day = int.parse(parts[1]);
        final month = months.indexOf(parts[2]) + 1;
        final year = int.parse(parts[3]);
        final hms = parts[4].split(':').map(int.parse).toList();
        d = DateTime.utc(year, month, day, hms[0], hms[1], hms[2]);
      } catch (_) {
        return '';
      }
    }
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  void dispose() {
    _flyCtrl.dispose();
    super.dispose();
  }
}

// ─── YouTube video overlay (official player — ToS-compliant) ─────────────────
// Sits ON TOP of the card's static photo, so the photo is always visible and
// the card never flashes gray. The player is only mounted while [active]
// (card at rest), because WebViews glitch under an animating Transform.
// Autoplays muted; tap = pause/resume; the deck's 🔊 switch un/mutes.
class _CardYouTube extends StatefulWidget {
  final String videoId;
  final bool active;
  final ValueNotifier<bool> soundOn;
  const _CardYouTube({
    super.key,
    required this.videoId,
    required this.active,
    required this.soundOn,
  });

  @override
  State<_CardYouTube> createState() => _CardYouTubeState();
}

class _CardYouTubeState extends State<_CardYouTube> {
  YoutubePlayerController? _yt;
  bool _paused = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _mount();
    widget.soundOn.addListener(_applySound);
  }

  @override
  void didUpdateWidget(_CardYouTube old) {
    super.didUpdateWidget(old);
    // Mount when the card comes to rest; keep it mounted afterwards.
    if (widget.active && _yt == null) _mount();
  }

  void _mount() {
    final ctrl = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: true,
        showControls: false,
        showFullscreenButton: false,
        playsInline: true,
        enableCaption: false,
        strictRelatedVideos: true,
      ),
    );
    _yt = ctrl;
    // Fade the player in once it actually starts, so the photo shows meanwhile.
    ctrl.listen((v) {
      if (!_ready && v.playerState == PlayerState.playing && mounted) {
        setState(() => _ready = true);
        if (widget.soundOn.value) ctrl.unMute();
      }
    });
  }

  void _applySound() {
    if (widget.soundOn.value) {
      _yt?.unMute();
    } else {
      _yt?.mute();
    }
  }

  void _togglePause() {
    final ctrl = _yt;
    if (ctrl == null) return;
    if (_paused) {
      ctrl.playVideo();
    } else {
      ctrl.pauseVideo();
    }
    setState(() => _paused = !_paused);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _yt;
    return Stack(fit: StackFit.expand, children: [
      // Player fades in over the photo once playing (photo stays as base).
      if (ctrl != null)
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: IgnorePointer(child: YoutubePlayer(controller: ctrl)),
            ),
          ),
        ),
      // Tap layer: single tap = pause / resume (Threads-style)
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _togglePause,
        child: AnimatedOpacity(
          opacity: _paused ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: const ColoredBox(
            color: Colors.black26,
            child: Center(
              child: Icon(Icons.play_arrow_rounded,
                  size: 84, color: Colors.white),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    widget.soundOn.removeListener(_applySound);
    _yt?.close();
    super.dispose();
  }
}

// ─── History: read stories (light text metadata only, stored on-device) ──────
class _NewsHistoryScreen extends StatefulWidget {
  const _NewsHistoryScreen();

  @override
  State<_NewsHistoryScreen> createState() => _NewsHistoryScreenState();
}

class _NewsHistoryScreenState extends State<_NewsHistoryScreen> {
  List<Map> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('news_hist_v1') ?? [];
    final items = <Map>[];
    for (final s in raw) {
      try {
        items.add(jsonDecode(s) as Map);
      } catch (_) {}
    }
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('newsHistory'))),
      body: _items.isEmpty
          ? Center(
              child: Text(context.t('newsHistEmpty'),
                  style: TextStyle(color: c.inkSoft)))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: c.ink.withOpacity(0.05)),
              itemBuilder: (_, i) {
                final n = _items[i];
                final ts = DateTime.tryParse((n['ts'] ?? '').toString());
                return ListTile(
                  onTap: () async {
                    final l = (n['l'] ?? '').toString();
                    if (l.isNotEmpty) {
                      try {
                        await launchUrl(Uri.parse(l),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  },
                  leading: Icon(Icons.article_outlined, color: c.inkSoft),
                  title: Text((n['t'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${n['s'] ?? ''}${ts != null ? ' · ${ts.day}.${ts.month.toString().padLeft(2, '0')}' : ''}',
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                );
              },
            ),
    );
  }
}
