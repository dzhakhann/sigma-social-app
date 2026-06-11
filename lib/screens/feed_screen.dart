import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../constants.dart';
import '../theme/brutal_theme.dart';
import '../widgets/post_card.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'story_view_screen.dart';

class FeedScreen extends StatefulWidget {
  final Map user;
  const FeedScreen({super.key, required this.user});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List _forYouPosts = [];
  List _followingPosts = [];
  List _stories = [];
  bool _isLoading = false;

  // Create post state
  final _postCtrl = TextEditingController();
  String? _pickedImageBase64;
  String? _pickedImagePath;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadPosts(), _loadStories()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadPosts() async {
    final all = await ApiService.getPosts(widget.user['id']);
    final following = await ApiService.getFollowingPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        _forYouPosts = all;
        _followingPosts = following;
      });
    }
  }

  Future<void> _loadStories() async {
    final data = await ApiService.getStories();
    if (mounted) setState(() => _stories = data);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageBase64 = base64Encode(bytes);
      _pickedImagePath = file.path;
    });
  }

  Future<void> _createPost() async {
    if (_postCtrl.text.trim().isEmpty && _pickedImageBase64 == null) return;
    setState(() => _isPosting = true);
    try {
      String? imageUrl;
      if (_pickedImageBase64 != null) {
        final fileName =
            '${widget.user['id']}_post_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final res = await http.put(
          Uri.parse('$kSupabaseUrl/storage/v1/object/avatars/$fileName'),
          headers: {
            'Authorization': 'Bearer $kSupabaseKey',
            'Content-Type': 'image/jpeg',
            'x-upsert': 'true',
          },
          body: base64Decode(_pickedImageBase64!),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          imageUrl =
              '$kSupabaseUrl/storage/v1/object/public/avatars/$fileName';
        }
      }
      await ApiService.createPost(
          widget.user['id'], _postCtrl.text.trim(),
          imageUrl: imageUrl);
      _postCtrl.clear();
      setState(() => _pickedImageBase64 = null);
      _loadPosts();
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _likePost(String postId, List postList, int index) async {
    final data = await ApiService.likePost(postId, widget.user['id']);
    if (data['success'] == true && mounted) {
      setState(() {
        final updated = Map.from(postList[index]);
        updated['likes_count'] = data['likes_count'];
        updated['is_liked'] = data['liked'];
        postList[index] = updated;
      });
    }
  }

  // ───────────── STORIES ─────────────────────────────────────────────────────

  Map<String, List> get _grouped {
    final Map<String, List> g = {};
    for (var s in _stories) {
      final uid = s['user_id'] as String;
      if (uid == widget.user['id']) continue;
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
                )));
  }

  Future<void> _addStory() async {
    final c = context.k;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final sc = ctx.k;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: sc.ink.withOpacity(0.12), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Add Story',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: sc.ink)),
            const SizedBox(height: 16),
            _SheetTile(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            _SheetTile(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ]),
        );
      },
    );
    if (src == null) return;
    final picker = ImagePicker();
    final img = await picker.pickImage(
        source: src, maxWidth: 800, imageQuality: 70);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final data =
        await ApiService.uploadStory(widget.user['id'], base64Encode(bytes));
    if (data['success'] == true) _loadStories();
  }

  // ───────────── BUILD ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _buildAppBar(c),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildFeed(_forYouPosts, 0, c),
            _buildFeed(_followingPosts, 1, c),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(BrutalColors c) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      backgroundColor: c.bg,
      elevation: 0,
      title: ShaderMask(
        shaderCallback: (bounds) =>
            c.storyGradient.createShader(bounds),
        child: const Text('sigma',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2)),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: Column(children: [
          // Stories row
          SizedBox(
            height: 90,
            child: _buildStoriesRow(),
          ),
        ]),
      ),
    );
  }

  Widget _buildStoriesRow() {
    final myStories =
        _stories.where((s) => s['user_id'] == widget.user['id']).toList();
    final grouped = _grouped;

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          )));
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
    );
  }

  Widget _buildFeed(List posts, int tabIndex, BrutalColors c) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: c.accent,
      backgroundColor: c.surface,
      child: CustomScrollView(
        slivers: [
          // Tab bar
          SliverToBoxAdapter(
            child: Container(
              color: c.bg,
              child: TabBar(
                controller: _tabCtrl,
                indicatorColor: c.accent,
                indicatorWeight: 2,
                labelColor: c.ink,
                unselectedLabelColor: c.inkSoft,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
                tabs: const [
                  Tab(text: 'For You'),
                  Tab(text: 'Following'),
                ],
              ),
            ),
          ),

          // Create post
          SliverToBoxAdapter(child: _buildCreatePost(c)),

          // Posts
          if (_isLoading)
            SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(
                        color: c.accent, strokeWidth: 2)))
          else if (posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(
                      tabIndex == 1
                          ? Icons.people_outline_rounded
                          : Icons.dynamic_feed_rounded,
                      size: 52,
                      color: c.inkSoft),
                  const SizedBox(height: 14),
                  Text(
                      tabIndex == 1
                          ? 'Follow people to see their posts'
                          : 'No posts yet',
                      style: TextStyle(color: c.inkSoft, fontSize: 15)),
                ]),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final post = posts[i];
                  return PostCard(
                    post: post,
                    onLike: () => _likePost(post['id'], posts, i),
                    onComment: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CommentsScreen(
                                post: post, user: widget.user))),
                    onUserTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(
                                  user: widget.user,
                                  targetUserId: post['user_id'],
                                  isOwnProfile:
                                      post['user_id'] == widget.user['id'],
                                ))),
                  );
                },
                childCount: posts.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCreatePost(BrutalColors c) {
    return Container(
      color: c.bg,
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SmallAvatar(url: widget.user['avatar_url']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              TextField(
                controller: _postCtrl,
                maxLines: null,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_pickedImagePath != null) ...[
                const SizedBox(height: 10),
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(_pickedImagePath!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: c.surface,
                            child: Center(
                                child: Icon(Icons.image, color: c.inkSoft)))),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _pickedImageBase64 = null;
                        _pickedImagePath = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(children: [
          GestureDetector(
            onTap: _pickImage,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.image_outlined,
                  color: c.accent, size: 22),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _isPosting ? null : _createPost,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                gradient: c.buttonGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isPosting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Post',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
            ),
          ),
        ]),
      ]),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _postCtrl.dispose();
    super.dispose();
  }
}

