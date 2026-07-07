import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'story_view_screen.dart';
import 'notifications_screen.dart';
import 'login_screen.dart';
import '../services/session.dart';
import '../widgets/link_preview.dart';
import '../widgets/shimmer.dart';
import '../services/events.dart';

// ════════════════════════════════════════════════════════════════════════════
//  HOME — Threads-style feed with stories row + FAB for compose.
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  final Map user;
  const HomeScreen({super.key, required this.user});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List _posts = [];
  List _stories = [];
  bool _loading = false;
  int _tab = 0; // 0 = Для вас (рекомендации), 1 = Подписки
  final Map<int, List> _tabCache = {}; // in-memory feed per tab for instant switch

  @override
  void initState() {
    super.initState();
    _load();
    feedRefresh.addListener(_onFeedRefresh);
  }

  void _onFeedRefresh() => _load();

  Future<void> _load() async {
    final cached = await _readCache();
    if (mounted) {
      setState(() {
        if (cached != null && _posts.isEmpty) _posts = cached;
        _loading = _posts.isEmpty;
      });
    }
    // "Для вас" = recommendations/recent; "Подписки" = following (with fallback
    // to recent so a new user's feed is never blank).
    List data;
    if (_tab == 1) {
      data = await ApiService.getFollowingPosts(widget.user['id']);
      if (data.isEmpty) {
        data = await ApiService.getPosts(widget.user['id'].toString());
      }
    } else {
      data = await ApiService.getPosts(widget.user['id'].toString());
    }
    _tabCache[_tab] = data;
    if (mounted) {
      setState(() { _posts = data; _loading = false; });
    }
    _saveCache(data);
    _loadStories();
  }

  void _setTab(int i) {
    if (_tab == i) return;
    HapticFeedback.selectionClick();
    final cached = _tabCache[i];
    setState(() {
      _tab = i;
      if (cached != null) {
        // Instant switch to already-loaded feed; refresh silently in the bg.
        _posts = cached;
        _loading = false;
      } else {
        _posts = [];
        _loading = true;
      }
    });
    _load();
  }

  Future<List?> _readCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('feed_cache');
      return s == null ? null : (jsonDecode(s) as List);
    } catch (_) { return null; }
  }

  Future<void> _saveCache(List data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('feed_cache', jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadStories() async {
    final data = await ApiService.getStories();
    if (mounted) setState(() => _stories = data);
  }

  Map<String, List> get _grouped {
    final Map<String, List> g = {};
    for (var s in _stories) {
      final uid = s['user_id']?.toString();
      if (uid == null || uid == widget.user['id'].toString()) continue;
      g.putIfAbsent(uid, () => []).add(s);
    }
    return g;
  }

  void _openStory(List uStories) {
    final all = _grouped.values.toList();
    int gi = 0;
    for (int i = 0; i < all.length; i++) {
      if (all[i].isNotEmpty &&
          all[i][0]['user_id'] == uStories[0]['user_id']) {
        gi = i;
        break;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewScreen(
          stories: uStories,
          allGroups: all,
          groupIndex: gi,
          startIndex: 0,
          user: widget.user,
          onStoryDeleted: _loadStories,
        ),
      ),
    );
  }

  Future<void> _addStory({ImageSource? source}) async {
    final c = context.k;
    final src = source ?? await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StoryPickerSheet(c: c),
    );
    if (src == null) return;
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: src, maxWidth: 800, imageQuality: 70);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final data =
        await ApiService.uploadStory(widget.user['id'], base64Encode(bytes));
    if (data['success'] == true) _loadStories();
  }


  // ─── Reactions ───────────────────────────────────────────────────────────
  Future<void> _react(Map post, int index) async {
    final wasLiked = post['is_liked'] == true;
    setState(() {
      _posts[index]['is_liked'] = !wasLiked;
      _posts[index]['likes_count'] =
          (post['likes_count'] ?? 0) + (wasLiked ? -1 : 1);
    });
    HapticFeedback.lightImpact();
    final res = await ApiService.likePost(
        post['id'].toString(), widget.user['id'].toString());
    if (res['success'] == true && mounted) {
      setState(() {
        _posts[index]['likes_count'] = res['likes_count'] ?? _posts[index]['likes_count'];
        _posts[index]['is_liked'] = res['liked'] == true;
      });
    }
  }

  Future<void> _repost(Map post) async {
    HapticFeedback.lightImpact();
    // Repost lives on the profile + notifies followers; it does NOT enter the
    // feed. So we don't touch _posts here.
    final res = await ApiService.repostPost(post['id'].toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['success'] == true
              ? 'Репост опубликован в вашем профиле'
              : 'Не удалось сделать репост')));
    }
  }

  void _share(Map post) {
    final username = (post['username'] ?? 'user').toString();
    final content = (post['content'] ?? '').toString();
    Clipboard.setData(
        ClipboardData(text: 'Sigmacta · @$username: $content'));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('linkCopied'))),
    );
  }

  void _postMenu(Map post, int index) {
    final c = context.k;
    final isOwn =
        post['user_id'].toString() == widget.user['id'].toString();

    void done(String msg) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }

    void soon() => done('Скоро будет доступно');

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: c.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            _SheetTile(
                icon: Icons.link_rounded,
                label: 'Копировать ссылку',
                onTap: () {
                  Clipboard.setData(ClipboardData(
                      text: 'https://sigmacta.app/post/${post['id']}'));
                  done('Ссылка скопирована');
                }),
            _SheetTile(
                icon: Icons.translate_rounded,
                label: 'Перевести',
                onTap: soon),
            _SheetTile(
                icon: Icons.bookmark_border_rounded,
                label: 'Сохранить',
                onTap: soon),
            _SheetTile(
                icon: Icons.not_interested_rounded,
                label: 'Не интересует',
                onTap: () {
                  Navigator.pop(context);
                  if (mounted) setState(() => _posts.removeAt(index));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Учтём. Меньше похожего в ленте.')));
                }),
            if (!isOwn) ...[
              _SheetTile(
                  icon: Icons.visibility_off_outlined,
                  label: 'Скрыть пользователя',
                  onTap: () {
                    Navigator.pop(context);
                    final uid = post['user_id'].toString();
                    if (mounted) {
                      setState(() => _posts.removeWhere(
                          (p) => p['user_id'].toString() == uid));
                    }
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Публикации ${post['username'] ?? 'этого пользователя'} скрыты')));
                  }),
              _SheetTile(
                  icon: Icons.shield_outlined,
                  label: 'Установить ограничения',
                  onTap: soon),
              _SheetTile(
                  icon: Icons.block_rounded,
                  label: 'Заблокировать',
                  color: c.danger,
                  onTap: soon),
              _SheetTile(
                  icon: Icons.flag_outlined,
                  label: 'Пожаловаться',
                  color: c.danger,
                  onTap: () => done('Жалоба отправлена. Спасибо!')),
            ],
            if (isOwn)
              _SheetTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Удалить публикацию',
                  color: c.danger,
                  onTap: () async {
                    Navigator.pop(context);
                    await ApiService.deletePost(post['id'].toString());
                    if (mounted) setState(() => _posts.removeAt(index));
                  }),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          backgroundColor: c.surface,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(c)),
              SliverToBoxAdapter(child: _storiesRow(c)),
              SliverToBoxAdapter(child: _tabsRow(c)),
              SliverToBoxAdapter(
                  child: Divider(height: 1, color: c.ink.withOpacity(0.07))),
              if (_loading)
                const SliverToBoxAdapter(child: FeedSkeleton())
              else if (_posts.isEmpty)
                SliverToBoxAdapter(child: _empty(c))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ThreadsPost(
                      post: _posts[i],
                      user: widget.user,
                      onLike: () => _react(_posts[i], i),
                      onComment: () => CommentsScreen.show(
                        context,
                        post: _posts[i],
                        user: widget.user,
                      ).then((_) => _load()),
                      onRepost: () => _repost(_posts[i]),
                      onShare: () => _share(_posts[i]),
                      onMore: () => _postMenu(_posts[i], i),
                      onProfileTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            user: widget.user,
                            targetUserId: _posts[i]['user_id'],
                            isOwnProfile:
                                _posts[i]['user_id'] == widget.user['id'],
                          ),
                        ),
                      ),
                    ),
                    childCount: _posts.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: c.buttonGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: const Text('Σ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NotificationsScreen(user: widget.user)),
            ),
            child: Icon(Icons.notifications_none_rounded, color: c.ink, size: 25),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: _openFeeds,
            child: Icon(Icons.menu, color: c.ink, size: 24),
          ),
        ],
      ),
    );
  }

  // Segmented "Для вас / Подписки" tabs (Threads/Twitter-style).
  Widget _tabsRow(BrutalColors c) {
    Widget tab(String label, int i) {
      final sel = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setTab(i),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                        color: sel ? c.ink : c.inkSoft,
                        fontSize: 14.5,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2.5,
                  width: sel ? 34 : 0,
                  decoration: BoxDecoration(
                      color: c.accent, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [tab('Для вас', 0), tab('Подписки', 1)]);
  }

  // "Ленты" side panel opened by the hamburger — mirrors the Figma prototype.
  void _openFeeds() {
    final c = context.k;
    Widget item(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? c.ink, size: 22),
        title: Text(label,
            style: TextStyle(
                color: color ?? c.ink,
                fontSize: 15.5,
                fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
    }

    void soon() {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скоро будет доступно')));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: c.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ленты',
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            item(Icons.favorite_border_rounded, 'Понравилось', soon),
            item(Icons.bookmark_border_rounded, 'Сохранённое', soon),
            item(Icons.auto_awesome_rounded, 'Для вас', () {
              Navigator.pop(context);
              _setTab(0);
            }),
            item(Icons.group_outlined, 'Подписки', () {
              Navigator.pop(context);
              _setTab(1);
            }),
            item(Icons.history_toggle_off_rounded, 'Исчезающие публикации',
                soon),
            Divider(height: 12, color: c.ink.withOpacity(0.07)),
            item(Icons.settings_outlined, 'Настройки', () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsScreen(user: widget.user)),
              );
            }),
            item(Icons.lock_outline_rounded, 'Приватность', soon),
            item(Icons.help_outline_rounded, 'Помощь', soon),
            item(Icons.logout_rounded, 'Выйти', () {
              Navigator.pop(context);
              _logout();
            }, color: c.danger),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  Widget _storiesRow(BrutalColors c) {
    final myStories = _stories
        .where(
            (s) => s['user_id'].toString() == widget.user['id'].toString())
        .toList();
    final grouped = _grouped;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            _MyStoryBtn(
              user: widget.user,
              hasStory: myStories.isNotEmpty,
              onTap: () {
                if (myStories.isEmpty) {
                  _addStory();
                } else {
                  _showStoryOptions(myStories);
                }
              },
            ),
            ...grouped.values.map((uStories) => _StoryAvatar(
                  stories: uStories,
                  onTap: () => _openStory(uStories),
                )),
          ],
        ),
      ),
    );
  }

  void _showStoryOptions(List myStories) {
    final c = context.k;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: c.ink.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 18),
          _SheetTile(
              icon: Icons.camera_alt_rounded,
              label: 'Camera',
              onTap: () {
                Navigator.pop(context);
                _addStory(source: ImageSource.camera);
              }),
          _SheetTile(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              onTap: () {
                Navigator.pop(context);
                _addStory(source: ImageSource.gallery);
              }),
          _SheetTile(
              icon: Icons.visibility_rounded,
              label: 'View my stories',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewScreen(
                      stories: myStories,
                      allGroups: [myStories],
                      groupIndex: 0,
                      startIndex: 0,
                      user: widget.user,
                      onStoryDeleted: _loadStories,
                    ),
                  ),
                );
              }),
        ]),
      ),
    );
  }

  Widget _empty(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          Icon(Icons.dynamic_feed_rounded, size: 56, color: c.inkSoft),
          const SizedBox(height: 14),
          Text(context.t('nothingYet'),
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 18, color: c.ink)),
          const SizedBox(height: 6),
          Text(context.t('beFirst'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    feedRefresh.removeListener(_onFeedRefresh);
    super.dispose();
  }
}

