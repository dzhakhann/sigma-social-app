import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final Map user;
  const NotificationsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List _notifs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getNotifications(widget.user['id']);
    if (mounted) setState(() { _notifs = data; _isLoading = false; });
  }

  Future<void> _markAllRead() async {
    await ApiService.markAllNotificationsRead(widget.user['id']);
    _load();
  }

  IconData _icon(String type) {
    switch (type) {
      case 'like': return Icons.favorite;
      case 'comment': return Icons.comment;
      case 'follow': return Icons.person_add;
      case 'repost': return Icons.repeat_rounded;
      case 'channel_post': return Icons.campaign_rounded;
      default: return Icons.notifications;
    }
  }

  Color _iconColor(String type, BrutalColors c) {
    switch (type) {
      case 'like': return c.danger;
      case 'comment': return c.accent2;
      case 'follow': return c.accent;
      case 'channel_post': return c.accent3;
      default: return c.inkSoft;
    }
  }

  // Localized notification text built from type + sender name, so the message
  // always follows the app language (server stores it in one language only).
  String _notifText(Map n) {
    final u = (n['from_username'] ?? '').toString();
    String key;
    switch ((n['type'] ?? '').toString()) {
      case 'like': key = 'nLike'; break;
      case 'comment': key = 'nComment'; break;
      case 'follow': key = 'nFollow'; break;
      case 'repost': key = 'nRepost'; break;
      case 'channel_post': key = 'nChannelPost'; break;
      default: key = '';
    }
    if (key.isEmpty || u.isEmpty) return (n['message'] ?? '').toString();
    return context.t(key).replaceAll('{u}', u);
  }

  List _filtered(int tabIndex) {
    if (tabIndex == 0) return _notifs; // All
    if (tabIndex == 1) {
      // Subscriptions (follows + channel_post)
      return _notifs
          .where((n) =>
              n['type'] == 'follow' || n['type'] == 'channel_post')
          .toList();
    }
    // Replies (comments + likes)
    return _notifs
        .where((n) => n['type'] == 'comment' || n['type'] == 'like')
        .toList();
  }

  // Instagram-style routing: like/comment/repost → open the post,
  // follow → open the follower's profile.
  Future<void> _openNotif(Map n) async {
    final type = (n['type'] ?? '').toString();
    if (type == 'follow') {
      final fromId = n['from_user_id'];
      if (fromId == null) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            user: widget.user,
            targetUserId: fromId,
            isOwnProfile: fromId == widget.user['id'],
          ),
        ),
      );
      return;
    }
    // like / comment / repost → open the referenced post
    final postId = n['post_id'];
    if (postId == null) return;
    final post =
        await ApiService.getPost(postId.toString(), widget.user['id'].toString());
    if (post == null || !mounted) return;
    CommentsScreen.show(context, post: post, user: widget.user);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final unread = _notifs.where((n) => n['is_read'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? '${context.t('activityTitle')} ($unread)' : context.t('activityTitle')),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(context.t('readAll'),
                  style: TextStyle(color: c.accent, fontSize: 12)),
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: c.ink,
          unselectedLabelColor: c.inkSoft,
          indicatorColor: c.ink,
          indicatorWeight: 2,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: context.t('tabAll')),
            Tab(text: context.t('tabSubs')),
            Tab(text: context.t('tabReplies')),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.accent,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _notifList(c, _filtered(0)),
                  _notifList(c, _filtered(1)),
                  _notifList(c, _filtered(2)),
                ],
              ),
      ),
    );
  }

  Widget _notifList(BrutalColors c, List notifs) {
    if (notifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 52, color: c.inkSoft),
            const SizedBox(height: 14),
            Text(context.t('noNotifications'),
                style: TextStyle(color: c.inkSoft, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: notifs.length,
      itemBuilder: (_, i) {
        final n = notifs[i];
        final isRead = n['is_read'] == true;
        final createdAt =
            n['created_at'] != null ? DateTime.tryParse(n['created_at']) : null;

        return Container(
          decoration: BoxDecoration(
            color: isRead ? null : c.accent.withOpacity(0.05),
            border: Border(
              bottom: BorderSide(color: c.ink.withOpacity(0.05), width: 0.5),
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: c.surface2,
                  backgroundImage: n['from_avatar'] != null
                      ? CachedNetworkImageProvider(n['from_avatar'])
                      : null,
                  child: n['from_avatar'] == null
                      ? Icon(Icons.person, color: c.inkSoft, size: 20)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _icon(n['type'] ?? ''),
                      size: 11,
                      color: _iconColor(n['type'] ?? '', c),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              _notifText(n),
              style: TextStyle(
                fontSize: 14,
                color: c.ink,
                fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
            subtitle: createdAt != null
                ? Text(
                    timeago.format(createdAt),
                    style: TextStyle(color: c.inkSoft, fontSize: 12),
                  )
                : null,
            onTap: () async {
              if (!isRead) {
                await ApiService.markNotificationRead(n['id']);
                _load();
              }
              await _openNotif(n);
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