// ─── STORY WIDGETS ────────────────────────────────────────────────────────────

class _MyStoryBtn extends StatelessWidget {
  final Map user;
  final bool hasStory;
  final VoidCallback onAdd;
  final VoidCallback onView;
  const _MyStoryBtn(
      {required this.user,
      required this.hasStory,
      required this.onAdd,
      required this.onView});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: hasStory ? onView : onAdd,
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(right: 14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(children: [
            _StoryRing(
              url: user['avatar_url'],
              hasStory: hasStory,
              size: 54,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    gradient: c.buttonGradient,
                    shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 13, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 5),
          Text('Your story',
              style: TextStyle(fontSize: 10, color: c.inkSoft),
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
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(right: 14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _StoryRing(
            url: first['user_avatar'],
            hasStory: true,
            size: 54,
          ),
          const SizedBox(height: 5),
          Text(first['username'] ?? 'User',
              style: TextStyle(fontSize: 10, color: c.inkSoft),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ]),
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
        color: hasStory ? null : c.ink.withOpacity(0.12),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.bg,
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: url != null
              ? CachedNetworkImage(
                  imageUrl: url!, fit: BoxFit.cover)
              : Container(
                  color: c.surface2,
                  child: Icon(Icons.person_rounded,
                      color: c.inkSoft)),
        ),
      ),
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  final String? url;
  const _SmallAvatar({this.url});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: c.surface2,
        child: url != null
            ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
            : Icon(Icons.person_rounded, color: c.inkSoft, size: 20),
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
          style: TextStyle(
              color: c.ink, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
