import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/api_service.dart';
import '../constants.dart';

class NotificationsScreen extends StatefulWidget {
  final Map user;
  const NotificationsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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
      default: return Icons.notifications;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'like': return Colors.red;
      case 'comment': return Colors.blue;
      case 'follow': return kGold;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['is_read'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark all read',
                    style: TextStyle(color: Colors.black, fontSize: 12))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kGold,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notifs.isEmpty
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(Icons.notifications_none,
                            size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No notifications yet',
                            style: TextStyle(color: Colors.grey)),
                      ]))
                : ListView.builder(
                    itemCount: _notifs.length,
                    itemBuilder: (_, i) {
                      final n = _notifs[i];
                      final isRead = n['is_read'] == true;
                      final createdAt = n['created_at'] != null
                          ? DateTime.tryParse(n['created_at'])
                          : null;
                      return Container(
                        color: isRead ? null : kGold.withOpacity(0.06),
                        child: ListTile(
                          leading: Stack(children: [
                            n['from_avatar'] != null
                                ? CircleAvatar(
                                    backgroundImage:
                                        CachedNetworkImageProvider(
                                            n['from_avatar']))
                                : const CircleAvatar(
                                    backgroundColor: kCard,
                                    child: Icon(Icons.person,
                                        color: Colors.grey)),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                    color: kDark, shape: BoxShape.circle),
                                child: Icon(_icon(n['type'] ?? ''),
                                    size: 12,
                                    color: _iconColor(n['type'] ?? '')),
                              ),
                            ),
                          ]),
                          title: Text(n['message'] ?? '',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold)),
                          subtitle: createdAt != null
                              ? Text(timeago.format(createdAt),
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12))
                              : null,
                          onTap: () async {
                            if (!isRead) {
                              await ApiService.markNotificationRead(n['id']);
                              _load();
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
