import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/pro_badge.dart';
import '../widgets/verified_badge.dart';
import 'profile_screen.dart';

/// Instagram-style followers/following list: search, Follow/Following button
/// per row, an X to remove a follower from YOUR OWN followers list.
class FollowListScreen extends StatefulWidget {
  final Map user; // the logged-in user (viewer)
  final String targetUserId; // whose followers/following we're viewing
  final String targetUsername;
  final bool showFollowers; // true = followers tab first, false = following

  const FollowListScreen({
    super.key,
    required this.user,
    required this.targetUserId,
    required this.targetUsername,
    this.showFollowers = true,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late bool _followersTab = widget.showFollowers;
  List<Map> _followers = [];
  List<Map> _following = [];
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _isOwn => widget.targetUserId == widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _loadFollowers();
    _loadFollowing();
  }

  Future<void> _loadFollowers() async {
    final data = await ApiService.getFollowers(widget.targetUserId);
    if (mounted) setState(() { _followers = data; _loadingFollowers = false; });
  }

  Future<void> _loadFollowing() async {
    final data = await ApiService.getFollowing(widget.targetUserId);
    if (mounted) setState(() { _following = data; _loadingFollowing = false; });
  }

  List<Map> get _activeList {
    final list = _followersTab ? _followers : _following;
    if (_query.trim().isEmpty) return list;
    final q = _query.trim().toLowerCase();
    return list.where((u) => (u['username'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  Future<void> _toggleFollow(Map u) async {
    final id = u['id'].toString();
    final me = widget.user['id'].toString();
    final wasFollowing = u['is_following'] == true;
    setState(() => u['is_following'] = !wasFollowing);
    if (wasFollowing) {
      await ApiService.unfollow(me, id);
    } else {
      await ApiService.follow(me, id);
    }
  }

  Future<void> _removeFollower(Map u) async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('removeFollowerTitle')),
        content: Text(context.t('removeFollowerBody')
            .replaceAll('{name}', (u['username'] ?? '').toString())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(context.t('removeBtn'), style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _followers.removeWhere((f) => f['id'] == u['id']));
    await ApiService.unfollow(u['id'].toString(), widget.user['id'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(widget.targetUsername)),
      body: Column(children: [
        Row(children: [
          _tab(c, true, context.t('followers')),
          _tab(c, false, context.t('following')),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: context.t('searchPeople'),
              prefixIcon: Icon(Icons.search_rounded, color: c.inkSoft),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: (_followersTab ? _loadingFollowers : _loadingFollowing)
              ? const Center(child: CircularProgressIndicator())
              : _activeList.isEmpty
                  ? Center(
                      child: Text(context.t('nothingFound'),
                          style: TextStyle(color: c.inkSoft)))
                  : ListView.builder(
                      itemCount: _activeList.length,
                      itemBuilder: (_, i) => _row(c, _activeList[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _tab(BrutalColors c, bool followers, String label) {
    final sel = _followersTab == followers;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _followersTab = followers),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: sel ? c.ink : Colors.transparent, width: 2))),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: sel ? c.ink : c.inkSoft,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _row(BrutalColors c, Map u) {
    final isMe = u['is_me'] == true;
    final isFollowing = u['is_following'] == true;
    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
              user: widget.user, targetUserId: u['id'], isOwnProfile: isMe),
        ),
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: c.surface2,
        backgroundImage: (u['avatar_url'] ?? '').toString().isNotEmpty
            ? CachedNetworkImageProvider(u['avatar_url'])
            : null,
        child: (u['avatar_url'] ?? '').toString().isEmpty
            ? Icon(Icons.person, color: c.inkSoft)
            : null,
      ),
      title: Row(children: [
        Flexible(
          child: Text((u['username'] ?? 'User').toString(),
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
      subtitle: (u['bio'] ?? '').toString().isNotEmpty
          ? Text(u['bio'].toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkSoft, fontSize: 12.5))
          : null,
      trailing: isMe
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 34,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isFollowing ? Colors.transparent : c.accent,
                    side: BorderSide(color: isFollowing ? c.ink.withOpacity(0.2) : c.accent),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => _toggleFollow(u),
                  child: Text(
                      isFollowing ? context.t('subscribed') : context.t('subscribe'),
                      style: TextStyle(
                          color: isFollowing ? c.ink : c.onAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              if (_isOwn && _followersTab) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: c.inkSoft, size: 20),
                  onPressed: () => _removeFollower(u),
                ),
              ],
            ]),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
