import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../constants.dart';
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

  // Inline muted autoplay for the front video card (Instagram/TikTok-style).
  // Only ONE player is ever alive (the top card); tap opens it fullscreen with
  // sound. The player is a WebView loading OUR hosted embed page — YouTube
  // requires a real https Referer now ("Error 153"), so in-memory player HTML
  // (youtube_player_iframe) is rejected for every video.
  String? _inlineId;
  bool _inlineFailed = false;
  bool _inlineSuspended = false; // true while the fullscreen player is open
  bool _inlineMuted = true; // sticky across cards, like Instagram
  final GlobalKey<_YtWebPlayerState> _inlineKey = GlobalKey();

  void _toggleInlineSound() {
    HapticFeedback.selectionClick();
    setState(() => _inlineMuted = !_inlineMuted);
    // Live toggle — no reload, the video keeps playing.
    _inlineKey.currentState?.setMuted(_inlineMuted);
  }

  void _syncInlinePlayer() {
    final n = _index < _deck.length ? _deck[_index] : null;
    final isVideo = n != null && (n['type'] ?? '') == 'video';
    final vid = isVideo ? (n['videoId'] ?? '').toString() : '';
    if (vid == (_inlineId ?? '')) return; // already showing the right video
    if (mounted) {
      setState(() {
        _inlineId = vid.isEmpty ? null : vid;
        _inlineFailed = false;
      });
    }
  }

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
      // Unread first; if everything's been read, fall back to the full pool so
      // the deck is never empty. It's an endless feed, not a "done" state.
      _deck = fresh.isNotEmpty ? fresh : List<Map>.from(all);
      _loading = false;
    });
    _syncInlinePlayer();
    _precache(1);
    _precache(2);
  }

  // Endless feed: top up the deck as the user nears the end. Pulls a fresh
  // batch from the server (which rotates content) and appends anything new; if
  // there's nothing new yet, it re-appends the pool so swiping never dead-ends.
  bool _loadingMore = false;
  Future<void> _maybeLoadMore() async {
    if (_loadingMore || _index < _deck.length - 5) return;
    _loadingMore = true;
    try {
      final all = await ApiService.news();
      if (!mounted) return;
      final have = _deck.map(_id).toSet();
      final incoming = all.where((n) => !have.contains(_id(n))).toList();
      final toAdd = incoming.isNotEmpty ? incoming : List<Map>.from(all);
      if (toAdd.isNotEmpty) setState(() => _deck.addAll(toAdd));
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
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
    // Either direction advances to the NEXT story (going back is the "Undo"
    // button now). The card flies off whichever way it was thrown.
    final goNext = vx.abs() > 90 || _dx.abs() > w * 0.06;
    if (goNext) {
      _flyingBack = false;
      final dir = (_dx != 0 ? _dx : -vx) < 0 ? -1.0 : 1.0;
      final target = dir * w * 1.4;
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
    _syncInlinePlayer();
    _maybeLoadMore();
    _precache(_index + 1);
    _precache(_index + 2);
  }

  // "Undo" — brings the previous story back (replaces the old swipe-right-back).
  void _goBack() {
    if (_flyCtrl.isAnimating || !_canGoBack) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index -= 1;
      _dx = 0;
      _heartVisible = false;
    });
    _syncInlinePlayer();
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

  // Single tap on the top card. On a video card it opens the player instantly;
  // living on the parent gesture detector (not a nested one) keeps the tap from
  // being swallowed while the double-tap-to-heart timer disambiguates.
  void _onTapCard() {
    if (_flyCtrl.isAnimating || _index >= _deck.length) return;
    final n = _deck[_index];
    if ((n['type'] ?? '') == 'video') _playVideo(n);
  }

  Future<void> _playVideo(Map n) async {
    final id = (n['videoId'] ?? '').toString();
    final link = (n['link'] ?? '').toString();
    if (id.isEmpty) {
      _openLink(link);
      return;
    }
    HapticFeedback.selectionClick();
    // Pause the inline preview while fullscreen plays (one player at a time).
    setState(() => _inlineSuspended = true);
    await Navigator.push(
      context,
      PageRouteBuilder(
        // OPAQUE: a transparent route over a WebView platform-view smears/ghosts
        // (the "trail") and gives the player no solid surface to composite on.
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => _FullscreenVideo(
            videoId: id, title: (n['title'] ?? '').toString(), link: link),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted) setState(() => _inlineSuspended = false);
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_deck.isEmpty) return _caughtUp(c); // only a real empty feed (offline)
    if (_index >= _deck.length) {
      // Ran past the tail — top up (or loop) and show a brief spinner.
      _maybeLoadMore();
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    final size = MediaQuery.of(context).size;

    return Stack(children: [
      _deckStack(c, size),
      // "Вернуть" — small pill, top-left, only once you've moved past the first
      // card. Sits above the deck so swiping doesn't move it.
      if (_canGoBack)
        Positioned(
          top: 6,
          left: 22,
          child: _undoChip(c),
        ),
    ]);
  }

  Widget _undoChip(BrutalColors c) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _goBack,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.undo_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(context.t('newsUndo'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _deckStack(BrutalColors c, Size size) {
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
                onTap: _onTapCard,
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
    final isVideo = (n['type'] ?? '') == 'video';
    return isVideo
        ? _videoCard(c, n, interactive: interactive)
        : _articleCard(c, n, interactive: interactive);
  }

  // Article card: image in the upper part, a solid readable panel below with
  // the FULL headline + description (instead of half-cut text over the photo).
  Widget _articleCard(BrutalColors c, Map n, {required bool interactive}) {
    final img = (n['image'] ?? '').toString();
    final desc = (n['desc'] ?? '').toString();
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
      child: Column(children: [
        // Image fills the top; the text panel below takes exactly what it needs,
        // so the whole headline + description stay readable.
        Expanded(child: _cardImage(c, n, img)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          color: c.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text((n['source'] ?? '').toString(),
                      style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text(_timeAgo(n['date']),
                    style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Text((n['title'] ?? '').toString(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 18.5,
                      height: 1.28,
                      fontWeight: FontWeight.w800)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(desc,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.inkSoft, fontSize: 13.5, height: 1.42)),
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
                  Icon(Icons.arrow_forward_rounded, color: c.accent2, size: 16),
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // Video card: full-bleed player/thumbnail with the glass caption overlay.
  Widget _videoCard(BrutalColors c, Map n, {required bool interactive}) {
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
        // Full image, never cropped: a blurred cover fills the card (no black
        // bars) with the whole photo/thumbnail shown "contain" on top — so text
        // baked into a thumbnail stays fully visible, Instagram-style.
        _cardImage(c, n, img),
        // Front video card → inline muted autoplay (over the blurred image).
        // IgnorePointer so tap/swipe still go to the parent (tap = fullscreen
        // with sound). Falls back to a static play button if it can't embed.
        if (isVideo &&
            interactive &&
            _inlineId == (n['videoId'] ?? '').toString() &&
            !_inlineFailed &&
            !_inlineSuspended) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: _YtWebPlayer(
                key: _inlineKey,
                videoId: (n['videoId'] ?? '').toString(),
                muted: _inlineMuted,
                controls: false,
                loop: true,
                onEvent: (e) {
                  if ((e.startsWith('error') || e == 'timeout') && mounted) {
                    setState(() => _inlineFailed = true);
                  }
                },
              ),
            ),
          ),
        ] else if (isVideo)
          const Positioned.fill(
            // Static play button: background cards, or a clip that won't embed.
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black26),
                child: Center(
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
        // Instagram-style sound toggle — LAST child so it sits above the
        // gradient/caption layers (below them it's covered and untappable).
        if (isVideo &&
            interactive &&
            _inlineId == (n['videoId'] ?? '').toString() &&
            !_inlineFailed &&
            !_inlineSuspended)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleInlineSound,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Icon(
                  _inlineMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // Blurred cover fill + full "contain" image on top. Shows the entire picture
  // (incl. any text on it) without ugly bars. Video thumbs fall back to `thumb`.
  Widget _cardImage(BrutalColors c, Map n, String img) {
    if (img.isEmpty) return _fallbackCover(c);
    final fb = (n['thumb'] ?? '').toString();
    Widget contained(String url) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => fb.isNotEmpty && url != fb
              ? contained(fb)
              : const SizedBox.shrink(),
        );
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: CachedNetworkImage(
          imageUrl: img,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: c.surface2),
          errorWidget: (_, __, ___) => _fallbackCover(c),
        ),
      ),
      Container(color: Colors.black.withOpacity(0.18)),
      contained(img),
    ]);
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
        // Respect the RFC-822 offset ("+0300"/"GMT") so we don't read a local
        // time as UTC (that produced future "-129m" timestamps).
        if (parts.length > 5) {
          final tz = parts[5];
          final m = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(tz);
          if (m != null) {
            final sign = m.group(1) == '-' ? -1 : 1;
            final off = Duration(
                hours: int.parse(m.group(2)!),
                minutes: int.parse(m.group(3)!));
            d = d.subtract(off * sign); // convert local→UTC
          }
        }
      } catch (_) {
        return '';
      }
    }
    var diff = DateTime.now().difference(d.toLocal());
    if (diff.isNegative) diff = Duration.zero; // clock skew guard, never show "-"
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

// ─── WebView player: loads OUR hosted embed page (real https origin) ─────────
// YouTube requires a valid Referer for embeds ("Error 153"), so the page must
// come from a real server — the backend serves /yt (public/yt-embed.html),
// which hosts the official YouTube iframe player. State events arrive through
// the SigmaYT JavaScript channel: ready / playing / ended / error:N / timeout.
class _YtWebPlayer extends StatefulWidget {
  final String videoId;
  final bool muted;
  final bool controls;
  final bool loop;
  final void Function(String event)? onEvent;
  const _YtWebPlayer({
    Key? key,
    required this.videoId,
    this.muted = false,
    this.controls = true,
    this.loop = false,
    this.onEvent,
  }) : super(key: key);

  @override
  State<_YtWebPlayer> createState() => _YtWebPlayerState();
}

class _YtWebPlayerState extends State<_YtWebPlayer>
    with WidgetsBindingObserver {
  late final WebViewController _c;
  bool _visible = true;
  bool _playing = true;

  static final String _base = kApiUrl.replaceFirst('/api', '');

  String get _url => '$_base/yt?v=${widget.videoId}'
      '&mute=${widget.muted ? 1 : 0}'
      '&controls=${widget.controls ? 1 : 0}'
      '&loop=${widget.loop ? 1 : 0}';

  /// Toggle sound live, without reloading the video.
  Future<void> setMuted(bool muted) async {
    try {
      await _c.runJavaScript(
          'window.sigmaSetMuted && sigmaSetMuted(${muted ? 'true' : 'false'})');
    } catch (_) {}
  }

  // Pause when scrolled off-screen / tab switched / app backgrounded; resume
  // from the same spot when visible again. Only for the inline preview (looping
  // clip); the fullscreen player passes controls and shouldn't auto-pause.
  bool _foreground = true;

  void _apply() {
    if (!widget.loop) return; // fullscreen player opts out of auto-pause
    final shouldPlay = _visible && _foreground;
    if (shouldPlay == _playing) return;
    _playing = shouldPlay;
    _c.runJavaScript(shouldPlay ? 'window.sigmaPlay&&sigmaPlay()'
                                : 'window.sigmaPause&&sigmaPause()');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    _c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('SigmaYT',
          onMessageReceived: (m) => widget.onEvent?.call(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // Keep the main frame on our player page (block taps on YouTube logo
        // etc. from hijacking the WebView).
        onNavigationRequest: (r) =>
            r.url.startsWith('$_base/yt') || r.url.startsWith('about:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
      ))
      ..loadRequest(Uri.parse(_url));
    final platform = _c.platform;
    if (platform is AndroidWebViewController) {
      // Allow autoplay (with sound in fullscreen) without a tap inside the view.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  @override
  void didUpdateWidget(covariant _YtWebPlayer old) {
    super.didUpdateWidget(old);
    // Same widget instance survives across cards (stable GlobalKey) — load the
    // new clip when the video changes. Mute changes go through setMuted().
    if (old.videoId != widget.videoId) {
      _playing = true; // fresh page autoplays
      _c.loadRequest(Uri.parse(_url));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = WebViewWidget(controller: _c);
    if (!widget.loop) return view; // fullscreen: no auto-pause
    return VisibilityDetector(
      key: const Key('gazette_inline_video'),
      onVisibilityChanged: (info) {
        final vis = info.visibleFraction > 0.55;
        if (vis == _visible) return;
        _visible = vis;
        _apply();
      },
      child: view,
    );
  }
}

// ─── Fullscreen YouTube player (official, ToS-compliant, reliable) ───────────
// Opened on tap. Autoplays with sound (a user gesture opened it, so the WebView
// autoplay policy is satisfied). YouTube's own controls handle play/pause — we
// never overlay a tap-catcher across the player, so those controls stay live.
// ✕ = close, ↗ = open in the YouTube app. If the clip refuses to embed we show
// a graceful "Watch on YouTube" fallback instead of a dead black screen.
class _FullscreenVideo extends StatefulWidget {
  final String videoId;
  final String title;
  final String link;
  const _FullscreenVideo(
      {required this.videoId, required this.title, required this.link});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  bool _ready = false;
  bool _failed = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // Safety net: if the player never reports anything (network, blocked clip),
    // fall back to "Watch on YouTube" instead of spinning forever. The hosted
    // page also sends its own 'timeout' event after 8s.
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted && !_ready && !_failed) setState(() => _failed = true);
    });
  }

  void _onPlayerEvent(String e) {
    if (!mounted) return;
    if (e == 'ready' || e == 'playing') {
      _timeout?.cancel();
      if (!_ready) setState(() => _ready = true);
    } else if (e.startsWith('error') || e == 'timeout') {
      _timeout?.cancel();
      if (!_failed) setState(() => _failed = true);
    }
  }

  Future<void> _openInYouTube() async {
    final url = widget.link.isNotEmpty
        ? widget.link
        : 'https://www.youtube.com/watch?v=${widget.videoId}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
          Positioned.fill(
            child: _failed
                ? Center(child: _fallback())
                : _YtWebPlayer(
                    key: ValueKey('fs_${widget.videoId}'),
                    videoId: widget.videoId,
                    muted: false,
                    controls: true,
                    loop: false,
                    onEvent: _onPlayerEvent,
                  ),
          ),
          if (!_ready && !_failed)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 6,
            right: 6,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'YouTube',
                icon: const Icon(Icons.open_in_new_rounded,
                    color: Colors.white, size: 24),
                onPressed: _openInYouTube,
              ),
            ]),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 66,
            child: IgnorePointer(
              child: Text(widget.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
            ),
          ),
        ]),
    );
  }

  Widget _fallback() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_display_outlined,
              color: Colors.white54, size: 56),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(widget.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black),
            onPressed: _openInYouTube,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Watch on YouTube'),
          ),
        ],
      );

  @override
  void dispose() {
    _timeout?.cancel();
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
