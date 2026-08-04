import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'sigma_gallery_screen.dart';
import 'comments_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/pro_state.dart';
import '../theme/brutal_theme.dart';
import '../widgets/verified_badge.dart';
import '../widgets/pro_badge_picker.dart';
import '../widgets/pro_badge.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import '../widgets/action_menu.dart';
import 'onboarding_screen.dart';
import 'story_view_screen.dart';
import 'chat_detail_screen.dart';
import 'profile_share_screen.dart';
import 'photo_view_screen.dart';
import 'avatar_crop_screen.dart';
import '../widgets/fav_track.dart';
import '../widgets/music_widgets.dart';
import '../widgets/link_preview.dart';
import 'media_picker_sheet.dart';
import 'follow_list_screen.dart';
import '../widgets/post_media_carousel.dart';
import '../services/session.dart';
import '../services/events.dart';
import '../services/profile_background.dart';
import '../widgets/pro_upsell_sheet.dart';
import '../widgets/profile_background_view.dart';

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
  int _tab = 0; // 0 = posts, 1 = reposts, 2 = stories/history

  /// Which way the last tab change went, so the slide matches the gesture.
  bool _tabForward = true;

  String get _targetId =>
      widget.isOwnProfile ? widget.user['id'].toString() : widget.targetUserId!;

  Set<String> get _hidden {
    final hf = userProfile['hidden_fields'];
    return hf is List ? hf.map((e) => e.toString()).toSet() : <String>{};
  }

  // Telegram-style pull-down morph: the overscroll distance in pixels drives
  // the round→square avatar animation directly (finger == animation).
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<double> _stretchPx = ValueNotifier(0);

  // Telegram doesn't spring the expanded photo back on release — it stays
  // square until you scroll it away yourself. A plain overscroll->px mapping
  // always reverts because BouncingScrollPhysics settles the offset back to
  // 0, so a deliberate pull past half (committed on release, like a
  // pull-to-refresh threshold) latches this, and _onScroll's unlock ramp
  // below un-morphs it proportionally to the user's own next scroll instead.
  bool _avatarLocked = false;
  // Was the last scroll notification driven by an actual finger drag?
  // ScrollEndNotification is NOT the release moment here — for
  // BouncingScrollPhysics it only fires once the position goes fully idle,
  // which is AFTER the ballistic settle-back animation finishes (offset
  // already decayed to ~0). The true "finger just lifted" instant is the
  // update where dragDetails flips from present to null.
  bool _wasDragging = false;

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    final live = offset < 0 ? (-offset).clamp(0.0, 200.0) : 0.0;
    var v = live;
    if (_avatarLocked) {
      // Ramps 120->0 as the user scrolls forward from the top; clamped at
      // 120 for any offset<=0, so it holds firm through the bounce-back
      // settle instead of dipping with it.
      final unlockRamp = (120.0 - offset).clamp(0.0, 120.0);
      v = live > unlockRamp ? live : unlockRamp;
      if (unlockRamp <= 0) _avatarLocked = false;
    }
    if (v != _stretchPx.value) _stretchPx.value = v;
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    userProfile = widget.isOwnProfile ? Map.from(widget.user) : {};
    _loadProfile();
    _loadPosts();
    _loadStories();
    if (!widget.isOwnProfile) {
      _checkFollow();
      _checkBlock();
    }
  }

  // Block state gates the whole profile (Instagram "profile unavailable").
  bool _iBlocked = false;
  bool _blockedByThem = false;

  Future<void> _checkBlock() async {
    final r = await ApiService.blockStatus(_targetId.toString());
    if (mounted) {
      setState(() {
        _iBlocked = r['i_blocked'] == true;
        _blockedByThem = r['blocked_me'] == true;
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _stretchPx.dispose();
    super.dispose();
  }

  Map _analytics = {};

  Future<void> _loadProfile() async {
    final data = await ApiService.getUser(_targetId);
    if (data['success'] == true && mounted) {
      setState(() => userProfile = data['data']);
      // The server is the authority on Pro. Syncing here keeps entitlement
      // honest in both directions: a subscription that lapsed elsewhere drops
      // the Premium theme, and one granted elsewhere unlocks it.
      if (widget.isOwnProfile) {
        final pro = data['data']['is_pro'] == true;
        ProState.set(pro);
        Session.patch({'is_pro': pro});
      }
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
    // Story rows carry no author identity — stamp it so the viewer header shows
    // the real @username / avatar instead of the "User" fallback.
    final name = (userProfile['username'] ?? widget.user['username'])?.toString();
    final avatar =
        (userProfile['avatar_url'] ?? widget.user['avatar_url'])?.toString();
    for (final st in s) {
      if (st is Map) {
        st['username'] ??= name;
        st['user_avatar'] ??= avatar;
      }
    }
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
    Map r;
    try {
      r = await ApiService.getOrCreateChat(
          widget.user['id'].toString(), _targetId);
    } catch (_) {
      r = {'success': false};
    }
    if (!mounted) return;
    if (r['success'] == true && r['data'] != null) {
      final chat = Map.from(r['data']);
      chat['name'] = userProfile['username'] ?? context.t('chatFallback');
      chat['avatar'] = userProfile['avatar_url'];
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatDetailScreen(chat: chat, user: widget.user)),
      );
    } else {
      // Was a silent dead-end (e.g. the account no longer exists / network
      // hiccup) — always tell the user WHY nothing opened.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              (r['error'] ?? '').toString().isNotEmpty
                  ? r['error'].toString()
                  : context.t('chatOpenFailed'))));
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
    Uint8List? raw;
    if (source == 'camera') {
      final picker = ImagePicker();
      // Pick at high resolution — the crop editor decides the visible square.
      final file = await picker.pickImage(
          source: ImageSource.camera, maxWidth: 2000, imageQuality: 90);
      if (file != null) raw = await file.readAsBytes();
    } else {
      // Sigmacta's own gallery instead of the system picker.
      final picked = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
            builder: (_) => const SigmaGalleryScreen(type: RequestType.image)),
      );
      if (picked is Uint8List) {
        raw = picked;
      } else if (picked is List<Uint8List> && picked.isNotEmpty) {
        raw = picked.first; // web: bytes read already, no dart:io File
      } else if (picked is List<File> && picked.isNotEmpty) {
        raw = await picked.first.readAsBytes();
      }
    }
    if (raw == null || !mounted) return;
    final Uint8List cropSrc = raw; // stable non-null capture for the builder
    // Telegram-style crop: pan + pinch under a circular window → square crop.
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AvatarCropScreen(imageBytes: cropSrc)),
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

  Widget _blockedPage(BrutalColors c) {
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: c.ink),
        actions: [
          // Blocker can unblock from here.
          if (_iBlocked)
            TextButton(
              onPressed: () async {
                await ApiService.unblockUser(_targetId.toString());
                _checkBlock();
              },
              child: Text(context.t('mUnblock'),
                  style: TextStyle(color: c.accent)),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_person_rounded, size: 64, color: c.inkSoft),
              const SizedBox(height: 18),
              Text(context.t('profileUnavailable'),
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(context.t('userBlockedYou'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  // Whether a field should be shown to the current viewer.
  bool _visible(String key) {
    if (widget.isOwnProfile) return true; // owner sees everything
    return !_hidden.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    // Instagram-style gate: if either side blocked, show an "unavailable" page.
    if (!widget.isOwnProfile && (_iBlocked || _blockedByThem)) {
      return _blockedPage(c);
    }
    return Scaffold(
      backgroundColor: c.bg,
      // No RefreshIndicator here: it would swallow the overscroll gesture that
      // drives the Telegram-style avatar morph. A deep pull (stretch trigger)
      // refreshes the profile instead.
      body: ProfileBackgroundView(
        preset: _bg,
        child: NotificationListener<ScrollNotification>(
        // Commit the expanded photo on RELEASE past half-pulled, same idea as
        // a pull-to-refresh threshold — not while still dragging, so pulling
        // partway then retreating before letting go doesn't latch it. Caught
        // via the drag->ballistic transition (see _wasDragging above), NOT
        // ScrollEndNotification, which fires too late to see the peak pull.
        onNotification: (n) {
          if (n is ScrollUpdateNotification) {
            final dragging = n.dragDetails != null;
            if (_wasDragging &&
                !dragging &&
                !_avatarLocked &&
                _stretchPx.value > 60) {
              _avatarLocked = true;
              _onScroll();
            }
            _wasDragging = dragging;
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollCtrl,
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
                  _favTrackSection(c),
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
                // Swipeable, but NOT a PageView: this lives inside a
                // CustomScrollView sliver, so it has unbounded height, and a
                // PageView would need a fixed one — the three tabs are grids of
                // very different lengths. A horizontal drag plus an animated
                // slide gives the same gesture without constraining height, and
                // horizontal drags don't compete with the vertical scroll.
                child: GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    // Ignore lazy drags so a slightly-off vertical scroll can't
                    // flip the tab.
                    if (v.abs() < 120) return;
                    final next = v < 0 ? _tab + 1 : _tab - 1;
                    if (next < 0 || next > 2) return;
                    setState(() {
                      _tabForward = v < 0;
                      _tab = next;
                    });
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    // Slides in from whichever side the gesture came from, so
                    // the motion matches the finger instead of always going one
                    // way.
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(_tabForward ? 0.12 : -0.12, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: _tab == 2
                          ? _storiesTab(c)
                          : _postsTab(c, reposts: _tab == 1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    // Fully expanded height must equal the (capped) square width so the
    // pulled-open photo is a true square — a fixed 290 constant left it a
    // visibly non-square rectangle on typical 360-430dp phone widths,
    // invisible before only because the bounce-back always sprang it shut
    // before anyone could see it held open.
    //
    // Capped at 480: the web build has no max-width wrapper, so on a wide
    // desktop browser MediaQuery's width is the full window (1700px+, easily
    // more than the viewport is ever tall). Using that raw width demanded an
    // equally enormous header height the viewport could never reach, so `t`
    // below stayed stuck near 0 — and since the name row's opacity is
    // derived from `t`, the name was invisible on every desktop load, not
    // just mid-gesture.
    final rawWidth = MediaQuery.of(context).size.width;
    final squareSize = rawWidth < 480.0 ? rawWidth : 480.0;
    final expanded = squareSize - topPad;
    final hasPhoto = avatarUrl != null;

    return SliverAppBar(
      pinned: true,
      stretch: true,
      // Deep pull (past the morph) refreshes the profile — replaces the old
      // RefreshIndicator, which used to swallow the overscroll gesture.
      onStretchTrigger: () async {
        await _loadProfile();
        await _loadPosts();
        await _loadStories();
      },
      expandedHeight: expanded,
      // Transparent so ProfileBackgroundView's animated layer (wrapping the
      // whole scaffold body) shows through the header too, collapsed toolbar
      // included — a solid bar there would hide it exactly where it's most
      // visible.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: !widget.isOwnProfile,
      iconTheme: IconThemeData(color: c.ink),
      actions: [
        if (widget.isOwnProfile) ...[
          IconButton(
            tooltip: context.t('profileBgTitle'),
            icon: Icon(Icons.wallpaper_rounded, color: c.ink),
            onPressed: _pickBackground,
          ),
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
        ] else
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: c.ink),
            onPressed: () => ActionMenu.profile(
              context,
              userId: _targetId.toString(),
              username: (userProfile['username'] ?? '').toString(),
              isBlocked: _iBlocked,
              onChanged: () {
                _checkBlock();
                _loadProfile();
              },
            ),
          ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (ctx, cons) => ValueListenableBuilder<double>(
        valueListenable: _stretchPx,
        builder: (ctx2, px, __) {
          final w = cons.biggest.width;
          final h = cons.biggest.height;
          final maxH = expanded + topPad;
          final minH = kToolbarHeight + topPad;
          final t = ((h - minH) / (maxH - minH)).clamp(0.0, 1.0);
          final e = Curves.easeOut.transform(t);
          // Morph factor driven DIRECTLY by the finger: overscroll pixels
          // from the scroll controller (0 → circle, ~120px → full square).
          // The bouncing physics springs it back on release — no separate
          // animation, the photo follows the gesture both ways.
          final s = (px / 120).clamp(0.0, 1.0);
          // The header itself grows with the stretch; fall back to the
          // computed height if the sliver hasn't expanded yet this frame.
          final hh = h > maxH ? h : maxH + px;

          // Morphing avatar geometry (round → full-bleed square). The square
          // target width is capped the same way `expanded` is above — on a
          // wide desktop browser `w` (the sliver's actual width) can be far
          // wider than the header is ever tall, so the photo targets
          // `squareW` instead of stretching edge-to-edge into a rectangle
          // again, and is centered within `w` rather than left-anchored.
          final d = 44.0 + 62.0 * t; // round diameter at current collapse
          final squareW = w < squareSize ? w : squareSize;
          final avW = d + (squareW - d) * s;
          final avH = d + (hh - d) * s;
          final avLeft = ((w - d) / 2) * (1 - s) + ((w - squareW) / 2) * s;
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
                    child: Container(
                      // Instagram-style glow when there's a published story —
                      // fades to nothing on its own as the ring inset shrinks
                      // to 0, so it never needs to survive the square morph.
                      padding: EdgeInsets.all(
                          userStories.isNotEmpty ? 2.5 * (1 - s) : 0),
                      decoration: userStories.isNotEmpty
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(radius),
                              gradient: c.storyGradient,
                            )
                          : null,
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
              // Ignored only WHILE STRETCHING. Unconditional IgnorePointer here
              // is why tapping the PRO badge did nothing — the badge sits in
              // this row, so it could never receive a touch. Plain Text has no
              // recognizer and doesn't hit-test itself, so letting pointers
              // through at rest doesn't steal scroll drags.
              child: IgnorePointer(
                ignoring: s > 0.01,
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
            // Anchored to avLeft/avW (the photo's own bounds) rather than
            // the full Stack width — on mobile those are the same thing, but
            // on a wide desktop browser the photo is a centered square
            // narrower than `w`, and this would otherwise spill past its
            // edges into the empty space either side of it.
            if (s > 0) ...[
              Positioned(
                left: avLeft, right: w - avLeft - avW, bottom: 0, height: 130,
                // Stays unconditionally ignored: this copy is only visible
                // mid-stretch, when the finger is already dragging.
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
                left: avLeft + 16,
                right: (w - avLeft - avW) + 16,
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
      ),
    );
  }

  Widget _bigAvatar(BrutalColors c, dynamic avatarUrl, double size,
      {bool tappable = true}) {
    final hasStory = userStories.isNotEmpty;
    final photo = Container(
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
        border:
            hasStory ? null : Border.all(color: c.ink.withOpacity(0.08), width: 2),
      ),
      child: avatarUrl == null
          ? Icon(Icons.person_rounded, size: size * 0.5, color: Colors.white)
          : null,
    );
    // Instagram-style glow when there's a published story.
    final circle = !hasStory
        ? photo
        : Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(shape: BoxShape.circle, gradient: c.storyGradient),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.bg),
              child: photo,
            ),
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
          const VerifiedBadge(size: 20),
        ],
        if (userProfile['is_pro'] == true) ...[
          const SizedBox(width: 6),
          ProBadge(
            isPro: true,
            gifUrl: userProfile['pro_badge_gif']?.toString(),
            // Only your own badge is editable; on someone else's profile it's
            // just an ornament.
            onTap: widget.isOwnProfile ? _editProBadge : null,
          ),
        ],
        const SizedBox(width: 6),
        _auraBadge(c),
      ],
    );
  }

  /// Pick or clear the GIF beside your name.
  Future<void> _editProBadge() async {
    final picked = await showProBadgePicker(context);
    if (picked == null || !mounted) return; // dismissed
    final result = await applyProBadge(context, picked);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    setState(() => userProfile['pro_badge_gif'] = result.url);
    // Mirror into the cached session so the badge survives a restart without
    // waiting for the next profile fetch.
    await Session.patch({'pro_badge_gif': result.url});
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('proBadgeSaved'))));
    }
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

    // ── «Любимый трек» (Раздел 2) — Telegram-style profile music ──────────────
  Map? get _favTrack {
    final t = userProfile['fav_track'];
    return t is Map ? t : null;
  }

  // ── Animated profile background (Telegram-style) — server-synced so
  // visitors see it too, not just the owner. Entitlement enforced on the
  // READ path (like the name badge): a Pro preset stops rendering the moment
  // the OWNER's subscription lapses, without wiping their stored choice —
  // it comes back on its own if they resubscribe.
  ProfileBackgroundPreset? get _bg {
    final p = ProfileBackgrounds.byId(userProfile['profile_background']?.toString());
    if (p == null) return null;
    if (p.pro && userProfile['is_pro'] != true) return null;
    return p;
  }

  Future<void> _pickBackground() async {
    final choice = await showProfileBackgroundPicker(context,
        current: userProfile['profile_background']?.toString(), user: widget.user);
    if (choice == null || !mounted) return;
    final value = choice.isEmpty ? null : choice;
    setState(() => userProfile['profile_background'] = value);
    await ApiService.updateUser(
        widget.user['id'].toString(), {'profile_background': value});
  }

  Widget _favTrackSection(BrutalColors c) {
    final t = _favTrack;
    // Bug 4: clear air above AND below the row (owner button too), so it never
    // crowds the stats card. Empty state adds no phantom spacing for visitors.
    if (t != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: FavTrackPill(track: t, onTap: () => _openFavPlayer(t)),
      );
    }
    // No track: owner sees a subtle add button, visitors see nothing.
    if (widget.isOwnProfile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FavTrackAddButton(
            onTap: _pickFavTrack, locked: !ProState.isPro.value),
      );
    }
    return const SizedBox.shrink();
  }

  void _favTrackUpsell() {
    showProUpsell(context,
        user: widget.user,
        icon: Icons.music_note_rounded,
        body: context.t('favTrackProOnly'));
  }

  void _openFavPlayer(Map t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      isScrollControlled: true,
      builder: (_) => FavTrackPlayerSheet(
        track: t,
        isOwner: widget.isOwnProfile,
        onChange: () {
          Navigator.pop(context);
          _pickFavTrack();
        },
        onRemove: () {
          Navigator.pop(context);
          _saveFavTrack(null);
        },
      ),
    );
  }

  /// Rhythm-only picker (with search) — the HARD RULE: no device audio.
  Future<void> _pickFavTrack() async {
    if (!ProState.isPro.value) return _favTrackUpsell();
    final picked = await showModalBottomSheet<Map>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      isScrollControlled: true,
      builder: (_) => const MediaPickerSheet(),
    );
    if (picked == null || !mounted) return;
    _saveFavTrack({
      'url': (picked['audio'] ?? '').toString(),
      'title': (picked['title'] ?? '').toString(),
      'artist': (picked['showTitle'] ?? '').toString(),
      'art': (picked['artwork'] ?? '').toString(),
      'dur': (picked['duration'] ?? '').toString(),
    });
  }

  /// Stores ONLY the catalog reference (or null to clear) — never audio bytes.
  Future<void> _saveFavTrack(Map? track) async {
    setState(() => userProfile['fav_track'] = track);
    await ApiService.updateUser(
        widget.user['id'].toString(), {'fav_track': track});
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
                context.t('followers'), onTap: () => _openFollowList(true)),
            _stat(c, '${userProfile['posts_count'] ?? userPosts.length}',
                context.t('postsLbl')),
            _stat(c, '${userProfile['following_count'] ?? 0}',
                context.t('following'), onTap: () => _openFollowList(false)),
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
          onTap: () => setState(() {
            _tabForward = i > _tab;
            _tab = i;
          }),
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
      children: list.map((post) => GestureDetector(
        onTap: () async {
          await CommentsScreen.show(context,
              post: Map<String, dynamic>.from(post), user: widget.user);
          // Refresh in case the post was edited or deleted while open.
          if (mounted) _loadPosts();
        },
        child: Container(
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
                if (PostMediaCarousel.urlsOf(post).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PostMediaCarousel(post: post, height: 280),
                ],
                if (post['music'] is Map) ...[
                  const SizedBox(height: 10),
                  PostMusicBar(track: Map<String, dynamic>.from(post['music'])),
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
        // A video story's image_url IS the .mp4. Feeding that to
        // CachedNetworkImage can't decode anything, which is why video stories
        // showed as blank white tiles with no way to tell they were tappable.
        final isVideo = ApiService.isVideoStory(url);
        return GestureDetector(
          onTap: () => _viewStory(s),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: (MediaQuery.of(context).size.width - 32 - 16) / 3,
              height: 150,
              child: url.isEmpty
                  ? Container(color: c.surface2)
                  : isVideo
                      // No server-side poster frame exists for stories, and
                      // decoding one on device per tile would cost a video
                      // controller each. A film-strip placeholder plus a play
                      // badge is honest about what it is and stays cheap.
                      ? Stack(fit: StackFit.expand, children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  c.surface2,
                                  c.accent.withOpacity(0.18),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.42),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Icon(Icons.videocam_rounded,
                                size: 15,
                                color: Colors.white.withOpacity(0.85)),
                          ),
                        ])
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: c.surface2),
                          // A dead URL previously fell through to nothing,
                          // producing the same blank tile as a video.
                          errorWidget: (_, __, ___) => Container(
                            color: c.surface2,
                            child: Icon(Icons.broken_image_outlined,
                                color: c.inkSoft, size: 22),
                          ),
                        ),
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

  Widget _stat(BrutalColors c, String value, String label, {VoidCallback? onTap}) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
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
        ),
      );

  void _openFollowList(bool showFollowers) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListScreen(
          user: widget.user,
          targetUserId: _targetId.toString(),
          targetUsername: (userProfile['username'] ?? '').toString(),
          showFollowers: showFollowers,
        ),
      ),
    );
  }

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