// ─── THREADS-STYLE POST ───────────────────────────────────────────────────────
class _ThreadsPost extends StatelessWidget {
  final Map post;
  final Map user;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onShare;
  final VoidCallback onProfileTap;
  final VoidCallback onMore;

  const _ThreadsPost({
    required this.post,
    required this.user,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onShare,
    required this.onProfileTap,
    required this.onMore,
  });

  String _time() {
    final raw = post['created_at'];
    if (raw == null) return '';
    try {
      return timeago.format(DateTime.parse(raw.toString()).toLocal(),
          locale: 'en_short');
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final username = (post['username'] ?? 'user').toString();
    final avatar = post['user_avatar'] ?? post['avatar_url'];
    final content = (post['content'] ?? '').toString();
    final image = post['image_url'];
    final liked = post['is_liked'] == true;
    final likes = (post['likes_count'] ?? 0);
    final comments = (post['comments_count'] ?? 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: c.ink.withOpacity(0.06), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + thread line ──────────────────────────────────
          Column(
            children: [
              GestureDetector(
                onTap: onProfileTap,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: c.surface2,
                  backgroundImage: avatar != null
                      ? CachedNetworkImageProvider(avatar.toString())
                      : null,
                  child: avatar == null
                      ? Text(
                          (username.isNotEmpty ? username[0] : '?')
                              .toUpperCase(),
                          style: TextStyle(
                              color: c.ink, fontWeight: FontWeight.w700))
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 2,
                height: 30,
                decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // ── Post content ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username row — time + ⋯ pinned to the top-right corner.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: onProfileTap,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            username,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: c.ink),
                          ),
                        ),
                      ),
                    ),
                    if (post['is_verified'] == true) ...[
                      const SizedBox(width: 4),
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.verified_rounded, size: 14),
                      ),
                    ],
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_time(),
                          style: TextStyle(fontSize: 12, color: c.inkSoft)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMore,
                      child: Icon(Icons.more_horiz, size: 20, color: c.inkSoft),
                    ),
                  ],
                ),

                // Content text
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: TextStyle(
                        fontSize: 15, height: 1.35, color: c.ink),
                  ),
                ],

                // Link preview (Telegram-style unfurl)
                if (image == null && firstUrl(content) != null)
                  LinkPreviewCard(url: firstUrl(content)!),

                // Image
                if (image != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: image.toString(),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          height: 200, color: c.surface2),
                    ),
                  ),
                ],

                // ── Action buttons (Threads-style) ────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _ActionIcon(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: likes > 0 ? '$likes' : '',
                        color: liked ? c.danger : c.inkSoft,
                        onTap: onLike,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.mode_comment_outlined,
                        label: comments > 0 ? '$comments' : '',
                        color: c.inkSoft,
                        onTap: onComment,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.repeat_rounded,
                        label: '',
                        color: c.inkSoft,
                        onTap: onRepost,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.send_outlined,
                        label: '',
                        color: c.inkSoft,
                        onTap: onShare,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Threads-style action icon with optional count label ─────────────────────
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionIcon(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── STORY WIDGETS ────────────────────────────────────────────────────────────
class _MyStoryBtn extends StatelessWidget {
  final Map user;
  final bool hasStory;
  final VoidCallback onTap;
  const _MyStoryBtn({
    required this.user,
    required this.hasStory,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 66,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(children: [
            _StoryRing(url: user['avatar_url'], hasStory: hasStory, size: 56),
            Positioned(
              bottom: 0,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2)),
                child: const Icon(Icons.add, size: 12, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 5),
          Text('You',
              style: TextStyle(fontSize: 11, color: c.inkSoft),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final List stories;
  final VoidCallback onTap;
  const _StoryAvatar({required this.stories, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final first = stories.first;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: SizedBox(
          width: 66,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            _StoryRing(url: first['user_avatar'], hasStory: true, size: 56),
            const SizedBox(height: 5),
            Text(first['username'] ?? 'User',
                style: TextStyle(fontSize: 11, color: c.inkSoft),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class _StoryRing extends StatelessWidget {
  final String? url;
  final bool hasStory;
  final double size;
  const _StoryRing(
      {required this.url, required this.hasStory, required this.size});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasStory ? c.storyGradient : null,
        color: hasStory ? null : c.surface2,
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.bg),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: url != null
              ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
              : Container(
                  color: c.surface2,
                  child: Icon(Icons.person_rounded, color: c.inkSoft)),
        ),
      ),
    );
  }
}

class _StoryPickerSheet extends StatelessWidget {
  final BrutalColors c;
  const _StoryPickerSheet({required this.c});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: c.ink.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        _SheetTile(
            icon: Icons.camera_alt_rounded,
            label: 'Camera',
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        _SheetTile(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SheetTile(
      {required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final tint = color ?? c.accent;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color?.withOpacity(0.12) ?? c.surface2,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              color: color ?? c.ink, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

// ─── HOME STATS FOOTER (animated donut of goal progress) ──────────────────────
class _StatsFooter extends StatefulWidget {
  final Map user;
  const _StatsFooter({required this.user});
  @override
  State<_StatsFooter> createState() => _StatsFooterState();
}

class _StatsFooterState extends State<_StatsFooter> {
  Map _w = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await ApiService.getWrapped(widget.user['id'].toString());
    if (mounted) setState(() { _w = w; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (_loading) return const SizedBox.shrink();
    final total = (_w['total'] ?? 0) as int;
    if (total == 0) return const SizedBox.shrink();
    final done = (_w['completed'] ?? 0) as int;
    final rate = (_w['completionRate'] ?? 0) as int;
    final avg = (_w['avgProgress'] ?? 0) as int;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.ink.withOpacity(0.06)),
      ),
      child: Row(children: [
        SizedBox(
          width: 84, height: 84,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: rate / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              painter: _DonutPainter(v, c.accent, c.surface2),
              child: Center(
                child: Text('${(v * 100).round()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.ink)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Твой прогресс за год',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: c.ink)),
              const SizedBox(height: 10),
              _statRow(c, 'Целей выполнено', '$done из $total'),
              _statRow(c, 'Средний прогресс', '$avg%'),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statRow(BrutalColors c, String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l, style: TextStyle(color: c.inkSoft, fontSize: 13)),
              Text(v,
                  style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
      );
}

class _DonutPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color bg;
  _DonutPainter(this.value, this.color, this.bg);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final bgPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, bgPaint);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value.clamp(0, 1), false,
        fgPaint);
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.value != value;
}
