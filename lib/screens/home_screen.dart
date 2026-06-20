import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'chat_detail_screen.dart';
import 'story_view_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  HOME · "PULSE"
//  Not a feed clone — a tactile board with an ENERGY meter + streak that grow
//  as you interact. Oversized, satisfying reaction blocks = dopamine.
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

  // dopamine state
  double _energy = 0.12;
  int _streak = 1;
  bool _postedToday = false;

  final _composerCtrl = TextEditingController();
  String? _imageB64;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Show the cached feed instantly, then refresh in the background.
    final cached = await _readCache();
    if (mounted) {
      setState(() {
        if (cached != null && _posts.isEmpty) _posts = cached;
        _loading = _posts.isEmpty;
      });
    }
    final data = await ApiService.getPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        _posts = data;
        _loading = false;
      });
    }
    _saveCache(data);
    _loadStories();
  }

  Future<List?> _readCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('feed_cache');
      return s == null ? null : (jsonDecode(s) as List);
    } catch (_) {
      return null;
    }
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

  // group stories by author (excluding mine, which get the "your story" tile)
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

  Future<void> _addStory() async {
    final c = context.k;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
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
      ),
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

  void _addEnergy(double amount) {
    HapticFeedback.lightImpact();
    setState(() => _energy = (_energy + amount).clamp(0.0, 1.0));
  }

  // ─── Spatial navigation (swipe on a post) ───────────────────────────────────
  void _openAuthorProfile(Map post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: widget.user,
          targetUserId: post['user_id'],
          isOwnProfile: post['user_id'] == widget.user['id'],
        ),
      ),
    );
  }

  void _openChat(Map post) {
    if (post['user_id'] == widget.user['id']) return; // don't DM yourself
    final target = {
      'id': post['user_id'],
      'username': post['username'],
      'avatar_url': post['user_avatar'] ?? post['avatar_url'],
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chat: {'name': post['username']},
          user: widget.user,
          targetUser: target,
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageB64 = base64Encode(bytes));
  }

  Future<void> _drop() async {
    if (_composerCtrl.text.trim().isEmpty && _imageB64 == null) return;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      if (_imageB64 != null) {
        imageUrl = await ApiService.uploadMedia(
          base64Decode(_imageB64!),
          folder: 'post',
          ext: 'jpg',
          contentType: 'image/jpeg',
          userId: widget.user['id'].toString(),
        );
      }
      await ApiService.createPost(widget.user['id'], _composerCtrl.text.trim(),
          imageUrl: imageUrl);
      _composerCtrl.clear();
      setState(() {
        _imageB64 = null;
        if (!_postedToday) {
          _postedToday = true;
          _streak += 1;
        }
      });
      _addEnergy(0.18);
      await _load();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
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
              SliverToBoxAdapter(child: _composer(c)),
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Center(
                        child: CircularProgressIndicator(color: c.accent2)),
                  ),
                )
              else if (_posts.isEmpty)
                SliverToBoxAdapter(child: _empty(c))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      // Spatial gestures: swipe right → message author,
                      // swipe left → open author's profile.
                      child: GestureDetector(
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v > 250) {
                            _openChat(_posts[i]);
                          } else if (v < -250) {
                            _openAuthorProfile(_posts[i]);
                          }
                        },
                        child: _PulseCard(
                          post: _posts[i],
                          user: widget.user,
                          onEnergy: _addEnergy,
                        ),
                      ),
                    ),
                    childCount: _posts.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          // SS badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: c.buttonGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: const Text('SS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          const SizedBox(width: 10),
          Text(
            context.t('appName'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: c.ink,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          BrutalTap(
            padding: const EdgeInsets.all(10),
            radius: 12,
            shadowOffset: const Offset(3, 3),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SettingsScreen(user: widget.user)),
            ),
            child: Icon(Icons.tune_rounded, color: c.ink, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _storiesRow(BrutalColors c) {
    final myStories = _stories
        .where(
            (s) => s['user_id'].toString() == widget.user['id'].toString())
        .toList();
    final grouped = _grouped;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            _MyStoryBtn(
              user: widget.user,
              hasStory: myStories.isNotEmpty,
              onAdd: _addStory,
              onView: () {
                if (myStories.isNotEmpty) {
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
                } else {
                  _addStory();
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

  Widget _composer(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: BrutalCard(
        fill: c.surface,
        padding: const EdgeInsets.all(14),
        shadowOffset: const Offset(5, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _composerCtrl,
              maxLines: null,
              minLines: 1,
              style: TextStyle(
                  color: c.ink, fontSize: 17, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t('whatsUp'),
                hintStyle: TextStyle(
                    color: c.inkSoft, fontSize: 17, fontWeight: FontWeight.w600),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_imageB64 != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(_imageB64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                BrutalTap(
                  onTap: _pickImage,
                  padding: const EdgeInsets.all(10),
                  radius: 10,
                  shadowOffset: const Offset(3, 3),
                  child: Icon(Icons.add_photo_alternate_rounded,
                      color: c.accent2, size: 20),
                ),
                const Spacer(),
                BrutalTap(
                  onTap: _posting ? null : _drop,
                  fill: c.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  radius: 10,
                  shadowOffset: const Offset(4, 4),
                  child: _posting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: c.onAccent),
                        )
                      : Text(
                          context.t('drop'),
                          style: TextStyle(
                            color: c.onAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Icon(Icons.bolt_rounded, size: 64, color: c.accent),
          const SizedBox(height: 14),
          Text(
            context.t('nothingYet'),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 20, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('beFirst'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }
}

// ─── PULSE CARD ───────────────────────────────────────────────────────────────
class _PulseCard extends StatefulWidget {
  final Map post;
  final Map user;
  final void Function(double) onEnergy;
  const _PulseCard(
      {required this.post, required this.user, required this.onEnergy});
  @override
  State<_PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<_PulseCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likes;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _liked = widget.post['is_liked'] == true;
    _likes = (widget.post['likes_count'] ?? 0) as int;
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  Future<void> _react() async {
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += _liked ? 1 : -1;
    });
    if (_liked) {
      _pop.forward(from: 0);
      widget.onEnergy(0.06);
    }
    final res = await ApiService.likePost(
        widget.post['id'].toString(), widget.user['id'].toString());
    if (res['success'] == true && mounted) {
      setState(() {
        _likes = (res['likes_count'] ?? _likes) as int;
        _liked = res['liked'] == true;
      });
    }
  }

  Future<void> _repost() async {
    HapticFeedback.lightImpact();
    final username = (widget.post['username'] ?? 'user').toString();
    final content = (widget.post['content'] ?? '').toString();
    final image = widget.post['image_url'];
    final text = '🔁 @$username: $content'.trim();
    await ApiService.createPost(
      widget.user['id'].toString(),
      text,
      imageUrl: image?.toString(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('reposted'))),
      );
    }
  }

  void _share() {
    final username = (widget.post['username'] ?? 'user').toString();
    final content = (widget.post['content'] ?? '').toString();
    Clipboard.setData(
        ClipboardData(text: 'Sigma Social · @$username: $content'));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('linkCopied'))),
    );
  }

  String _time() {
    final raw = widget.post['created_at'];
    if (raw == null) return '';
    try {
      return timeago.format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final username = (widget.post['username'] ?? 'user').toString();
    final avatar = widget.post['user_avatar'] ?? widget.post['avatar_url'];
    final content = (widget.post['content'] ?? '').toString();
    final image = widget.post['image_url'];

    return BrutalCard(
      fill: c.surface,
      padding: EdgeInsets.zero,
      shadowOffset: const Offset(5, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // author
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    user: widget.user,
                    targetUserId: widget.post['user_id'],
                    isOwnProfile:
                        widget.post['user_id'] == widget.user['id'],
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.ink, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatar != null
                        ? CachedNetworkImage(
                            imageUrl: avatar.toString(), fit: BoxFit.cover)
                        : Icon(Icons.person_rounded, color: c.inkSoft),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$username',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: c.ink),
                        ),
                        Text(
                          _time(),
                          style: TextStyle(fontSize: 11, color: c.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // content
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                content,
                style: TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: c.ink),
              ),
            ),
          // image
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.ink, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: image.toString(),
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // reactions
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.ink, width: 2)),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: _ReactBtn(
                    icon: _liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '$_likes',
                    active: _liked,
                    activeColor: c.danger,
                    pop: _pop,
                    onTap: _react,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReactBtn(
                    icon: Icons.mode_comment_outlined,
                    label: context.t('comment'),
                    active: false,
                    activeColor: c.accent2,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommentsScreen(
                            post: widget.post, user: widget.user),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReactBtn(
                    icon: Icons.repeat_rounded,
                    label: context.t('repost'),
                    active: false,
                    activeColor: c.accent2,
                    onTap: _repost,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReactBtn(
                    icon: Icons.ios_share_rounded,
                    label: context.t('share'),
                    active: false,
                    activeColor: c.accent2,
                    onTap: _share,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }
}

class _ReactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final AnimationController? pop;
  const _ReactBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.pop,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final iconWidget = Icon(
      icon,
      size: 20,
      color: active ? c.onAccent : c.ink,
    );
    return BrutalTap(
      onTap: onTap,
      fill: active ? activeColor : c.surface,
      radius: 10,
      shadowOffset: const Offset(3, 3),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          pop != null
              ? ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                    CurvedAnimation(parent: pop!, curve: Curves.elasticOut),
                  ),
                  child: iconWidget,
                )
              : iconWidget,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: active ? c.onAccent : c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── STORY WIDGETS ────────────────────────────────────────────────────────────
class _MyStoryBtn extends StatelessWidget {
  final Map user;
  final bool hasStory;
  final VoidCallback onAdd;
  final VoidCallback onView;
  const _MyStoryBtn({
    required this.user,
    required this.hasStory,
    required this.onAdd,
    required this.onView,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: hasStory ? onView : onAdd,
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

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetTile(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: c.accent, size: 20),
      ),
      title: Text(label,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
