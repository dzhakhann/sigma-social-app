import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/api_service.dart';
import '../services/nearby_store.dart';
import '../theme/brutal_theme.dart';
import '../widgets/pro_badge.dart';
import '../widgets/verified_badge.dart';
import '../l10n/app_strings.dart';
import '../widgets/profile_exchange_icon.dart';
import '../widgets/yt_player.dart';
import 'profile_screen.dart';
import 'sigma_nearby_screen.dart';
import 'sigma_nearby_web_screen.dart';

/// "Обзор" — search people by name/@username (+ the exact-handle YouTube
/// channel match, if the query happens to also be a real handle), the
/// profile-exchange entry, and a cached trending-videos feed. No posts, no
/// suggested people here.
class SearchScreen extends StatefulWidget {
  final Map user;
  const SearchScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List _results = [];
  List _ytVideos = [];
  bool _searching = false;
  Timer? _debounce;
  List<Map> _recent = [];
  List _trending = [];

  String get _uid => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    final t = await ApiService.getYoutubeTrending();
    if (mounted) setState(() => _trending = t);
  }

  void _openVideo(Map v) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => YtFullscreenVideo(
          videoId: (v['videoId'] ?? '').toString(),
          title: (v['title'] ?? '').toString(),
          link: (v['link'] ?? '').toString(),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _loadRecent() async {
    final r = await NearbyStore.recent();
    if (mounted) setState(() => _recent = r);
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _results = []; _ytVideos = []; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _searching = true);
    // Sigmacta accounts + an exact-handle YouTube channel match run together —
    // the YT side is a cheap 1-quota-unit lookup (channels.list?forHandle=),
    // never the 100-unit search.list, so this is safe to fire on every query.
    final results = await Future.wait([
      ApiService.searchUsers(q),
      ApiService.getYoutubeChannelVideos(q),
    ]);
    if (mounted) {
      setState(() {
        _results = results[0].where((u) => u['id'].toString() != _uid).toList();
        _ytVideos = results[1];
        _searching = false;
      });
    }
  }

  String _name(Map u) {
    final full = [u['first_name'], u['last_name']]
        .where((e) => (e ?? '').toString().trim().isNotEmpty)
        .map((e) => e.toString())
        .join(' ')
        .trim();
    return full.isNotEmpty ? full : (u['username'] ?? 'User').toString();
  }

  void _openProfile(Map u) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
              user: widget.user, targetUserId: u['id'], isOwnProfile: false),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('discover'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: context.t('searchPeople'),
              prefixIcon: Icon(Icons.search, color: c.accent),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() { _results = []; _ytVideos = []; });
                      })
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : hasQuery
                  ? _resultsList(c)
                  : _discover(c),
        ),
      ]),
    );
  }

  Widget _resultsList(BrutalColors c) {
    if (_results.isEmpty && _ytVideos.isEmpty) {
      return Center(
          child: Text(context.t('nothingFound'),
              style: TextStyle(color: c.inkSoft)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        for (final u in _results) _personTile(c, u),
        if (_ytVideos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Row(children: [
              const Icon(Icons.smart_display_rounded, size: 18, color: Color(0xFFFF0000)),
              const SizedBox(width: 6),
              Text('YouTube',
                  style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
          // Vertical list (same row widget the trending feed uses), not the
          // old horizontal strip: a keyword search returns ~10 videos and
          // you're here to pick one, so they all need to be browsable
          // without sideways scrolling.
          for (final v in _ytVideos) _trendingRow(c, v),
        ],
      ],
    );
  }

  Widget _discover(BrutalColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        // Profile exchange → Sigma Nearby
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                // Bluetooth/Wi-Fi Direct discovery has no web equivalent —
                // Safari on iOS doesn't expose Web Bluetooth at all — so web
                // gets the QR/code version of the same server-side exchange
                // instead of the native radar screen.
                builder: (_) => kIsWeb
                    ? SigmaNearbyWebScreen(user: widget.user)
                    : SigmaNearbyScreen(user: widget.user)),
          ).then((_) => _loadRecent()),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [c.accent.withOpacity(0.22), c.accent3.withOpacity(0.12)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.accent.withOpacity(0.3)),
            ),
            child: Row(children: [
              ProfileExchangeIcon(size: 62, color: c.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('profileExchange'),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: c.ink)),
                    const SizedBox(height: 3),
                    Text(context.t('profileExchangeHint'),
                        style: TextStyle(
                            color: c.inkSoft, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.inkSoft),
            ]),
          ),
        ),
        // Recent Sigma Nearby connections (local history)
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(context.t('nearbyRecent'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800)),
          ),
          for (final r in _recent) _recentTile(c, r),
        ],
        // Trending YouTube — same cached feed for everyone, refreshed a few
        // times a day server-side, not per-request. View-only: no comments,
        // no history, no likes, no Google sign-in.
        if (_trending.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFFF0000)),
              const SizedBox(width: 6),
              Text(context.t('trendingLabel'),
                  style: TextStyle(color: c.ink, fontSize: 15.5, fontWeight: FontWeight.w800)),
            ]),
          ),
          for (final v in _trending) _trendingRow(c, v),
        ],
      ],
    );
  }

  Widget _trendingRow(BrutalColors c, Map v) => GestureDetector(
        onTap: () => _openVideo(v),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  // Trending rows carry `image`, channel/search hits `thumb`.
                  imageUrl: (v['image'] ?? v['thumb'] ?? '').toString(),
                  width: 96, height: 64, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(width: 96, height: 64, color: c.surface2),
                  errorWidget: (_, __, ___) => Container(width: 96, height: 64, color: c.surface2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((v['title'] ?? '').toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text((v['channel'] ?? v['source'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _recentTile(BrutalColors c, Map r) {
    DateTime? at;
    try {
      at = DateTime.parse((r['at'] ?? '').toString());
    } catch (_) {}
    final lang = AppScope.of(context).lang;
    final when = at == null
        ? ''
        : timeago.format(at, locale: lang == 'ru' ? 'ru' : 'en');
    final url = (r['avatar_url'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openProfile(r),
        leading: CircleAvatar(
          radius: 21,
          backgroundColor: c.surface2,
          backgroundImage:
              url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
          child: url.isEmpty ? Icon(Icons.person, color: c.inkSoft) : null,
        ),
        title: Text('@${r['username'] ?? ''}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(when,
            style: TextStyle(color: c.inkSoft, fontSize: 12)),
        trailing: Icon(Icons.bolt_rounded, color: c.accent, size: 20),
      ),
    );
  }

  Widget _personTile(BrutalColors c, Map u) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openProfile(u),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: c.surface2,
          backgroundImage: u['avatar_url'] != null
              ? CachedNetworkImageProvider(u['avatar_url'])
              : null,
          child: u['avatar_url'] == null
              ? Icon(Icons.person, color: c.inkSoft)
              : null,
        ),
        title: Row(children: [
          Flexible(
            child: Text(_name(u),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (u['is_verified'] == true) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(),
          ],
          if (u['is_pro'] == true) ...[
            const SizedBox(width: 4),
            ProBadge(
                isPro: true,
                gifUrl: u['pro_badge_gif']?.toString(),
                height: 18),
          ],
        ]),
        subtitle: Text(
            '@${u['username'] ?? ''}${(u['work'] ?? '').toString().trim().isNotEmpty ? ' · ${u['work']}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
        trailing: Icon(Icons.chevron_right, color: c.inkSoft),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
