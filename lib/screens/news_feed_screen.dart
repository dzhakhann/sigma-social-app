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

/// Standalone «Газета» screen (from the home teaser's history button etc).
class NewsFeedScreen extends StatelessWidget {
  const NewsFeedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                onPressed: () => Navigator.pop(context),
              ),
              Text('🗞️ ${context.t('newsTitle')}',
                  style: TextStyle(
                      color: c.ink, fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.history_rounded, color: c.inkSoft),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewsHistoryScreen()),
                ),
              ),
            ]),
          ),
          const Expanded(child: NewsDeck()),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

/// «Газета» deck — one mixed Tinder-style stack of article + video cards.
/// Designed to be embedded directly on the home screen (fixed height) OR used
/// full-screen. Horizontal drags flick cards; vertical drags pass THROUGH to a
/// parent scroll view, so it works inline in the scrolling home feed.
///
/// · light flick → next / previous
/// · double-tap → Instagram heart (visual only, never stored)
/// · video card → tap plays fullscreen via the official YouTube player
/// · a card is "read" only after it's swiped away, never on display
class NewsDeck extends StatefulWidget {
  const NewsDeck({Key? key}) : super(key: key);

  @override
  State<NewsDeck> createState() => _NewsDeckState();
}

class _NewsDeckState extends State<NewsDeck>
    with SingleTickerProviderStateMixin {
  List<Map> _deck = [];
  int _index = 0;
  bool _loading = true;

  double _dx = 0; // horizontal drag only
  late final AnimationController _flyCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 230));
  Animation<double>? _flyAnim;
  bool _flyingBack = false;

  bool _heartVisible = false;
  final Set<String> _hearted = {};
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _deck = [];
      _index = 0;
      _dx = 0;
    });
    final all = await ApiService.news();
    if (!mounted) return;
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
    final hist = p.getStringList('news_hist_v1') ?? [];
    hist.insert(0, jsonEncode({
      'id': id, 't': n['title'], 's': n['source'], 'l': n['link'],
      'ts': DateTime.now().toIso8601String(),
    }));
    if (hist.length > 200) hist.removeRange(200, hist.length);
    await p.setStringList('news_hist_v1', hist);
  }

  // ─── Swipe (horizontal only, so vertical scroll passes through) ─────────────
  bool get _canGoBack => _index > 0;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flyCtrl.isAnimating) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_flyCtrl.isAnimating) return;
    final w = MediaQuery.of(context).size.width;
    final vx = d.velocity.pixelsPerSecond.dx;
    final goNext = vx < -90 || _dx < -w * 0.06;
    final goPrev = (vx > 90 || _dx > w * 0.06) && _canGoBack;
    if (goNext || goPrev) {
      _flyingBack = goPrev;
      final target = goNext ? -w * 1.4 : w * 1.4;
      _flyAnim = Tween(begin: _dx, end: target).animate(
          CurvedAnimation(parent: _flyCtrl, curve: Curves.easeOut));
      _flyCtrl.forward(from: 0);
      HapticFeedback.selectionClick();
    } else {
      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 240));
      final anim = Tween(begin: _dx, end: 0.0).animate(
          CurvedAnimation(parent: ctrl, curve: Curves.easeOutBack));
      anim.addListener(() => setState(() => _dx = anim.value));
      ctrl.forward().whenComplete(ctrl.dispose);
    }
  }

  void _onFlyDone() {
    if (!_flyingBack && _index < _deck.length) _markRead(_deck[_index]);
    setState(() {
      _index = _flyingBack
          ? math.max(0, _index - 1)
          : math.min(_deck.length, _index + 1);
      _dx = 0;
      _heartVisible = false;
    });
    _flyCtrl.reset();
    _flyAnim = null;
    _precache(_index + 1);
    _precache(_index + 2);
  }

  void _doubleTap() {
    final id = _index < _deck.length ? _id(_deck[_index]) : '';
    if (_hearted.contains(id)) return;
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

  void _playVideo(Map n) {
    final id = (n['videoId'] ?? '').toString();
    if (id.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            _FullscreenVideo(videoId: id, title: (n['title'] ?? '').toString()),
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_index >= _deck.length) return _caughtUp(c);
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _flyCtrl,
      builder: (_, __) {
        final dx = _flyAnim?.value ?? _dx;
        final a = dx / size.width * 0.35;
        final progress = (dx.abs() / (size.width * 0.5)).clamp(0.0, 1.0);
        return Stack(alignment: Alignment.center, children: [
          if (_index + 1 < _deck.length)
            Transform.scale(
              scale: 0.93 + 0.07 * progress,
              child: Opacity(
                opacity: 0.6 + 0.4 * progress,
                child: _card(c, _deck[_index + 1], interactive: false),
              ),
            ),
          Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.rotate(
              angle: a,
              child: GestureDetector(
                // Horizontal only → vertical scroll passes to the parent.
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onDoubleTap: _doubleTap,
                child: _card(c, _deck[_index], interactive: true),
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedScale(
              scale: _heartVisible ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 350),
              curve: Curves.elasticOut,
              child: AnimatedOpacity(
                opacity: _heartVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.favorite_rounded,
                    size: 120,
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
    final img = (n['image'] ?? '').toString();
    final isVideo = (n['type'] ?? '') == 'video';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: c.surface,
        boxShadow: const [
          BoxShadow(blurRadius: 24, color: Colors.black38, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(fit: StackFit.expand, children: [
        // HD photo (og:image). Video cards fall back maxres → hq thumbnail.
        if (img.isNotEmpty)
          CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: c.surface2),
            errorWidget: (_, __, ___) {
              final fb = (n['thumb'] ?? '').toString();
              if (fb.isNotEmpty) {
                return CachedNetworkImage(
                    imageUrl: fb,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _fallbackCover(c));
              }
              return _fallbackCover(c);
            },
          )
        else
          _fallbackCover(c),
        if (isVideo)
          Positioned.fill(
            child: GestureDetector(
              onTap: interactive ? () => _playVideo(n) : null,
              child: Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 82,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 18, color: Colors.black54)]),
                ),
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Positioned(
          left: 14, right: 14, bottom: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
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
                    const SizedBox(height: 9),
                    Text((n['title'] ?? '').toString(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1.25,
                            fontWeight: FontWeight.w800)),
                    if ((n['desc'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text((n['desc'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.4)),
                    ],
                    const SizedBox(height: 10),
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
        child: const Center(child: Text('🗞️', style: TextStyle(fontSize: 64))),
      );

  Widget _caughtUp(BrutalColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 14),
            Text(context.t('newsCaughtUp'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(context.t('newsCaughtUpSub'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, height: 1.4, fontSize: 13)),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh_rounded, color: c.accent),
              label: Text(context.t('newsRefresh'),
                  style: TextStyle(color: c.accent)),
            ),
          ]),
        ),
      );

  String _timeAgo(dynamic raw) {
    if (raw == null) return '';
    DateTime? d = DateTime.tryParse(raw.toString());
    if (d == null) {
      try {
        final parts = raw.toString().split(' ');
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        d = DateTime.utc(int.parse(parts[3]), months.indexOf(parts[2]) + 1,
            int.parse(parts[1]),
            int.parse(parts[4].split(':')[0]),
            int.parse(parts[4].split(':')[1]));
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

// ─── Fullscreen YouTube player (official, ToS-compliant, reliable) ───────────
// Opened on tap. Autoplays with sound (a user gesture opened it, so the WebView
// autoplay policy is satisfied). Tap = pause/resume, back / ✕ = close.
class _FullscreenVideo extends StatefulWidget {
  final String videoId;
  final String title;
  const _FullscreenVideo({required this.videoId, required this.title});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  late final YoutubePlayerController _yt = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showControls: true,
      showFullscreenButton: false,
      playsInline: true,
      strictRelatedVideos: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: YoutubePlayer(controller: _yt),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          left: 16, right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 20,
          child: Text(widget.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}

// ─── History: read stories (light text metadata only, stored on-device) ──────
class NewsHistoryScreen extends StatefulWidget {
  const NewsHistoryScreen({Key? key}) : super(key: key);

  @override
  State<NewsHistoryScreen> createState() => _NewsHistoryScreenState();
}

class _NewsHistoryScreenState extends State<NewsHistoryScreen> {
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
