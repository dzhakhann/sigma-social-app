import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/brutal.dart';
import 'onboarding_screen.dart';
import 'story_view_screen.dart';
import 'chat_detail_screen.dart';
import '../widgets/link_preview.dart';
import '../services/session.dart';
import '../services/events.dart';

class ProfileScreen extends StatefulWidget {
  final Map user;
  final String? targetUserId;
  final bool isOwnProfile;
  const ProfileScreen(
      {Key? key,
      required this.user,
      this.targetUserId,
      this.isOwnProfile = true})
      : super(key: key);
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map userProfile = {};
  List userPosts = [];
  List userStories = [];
  bool isLoading = false;
  bool isFollowing = false;
  bool isUploadingAvatar = false;
  int _tab = 0; // 0 = posts, 1 = stories/history

  String get _targetId =>
      widget.isOwnProfile ? widget.user['id'].toString() : widget.targetUserId!;

  Set<String> get _hidden {
    final hf = userProfile['hidden_fields'];
    return hf is List ? hf.map((e) => e.toString()).toSet() : <String>{};
  }

  @override
  void initState() {
    super.initState();
    userProfile = widget.isOwnProfile ? Map.from(widget.user) : {};
    _loadProfile();
    _loadPosts();
    _loadStories();
    if (!widget.isOwnProfile) _checkFollow();
  }

  Future<void> _loadProfile() async {
    final data = await ApiService.getUser(_targetId);
    if (data['success'] == true && mounted) {
      setState(() => userProfile = data['data']);
    }
  }

  Future<void> _loadPosts() async {
    setState(() => isLoading = true);
    // Includes reposts (they only show here, not in the feed).
    final list = await ApiService.getUserPosts(
        _targetId.toString(), widget.user['id'].toString());
    if (mounted) {
      setState(() {
        userPosts = list;
        isLoading = false;
      });
    }
  }

  Future<void> _loadStories() async {
    final s = await ApiService.getUserStories(_targetId);
    if (mounted) setState(() => userStories = s);
  }

  Future<void> _checkFollow() async {
    final result = await ApiService.isFollowing(
        widget.user['id'].toString(), widget.targetUserId!);
    if (mounted) setState(() => isFollowing = result);
  }

  Future<void> _toggleFollow() async {
    final fn = isFollowing ? ApiService.unfollow : ApiService.follow;
    final data =
        await fn(widget.user['id'].toString(), widget.targetUserId!);
    if (data['success'] == true && mounted) {
      setState(() {
        isFollowing = !isFollowing;
        userProfile['followers_count'] = isFollowing
            ? (userProfile['followers_count'] ?? 0) + 1
            : ((userProfile['followers_count'] ?? 1) - 1).clamp(0, 99999);
      });
    }
  }

