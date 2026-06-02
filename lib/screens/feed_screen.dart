import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../constants.dart';
import '../widgets/post_card.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'story_view_screen.dart';

class FeedScreen extends StatefulWidget {
  final Map user;
  const FeedScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _postCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List _posts = [];
  List _filtered = [];
  List _stories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadStories();
    _searchCtrl.addListener(_filter);
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    _posts = await ApiService.getPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _applyFilter();
      });
    }
  }

  Future<void> _loadStories() async {
    final data = await ApiService.getStories();
    if (mounted) setState(() => _stories = data);
  }

  void _filter() => setState(_applyFilter);

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    _filtered = q.isEmpty
        ? List.from(_posts)
        : _posts.where((p) {
            return (p['content'] ?? '').toLowerCase().contains(q) ||
                (p['username'] ?? '').toLowerCase().contains(q);
          }).toList();
  }

  Future<void> _createPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty) return;
    _postCtrl.clear();
    await ApiService.createPost(widget.user['id'], text);
    _loadPosts();
  }

  Future<void> _likePost(String postId) async {
    final data = await ApiService.likePost(postId, widget.user['id']);
    if (data['success'] == true && mounted) {
      setState(() {
        for (var i = 0; i < _posts.length; i++) {
          if (_posts[i]['id'] == postId) {
            _posts[i] = Map.from(_posts[i]);
            _posts[i]['likes_count'] = data['likes_count'];
            _posts[i]['is_liked'] = data['liked'];
          }
        }
        _applyFilter();
      });
    }
  }

  // ===== STORIES =====
  Map<String, List> get _groupedStories {
    final Map<String, List> grouped = {};
    for (var s in _stories) {
      final uid = s['user_id'] as String;
      if (uid == widget.user['id']) continue;
      grouped.putIfAbsent(uid, () => []).add(s);
    }
    return grouped;
  }

  void _openStory(List userStories, int startIndex) {
    final allGroups = _groupedStories.values.toList();
    int groupIndex = 0;
    for (int i = 0; i < allGroups.length; i++) {
      if (allGroups[i].isNotEmpty &&
          allGroups[i][0]['user_id'] == userStories[0]['user_id']) {
        groupIndex = i;
        break;
      }
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StoryViewScreen(
                  stories: userStories,
                  allGroups: allGroups,
                  groupIndex: groupIndex,
                  startIndex: startIndex,
                  user: widget.user,
                  onStoryDeleted: _loadStories,
                )));
  }

  Future<void> _addStory() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add Story',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: kGold),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: kGold),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final img = await picker.pickImage(
        source: source, maxWidth: 800, imageQuality: 70);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final b64 = base64Encode(bytes);
    final data = await ApiService.uploadStory(widget.user['id'], b64);
    if (data['success'] == true) _loadStories();
  }

  @override
  Widget build(BuildContext context) {
    final myStories =
        _stories.where((s) => s['user_id'] == widget.user['id']).toList();
    final grouped = _groupedStories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SIGMA', style: TextStyle(letterSpacing: 4)),
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _loadPosts(); await _loadStories(); },
        color: kGold,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(children: [
                // STORIES
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: grouped.length + 1,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemBuilder: (_, index) {
                      if (index == 0) {
                        return _myStoryBtn(myStories);
                      }
                      final uid = grouped.keys.toList()[index - 1];
                      final uStories = grouped[uid]!;
                      return _storyAvatar(uStories);
                    },
                  ),
                ),
                const Divider(height: 1),
                // SEARCH
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search posts...',
                      prefixIcon: const Icon(Icons.search, color: kGold),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _filter();
                              })
                          : null,
                    ),
                  ),
                ),
                // NEW POST
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _postCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Share your thoughts...'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _createPost,
                        child: const Text('Post')),
                  ]),
                ),
              ]),
            ),
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
                : _filtered.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                            child: Text(
                                _searchCtrl.text.isEmpty
                                    ? 'No posts yet'
                                    : 'No posts found',
                                style: const TextStyle(color: Colors.grey))))
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final post = _filtered[i];
                            return PostCard(
                              post: post,
                              onLike: () => _likePost(post['id']),
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
                                            isOwnProfile: post['user_id'] ==
                                                widget.user['id'],
                                          ))),
                            );
                          },
                          childCount: _filtered.length,
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _myStoryBtn(List myStories) {
    return GestureDetector(
      onTap: myStories.isEmpty
          ? _addStory
          : () => showModalBottomSheet(
              context: context,
              backgroundColor: kCard,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                        leading: const Icon(Icons.add, color: kGold),
                        title: const Text('Add to story'),
                        onTap: () {
                          Navigator.pop(context);
                          _addStory();
                        }),
                    ListTile(
                        leading: const Icon(Icons.visibility, color: kGold),
                        title: const Text('View my story'),
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
                                      )));
                        }),
                  ])),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        width: 68,
        child: Column(children: [
          Stack(children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: myStories.isEmpty ? kBorder : kGold, width: 2),
                color: kCard,
                image: widget.user['avatar_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(widget.user['avatar_url']),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: widget.user['avatar_url'] == null
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: kGold, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.add, size: 14, color: Colors.black),
                )),
          ]),
          const SizedBox(height: 3),
          const Text('Your story',
              style: TextStyle(fontSize: 9, color: Colors.grey),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _storyAvatar(List uStories) {
    final first = uStories.first;
    return GestureDetector(
      onTap: () => _openStory(uStories, 0),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        width: 68,
        child: Column(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kGold, width: 2.5),
              color: kCard,
              image: first['user_avatar'] != null
                  ? DecorationImage(
                      image: NetworkImage(first['user_avatar']),
                      fit: BoxFit.cover)
                  : null,
            ),
            child: first['user_avatar'] == null
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 3),
          Text(first['username'] ?? 'User',
              style: const TextStyle(fontSize: 9, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _postCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }
}
