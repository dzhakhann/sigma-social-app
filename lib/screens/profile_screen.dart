import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../constants.dart';
import '../theme/brutal_theme.dart';
import 'chat_detail_screen.dart';

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
  bool isLoading = false;
  bool isEditing = false;
  bool isFollowing = false;
  bool isUploadingAvatar = false;
  late TextEditingController _usernameCtrl;
  late TextEditingController _bioCtrl;

  String get _targetId =>
      widget.isOwnProfile ? widget.user['id'] : widget.targetUserId!;

  @override
  void initState() {
    super.initState();
    userProfile = widget.isOwnProfile ? Map.from(widget.user) : {};
    _usernameCtrl =
        TextEditingController(text: userProfile['username'] ?? '');
    _bioCtrl = TextEditingController(text: userProfile['bio'] ?? '');
    _loadProfile();
    _loadPosts();
    if (!widget.isOwnProfile) _checkFollow();
  }

  Future<void> _loadProfile() async {
    final data = await ApiService.getUser(_targetId);
    if (data['success'] == true && mounted) {
      setState(() {
        userProfile = data['data'];
        _usernameCtrl.text = userProfile['username'] ?? '';
        _bioCtrl.text = userProfile['bio'] ?? '';
      });
    }
  }

  Future<void> _loadPosts() async {
    setState(() => isLoading = true);
    final all = await ApiService.getPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        userPosts = all.where((p) => p['user_id'] == _targetId).toList();
        isLoading = false;
      });
    }
  }

  Future<void> _checkFollow() async {
    final result = await ApiService.isFollowing(
        widget.user['id'], widget.targetUserId!);
    if (mounted) setState(() => isFollowing = result);
  }

  Future<void> _toggleFollow() async {
    final fn = isFollowing
        ? ApiService.unfollow
        : ApiService.follow;
    final data = await fn(widget.user['id'], widget.targetUserId!);
    if (data['success'] == true && mounted) {
      setState(() {
        isFollowing = !isFollowing;
        userProfile['followers_count'] = isFollowing
            ? (userProfile['followers_count'] ?? 0) + 1
            : ((userProfile['followers_count'] ?? 1) - 1).clamp(0, 99999);
      });
    }
  }

  Future<void> _saveProfile() async {
    final data = await ApiService.updateUser(widget.user['id'], {
      'username': _usernameCtrl.text,
      'bio': _bioCtrl.text,
    });
    if (data['success'] == true && mounted) {
      setState(() {
        isEditing = false;
        userProfile['username'] = _usernameCtrl.text;
        userProfile['bio'] = _bioCtrl.text;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated!')));
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80);
    if (file == null) return;
    setState(() => isUploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final fileName = '${widget.user['id']}_avatar.jpg';
      final res = await http.put(
        Uri.parse(
            '$kSupabaseUrl/storage/v1/object/avatars/$fileName'),
        headers: {
          'Authorization': 'Bearer $kSupabaseKey',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: bytes,
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final url =
            '$kSupabaseUrl/storage/v1/object/public/avatars/$fileName?t=${DateTime.now().millisecondsSinceEpoch}';
        await ApiService.updateUser(widget.user['id'], {
          'username': userProfile['username'],
          'bio': userProfile['bio'] ?? '',
          'avatar_url': url,
        });
        if (mounted) {
          setState(() => userProfile['avatar_url'] = url);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Avatar updated!')));
        }
      }
    } catch (_) {}
    setState(() => isUploadingAvatar = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final avatarUrl = userProfile['avatar_url'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.isOwnProfile && !isEditing)
            IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => isEditing = true))
          else if (widget.isOwnProfile && isEditing)
            IconButton(icon: const Icon(Icons.check), onPressed: _saveProfile),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              GestureDetector(
                onTap: widget.isOwnProfile ? _pickAvatar : null,
                child: Stack(children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      image: avatarUrl != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(avatarUrl),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: avatarUrl == null
                        ? Icon(Icons.person,
                            size: 50, color: c.ink)
                        : null,
                  ),
                  if (widget.isOwnProfile)
                    Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: c.accent, shape: BoxShape.circle),
                          child: isUploadingAvatar
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: c.ink))
                              : Icon(Icons.camera_alt,
                                  size: 18, color: c.ink),
                        )),
                ]),
              ),
              const SizedBox(height: 16),
              if (!isEditing)
                Text(userProfile['username'] ?? 'User',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold))
              else
                TextField(
                    controller: _usernameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 8),
              if (!isEditing)
                Text(userProfile['bio'] ?? 'No bio',
                    style: TextStyle(color: c.inkSoft),
                    textAlign: TextAlign.center)
              else
                TextField(
                    controller: _bioCtrl,
                    decoration: const InputDecoration(labelText: 'Bio'),
                    maxLines: 3),
              const SizedBox(height: 20),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(userPosts.length.toString(), 'Posts', c),
                    _stat(
                        '${userProfile['followers_count'] ?? 0}', 'Followers', c),
                    _stat(
                        '${userProfile['following_count'] ?? 0}', 'Following', c),
                  ]),
              if (!widget.isOwnProfile) ...[
                const SizedBox(height: 20),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _toggleFollow,
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isFollowing ? c.inkSoft : c.accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12)),
                        child: Text(isFollowing ? 'Following ✓' : 'Follow +',
                            style: TextStyle(
                                color: isFollowing
                                    ? Colors.white
                                    : c.ink)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                        chat: {
                                          'name': userProfile['username']
                                        },
                                        user: widget.user,
                                        targetUser: userProfile))),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: c.accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12)),
                        child: Text('Message 💬',
                            style: TextStyle(color: c.ink)),
                      ),
                    ]),
              ],
            ]),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Posts',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : userPosts.isEmpty
                      ? Text('No posts',
                          style: TextStyle(color: c.inkSoft))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: userPosts.length,
                          itemBuilder: (_, i) {
                            final post = userPosts[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(post['content'] ?? '',
                                            style: const TextStyle(
                                                fontSize: 15)),
                                        const SizedBox(height: 6),
                                        Text(
                                            '❤️ ${post['likes_count']} likes',
                                            style: TextStyle(
                                                color: c.inkSoft,
                                                fontSize: 12)),
                                      ])),
                            );
                          }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label, BrutalColors c) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: c.accent)),
        Text(label, style: TextStyle(color: c.inkSoft, fontSize: 12)),
      ]);

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }
}
