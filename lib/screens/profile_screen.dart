import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import 'onboarding_screen.dart';
import 'story_view_screen.dart';
import 'chat_detail_screen.dart';
import 'profile_share_screen.dart';
import 'photo_view_screen.dart';
import 'avatar_crop_screen.dart';
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

  Map _analytics = {};

  Future<void> _loadProfile() async {
    final data = await ApiService.getUser(_targetId);
    if (data['success'] == true && mounted) {
      setState(() => userProfile = data['data']);
    }
    if (widget.isOwnProfile) {
      // Own profile → load the mini-analytics card.
      final a = await ApiService.myAnalytics();
      if (mounted) setState(() => _analytics = a);
    } else {
      // Someone else's profile → count the visit (unique per visitor).
      ApiService.visitProfile(_targetId.toString());
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
      chat['name'] = userProfile['username'] ?? context.t('chatFallback');
      chat['avatar'] = userProfile['avatar_url'];
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatDetailScreen(chat: chat, user: widget.user)),
      );
    }
  }

  // Telegram logic: the camera badge goes STRAIGHT to the gallery (no menu),
  // then into the crop editor. The full menu lives on long-press instead.
  Future<void> _pickAvatar() => _pickAvatarFrom('gallery');

  // Long-press on the avatar → full menu (view / take photo / gallery / remove).
  Future<void> _avatarMenu() async {
    final c = context.k;
    final hasPhoto = (userProfile['avatar_url'] ?? '').toString().isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.camera_alt_rounded, color: c.accent),
            ),
            title: Text(ctx.t('takePhoto'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.photo_library_rounded, color: c.accent),
            ),
            title: Text(ctx.t('chooseFromGallery'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: c.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.delete_outline_rounded, color: c.danger),
              ),
              title: Text(ctx.t('removePhoto'),
                  style:
                      TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.close_rounded, color: c.inkSoft),
            ),
            title: Text(ctx.t('cancelBtn'),
                style: TextStyle(color: c.inkSoft)),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      await _removeAvatar();
      return;
    }
    await _pickAvatarFrom(choice);
  }

  Future<void> _removeAvatar() async {
    setState(() => isUploadingAvatar = true);
    await ApiService.updateUser(
        widget.user['id'].toString(), {'avatar_url': null});
    widget.user['avatar_url'] = null;
    await Session.patch({'avatar_url': null});
    feedRefresh.value++;
    if (mounted) {
      setState(() {
        userProfile['avatar_url'] = null;
        isUploadingAvatar = false;
      });
    }
  }

  Future<void> _pickAvatarFrom(String source) async {
    final picker = ImagePicker();
    // Pick at high resolution — the crop editor decides the visible square.
    final file = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 90);
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (!mounted) return;
    // Telegram-style crop: pan + pinch under a circular window → square crop.
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AvatarCropScreen(imageBytes: raw)),
    );
    if (bytes == null) return;
    setState(() => isUploadingAvatar = true);
    try {
      final uploaded = await ApiService.uploadMedia(bytes,
          folder: 'avatar',
          ext: 'png',
          contentType: 'image/png',
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
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadProfile();
          await _loadPosts();
          await _loadStories();
        },
        child: CustomScrollView(
          // Bouncing physics enables the Telegram-style stretch of the header
          // (round avatar morphs into a full-width square photo on pull-down).
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _sliverHeader(c),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  _statsAndActions(c),
                  _analyticsCard(c),
                ]),
              ),
            ),
            if (_aboutVisible(c))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _aboutCard(c),
                ),
              ),
            if (_detailsVisible())
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _detailsCard(c),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _tabBar(c),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                child: _tab == 2
                    ? _storiesTab(c)
                    : _postsTab(c, reposts: _tab == 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Collapsing header (Telegram-style) ──────────────────────────────────────
  // Default: round avatar centered + name below (like Telegram at rest).
  // Pull DOWN: the round avatar smoothly morphs into a full-width square
  // photo with the name overlaid bottom-left. Scroll UP: shrinks into the
  // toolbar with a small round avatar.
  Widget _sliverHeader(BrutalColors c) {
    final avatarUrl = userProfile['avatar_url'];
    final full = _fullName();
    final showName = full.isNotEmpty && _visible('name');
    final title =
        showName ? full : (userProfile['username'] ?? 'User').toString();
    final topPad = MediaQuery.of(context).padding.top;
    const expanded = 290.0;
    final hasPhoto = avatarUrl != null;

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: expanded,
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: !widget.isOwnProfile,
      iconTheme: IconThemeData(color: c.ink),
      actions: [
        if (widget.isOwnProfile) ...[
          IconButton(
            tooltip: context.t('profileShareTitle'),
            icon: Icon(Icons.qr_code_scanner_rounded, color: c.ink),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ProfileShareScreen(user: widget.user)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_rounded, color: c.ink),
            onPressed: _editProfile,
          ),
        ],
      ],
      flexibleSpace: LayoutBuilder(
        builder: (ctx, cons) {
          final w = cons.biggest.width;
          final h = cons.biggest.height;
          final maxH = expanded + topPad;
          final minH = kToolbarHeight + topPad;
          final t = ((h - minH) / (maxH - minH)).clamp(0.0, 1.0);
          final e = Curves.easeOut.transform(t);
          // Stretch factor: 0 at rest → 1 when pulled ~150px past the top.
          final s = h <= maxH ? 0.0 : ((h - maxH) / 150).clamp(0.0, 1.0);

          // Morphing avatar geometry (round → full-bleed square).
          final d = 44.0 + 62.0 * t; // round diameter at current collapse
          final avW = d + (w - d) * s;
          final avH = d + (h - d) * s;
          final avLeft = ((w - d) / 2) * (1 - s);
          final avTop = (topPad + 34) * (1 - s);
          final radius = (d / 2) * (1 - s);

          return Stack(fit: StackFit.expand, children: [
            // ── The morphing avatar itself ───────────────────────────────
            Positioned(
              left: avLeft,
              top: avTop,
              width: avW,
              height: avH,
              child: IgnorePointer(
                ignoring: t < 0.35,
                child: Opacity(
                  opacity: e,
                  child: GestureDetector(
                    onTap: () {
                      if (hasPhoto) {
                        Navigator.push(
                            context,
                            PhotoViewScreen.route(avatarUrl.toString(),
                                heroTag: avatarUrl.toString()));
                      } else if (widget.isOwnProfile) {
                        _pickAvatar();
                      }
                    },
                    // Telegram: long-press the photo → full avatar menu.
                    onLongPress:
                        widget.isOwnProfile ? _avatarMenu : null,
                    child: Hero(
                      tag: avatarUrl?.toString() ?? 'avatar_$_targetId',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: hasPhoto
                            ? CachedNetworkImage(
                                imageUrl: avatarUrl.toString(),
                                fit: BoxFit.cover)
                            : Container(
                                decoration: BoxDecoration(
                                    gradient: c.buttonGradient),
                                child: Icon(Icons.person_rounded,
                                    size: 40 + 40 * s,
                                    color:
                                        Colors.white.withOpacity(0.9)),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Camera badge on the round avatar (own profile, at rest) ──
            if (widget.isOwnProfile && s < 0.2)
              Positioned(
                left: (w + d) / 2 - 30,
                top: avTop + d - 30,
                child: IgnorePointer(
                  ignoring: t < 0.35,
                  child: Opacity(
                    opacity: e * (1 - s * 5).clamp(0.0, 1.0),
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: c.accent, shape: BoxShape.circle,
                          border: Border.all(color: c.bg, width: 2),
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
                  ),
                ),
              ),
            // ── Name below the round avatar (fades out on stretch) ──────
            Positioned(
              top: topPad + 34 + d + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (e * (1 - s * 1.6)).clamp(0.0, 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _nameRow(c, title, center: true),
                      if (showName)
                        Text('@${userProfile['username'] ?? ''}',
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 13)),
                      if ((userProfile['headline'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(userProfile['headline'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                color: c.inkSoft,
                                fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // ── Stretched state: gradient + name over the photo ─────────
            if (s > 0) ...[
              Positioned(
                left: 0, right: 0, bottom: 0, height: 130,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: s,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: s,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _nameRow(c, title, onPhoto: true),
                        if (showName)
                          Text('@${userProfile['username'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            // ── Collapsed: small round avatar + name in the toolbar ─────
            Positioned(
              top: topPad,
              height: kToolbarHeight,
              left: widget.isOwnProfile ? 16 : 52,
              right: widget.isOwnProfile ? 100 : 16,
              child: IgnorePointer(
                ignoring: e > 0.5,
                child: Opacity(
                  opacity: 1 - e,
                  child: Row(children: [
                    _bigAvatar(c, avatarUrl, 34, tappable: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _bigAvatar(BrutalColors c, dynamic avatarUrl, double size,
      {bool tappable = true}) {
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: avatarUrl == null ? c.buttonGradient : null,
        shape: BoxShape.circle,
        image: avatarUrl != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(avatarUrl.toString()),
                fit: BoxFit.cover)
            : null,
        border: Border.all(color: c.ink.withOpacity(0.08), width: 2),
      ),
      child: avatarUrl == null
          ? Icon(Icons.person_rounded, size: size * 0.5, color: Colors.white)
          : null,
    );
    // Only the big (tappable) avatar is a Hero — avoids duplicate-tag errors.
    if (!tappable) return circle;
    final avatar =
        Hero(tag: avatarUrl ?? 'avatar_$_targetId', child: circle);
    return Stack(children: [
      GestureDetector(
        onTap: () {
          if (avatarUrl != null) {
            Navigator.push(context,
                PhotoViewScreen.route(avatarUrl.toString(), heroTag: avatarUrl.toString()));
          } else if (widget.isOwnProfile) {
            _pickAvatar();
          }
        },
        child: avatar,
      ),
      if (widget.isOwnProfile)
        Positioned(
          bottom: 0, right: 0,
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: c.accent, shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: 2),
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
        ),
    ]);
  }

  Widget _nameRow(BrutalColors c, String title,
      {bool center = false, bool onPhoto = false}) {
    final nameColor = onPhoto ? Colors.white : c.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: nameColor,
                  shadows: onPhoto
                      ? const [Shadow(blurRadius: 8, color: Colors.black54)]
                      : null)),
        ),
        if (userProfile['is_verified'] == true) ...[
          const SizedBox(width: 6),
          Icon(Icons.verified_rounded, size: 20, color: nameColor),
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
        const SizedBox(width: 6),
        _auraBadge(c),
      ],
    );
  }

  Widget _auraBadge(BrutalColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c.accent3.withOpacity(0.9), c.accent.withOpacity(0.9)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('✦', style: TextStyle(color: Colors.white, fontSize: 11)),
        const SizedBox(width: 3),
        Text(_fmtAura(userProfile['aura']),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // Mini-analytics for the owner: visits, likes, story views, reach.
  Widget _analyticsCard(BrutalColors c) {
    if (!widget.isOwnProfile || _analytics.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget cell(IconData icon, String n, String label) => Expanded(
          child: Column(children: [
            Icon(icon, size: 18, color: c.accent),
            const SizedBox(height: 4),
            Text(n,
                style: TextStyle(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, fontSize: 10.5)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: cleanCard(c, radius: 18),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 8),
          Icon(Icons.insights_rounded, size: 16, color: c.inkSoft),
          const SizedBox(width: 6),
          Text(context.t('analyticsTitle'),
              style: TextStyle(
                  color: c.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          cell(Icons.person_search_rounded,
              '${_analytics['profile_visits'] ?? 0}', context.t('aVisits')),
          cell(Icons.favorite_rounded, '${_analytics['post_likes'] ?? 0}',
              context.t('aPostLikes')),
          cell(Icons.chat_bubble_outline_rounded,
              '${_analytics['comments'] ?? 0}', context.t('aComments')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          cell(Icons.visibility_rounded,
              '${_analytics['story_views'] ?? 0}', context.t('aStoryViews')),
          cell(Icons.favorite_border_rounded,
              '${_analytics['story_likes'] ?? 0}', context.t('aStoryLikes')),
          cell(Icons.trending_up_rounded, '${_analytics['reach'] ?? 0}',
              context.t('aReach')),
        ]),
      ]),
    );
  }

  Widget _statsAndActions(BrutalColors c) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: cleanCard(c, radius: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat(c, '${userProfile['followers_count'] ?? 0}',
                context.t('followers')),
            _stat(c, '${userProfile['posts_count'] ?? userPosts.length}',
                context.t('postsLbl')),
            _stat(c, '${userProfile['following_count'] ?? 0}',
                context.t('following')),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _goalsProgressCard(c),
      if (!widget.isOwnProfile) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _actionBtn(c,
                label:
                    isFollowing ? context.t('friends') : context.t('addFriend'),
                filled: !isFollowing, onTap: _toggleFollow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionBtn(c,
                label: context.t('messageBtn'), filled: false, onTap: _openChat),
          ),
        ]),
      ],
    ]);
  }

  String _fmtAura(dynamic v) {
    final n = (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    if (n > 99999) return '99 999+';
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  // Goals progress card: others see how many goals & % done, but NOT the titles.
  Widget _goalsProgressCard(BrutalColors c) {
    final total = (userProfile['goals_count'] ?? 0) as int;
    final done = (userProfile['goals_done_count'] ?? 0) as int;
    if (total == 0) return const SizedBox.shrink();
    final pct = ((done / total) * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cleanCard(c, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.flag_rounded, size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text(context.t('goalsYear'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            Text('$done ${context.t('ofWord')} $total',
                style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (done / total).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: c.ink.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text('$pct% ${context.t('completed')} · ${context.t('goalsHidden')}',
              style: TextStyle(color: c.inkSoft, fontSize: 12)),
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
            _sectionTitle(c, context.t('aboutMe')),
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
          _sectionTitle(c, context.t('info')),
          const SizedBox(height: 12),
          ..._detailDefs.map((d) {
            final key = d[0] as String;
            final icon = d[1] as IconData;
            var val = (d[2] ?? '').toString().trim();
            // Gender / relationship are stored canonically — translate here.
            if (key == 'gender' || key == 'relationship') {
              val = localizedProfileValue(context, val);
            }
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
        btn(0, context.t('tabPosts'), Icons.grid_view_rounded),
        btn(1, context.t('tabReposts'), Icons.repeat_rounded),
        btn(2, context.t('tabStories'), Icons.auto_stories_rounded),
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
          reposts ? context.t('noReposts') : context.t('noPostsYet'));
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
                        '${context.t('repostFrom')}${post['repost_username'] != null ? ' · @${post['repost_username']}' : ''}',
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
              ? context.t('storiesArchiveHint')
              : context.t('noStories'));
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