  Future<void> _editProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OnboardingScreen(user: Map.from(userProfile), editMode: true),
      ),
    );
    if (changed == true) {
      await _loadProfile();
      if (widget.isOwnProfile) {
        // Keep the shared user + persisted session in sync so the new data
        // shows everywhere and survives a restart.
        widget.user.addAll(userProfile);
        await Session.patch(userProfile);
        feedRefresh.value++;
      }
    }
  }

  Future<void> _openChat() async {
    final r = await ApiService.getOrCreateChat(
        widget.user['id'].toString(), _targetId);
    if (r['success'] == true && r['data'] != null && mounted) {
      final chat = Map.from(r['data']);
      chat['name'] = userProfile['username'] ?? 'Чат';
      chat['avatar'] = userProfile['avatar_url'];
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatDetailScreen(chat: chat, user: widget.user)),
      );
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (file == null) return;
    setState(() => isUploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final uploaded = await ApiService.uploadMedia(bytes,
          folder: 'avatar',
          ext: 'jpg',
          contentType: 'image/jpeg',
          userId: widget.user['id'].toString());
      if (uploaded != null) {
        final url = '$uploaded?t=${DateTime.now().millisecondsSinceEpoch}';
        await ApiService.updateUser(widget.user['id'].toString(), {'avatar_url': url});
        widget.user['avatar_url'] = url; // shared user (used across tabs)
        await Session.patch({'avatar_url': url}); // survive restart
        feedRefresh.value++; // refresh Home (story avatar, etc.)
        if (mounted) setState(() => userProfile['avatar_url'] = url);
      }
    } catch (_) {}
    if (mounted) setState(() => isUploadingAvatar = false);
  }

  String _fullName() {
    final parts = [
      userProfile['first_name'],
      userProfile['last_name'],
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).map((e) => e.toString());
    return parts.join(' ').trim();
  }

  // Whether a field should be shown to the current viewer.
  bool _visible(String key) {
    if (widget.isOwnProfile) return true; // owner sees everything
    return !_hidden.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          if (widget.isOwnProfile)
            IconButton(
              icon: Icon(Icons.edit_rounded, color: c.ink),
              onPressed: _editProfile,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadProfile();
          await _loadPosts();
          await _loadStories();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _headerCard(c),
            const SizedBox(height: 14),
            if (_aboutVisible(c)) ...[_aboutCard(c), const SizedBox(height: 14)],
            if (_detailsVisible()) ...[_detailsCard(c), const SizedBox(height: 14)],
            _tabBar(c),
            const SizedBox(height: 12),
            if (_tab == 2) _storiesTab(c) else _postsTab(c, reposts: _tab == 1),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────
  Widget _headerCard(BrutalColors c) {
    final avatarUrl = userProfile['avatar_url'];
    final full = _fullName();
    final showName = full.isNotEmpty && _visible('name');
    final title = showName ? full : (userProfile['username'] ?? 'User').toString();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cleanCard(c, radius: 18),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.isOwnProfile ? _pickAvatar : null,
            child: Stack(
              children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    gradient: avatarUrl == null ? c.buttonGradient : null,
                    shape: BoxShape.circle,
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(avatarUrl),
                            fit: BoxFit.cover)
                        : null,
                    border: Border.all(color: c.ink.withOpacity(0.08), width: 2),
                  ),
                  child: avatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 46, color: Colors.white)
                      : null,
                ),
                if (widget.isOwnProfile)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: c.accent, shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                      child: isUploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_rounded,
                              size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, color: c.ink)),
              ),
              if (userProfile['is_verified'] == true) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified_rounded, size: 20, color: c.ink),
              ],
              if (userProfile['is_pro'] == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: c.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('PRO',
                      style: TextStyle(
                          color: c.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
          if (showName)
            Text('@${userProfile['username'] ?? ''}',
                style: TextStyle(color: c.inkSoft, fontSize: 13)),
          if ((userProfile['headline'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(userProfile['headline'],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: c.inkSoft, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(c, '${userProfile['goals_count'] ?? 0}', 'Цели'),
              _stat(c, '${userProfile['followers_count'] ?? 0}', 'Подписчики'),
              _stat(c,
                  '${userProfile['posts_count'] ?? userPosts.length}', 'Посты'),
              _stat(c, '${userProfile['following_count'] ?? 0}', 'Подписки'),
            ],
          ),
          if (!widget.isOwnProfile) ...[
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: _actionBtn(c,
                    label: isFollowing ? 'В друзьях' : 'Добавить',
                    filled: !isFollowing, onTap: _toggleFollow),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(c,
                    label: 'Написать', filled: false, onTap: _openChat),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  bool _aboutVisible(BrutalColors c) {
    final about = (userProfile['about'] ?? '').toString().trim();
    return about.isNotEmpty && _visible('about');
  }

  Widget _aboutCard(BrutalColors c) => BrutalCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(c, 'О себе'),
            const SizedBox(height: 10),
            Text(userProfile['about'].toString(),
                style: TextStyle(color: c.ink, fontSize: 14, height: 1.5)),
          ],
        ),
      );

  // ─── DETAILS ─────────────────────────────────────────────────────────────────
  List<List<dynamic>> get _detailDefs => [
        ['work', Icons.work_outline_rounded, userProfile['work']],
        ['education', Icons.school_outlined, userProfile['education']],
        ['birthplace', Icons.public_rounded, userProfile['birthplace']],
        ['birthday', Icons.cake_outlined, userProfile['birthday']],
        ['gender', Icons.wc_rounded, userProfile['gender']],
        ['relationship', Icons.favorite_border_rounded, userProfile['relationship']],
        ['location', Icons.location_on_outlined, userProfile['location']],
        ['skills', Icons.stars_rounded, userProfile['skills']],
        ['website', Icons.link_rounded, userProfile['website']],
      ];

  bool _detailsVisible() {
    for (final d in _detailDefs) {
      final key = d[0] as String;
      final val = (d[2] ?? '').toString().trim();
      if (val.isNotEmpty && _visible(key)) return true;
    }
    return false;
  }

  Widget _detailsCard(BrutalColors c) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(c, 'Информация'),
          const SizedBox(height: 12),
          ..._detailDefs.map((d) {
            final key = d[0] as String;
            final icon = d[1] as IconData;
            final val = (d[2] ?? '').toString().trim();
            if (val.isEmpty) return const SizedBox.shrink();
            if (!widget.isOwnProfile && _hidden.contains(key)) {
              return const SizedBox.shrink();
            }
            final hiddenForOwner = widget.isOwnProfile && _hidden.contains(key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(icon, size: 18, color: c.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(val,
                      style: TextStyle(color: c.ink, fontSize: 14)),
                ),
                if (hiddenForOwner)
                  Icon(Icons.visibility_off_rounded, size: 15, color: c.inkSoft),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ─── TABS ─────────────────────────────────────────────────────────────────────
  Widget _tabBar(BrutalColors c) {
    Widget btn(int i, String label, IconData icon) {
      final sel = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: sel ? c.accent.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: sel ? c.accent : c.inkSoft),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: sel ? c.ink : c.inkSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        btn(0, 'Посты', Icons.grid_view_rounded),
        btn(1, 'Репосты', Icons.repeat_rounded),
        btn(2, 'История', Icons.auto_stories_rounded),
      ]),
    );
  }

  bool _isRepost(Map p) =>
      p['repost_of'] != null ||
      (p['content'] ?? '').toString().trimLeft().startsWith('🔁');

  Widget _postsTab(BrutalColors c, {bool reposts = false}) {
    if (isLoading) {
      return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: c.accent)));
    }
    final list = userPosts.where((p) => _isRepost(p) == reposts).toList();
    if (list.isEmpty) {
      return _emptyBox(
          c,
          reposts ? Icons.repeat_rounded : Icons.article_outlined,
          reposts ? 'Пока нет репостов' : 'Пока нет публикаций');
    }
    return Column(
      children: list.map((post) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: c.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isRepost(post)) ...[
                  Row(children: [
                    Icon(Icons.repeat_rounded, size: 14, color: c.accent),
                    const SizedBox(width: 6),
                    Text(
                        'Репост${post['repost_username'] != null ? ' из @${post['repost_username']}' : ''}',
                        style: TextStyle(
                            color: c.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                ],
                if ((post['content'] ?? '').toString().isNotEmpty)
                  Text(post['content'],
                      style: TextStyle(fontSize: 15, color: c.ink)),
                if ((post['image_url'] ?? '').toString().isEmpty &&
                    firstUrl((post['content'] ?? '').toString()) != null)
                  LinkPreviewCard(
                      url: firstUrl((post['content'] ?? '').toString())!),
                if ((post['image_url'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                        imageUrl: post['image_url'], fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.favorite_rounded, size: 14, color: c.danger),
                  const SizedBox(width: 5),
                  Text('${post['likes_count'] ?? 0}',
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ]),
              ],
            ),
          )).toList(),
    );
  }

  Widget _storiesTab(BrutalColors c) {
    if (userStories.isEmpty) {
      return _emptyBox(c, Icons.auto_stories_outlined,
          widget.isOwnProfile
              ? 'Твои прошлые истории будут храниться здесь'
              : 'Нет историй');
    }
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: userStories.map((s) {
        final url = (s['image_url'] ?? '').toString();
        return GestureDetector(
          onTap: () => _viewStory(s),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: (MediaQuery.of(context).size.width - 32 - 16) / 3,
              height: 150,
              child: url.isEmpty
                  ? Container(color: c.surface2)
                  : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _viewStory(Map s) {
    final start = userStories.indexOf(s);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewScreen(
          stories: userStories,
          allGroups: [userStories],
          groupIndex: 0,
          startIndex: start < 0 ? 0 : start,
          user: widget.user,
          onStoryDeleted: _loadStories,
        ),
      ),
    );
  }

  // ─── small pieces ───────────────────────────────────────────────────────────
  Widget _emptyBox(BrutalColors c, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Icon(icon, size: 46, color: c.inkSoft),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: c.inkSoft, fontSize: 14)),
        ]),
      );

  Widget _sectionTitle(BrutalColors c, String t) => Text(t,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink));

  Widget _stat(BrutalColors c, String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 10.5)),
        ]),
      );

  Widget _actionBtn(BrutalColors c,
      {required String label, required bool filled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(13),
          border: filled ? null : Border.all(color: c.ink.withOpacity(0.1)),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? c.onAccent : c.ink,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
  }
}
