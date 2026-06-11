import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'chat_detail_screen.dart';
import 'select_user_screen.dart';

class ChatsScreen extends StatefulWidget {
  final Map user;
  const ChatsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List chats = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final data = await ApiService.getChats(widget.user['id']);
    if (mounted) setState(() => chats = data);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.ink,
        onPressed: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SelectUserScreen(user: widget.user)));
          _load();
        },
        child: const Icon(Icons.edit),
      ),
      body: chats.isEmpty
          ? Center(
              child: Text('No chats yet. Tap + to start',
                  style: TextStyle(color: c.inkSoft)))
          : ListView.builder(
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final chat = chats[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: chat['avatar'] != null
                        ? CircleAvatar(
                            backgroundImage:
                                CachedNetworkImageProvider(chat['avatar']))
                        : CircleAvatar(
                            backgroundColor: c.accent,
                            child: Icon(Icons.person, color: c.ink)),
                    title: Text(chat['name'] ?? 'Chat',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(chat['last_message'] ?? 'No messages',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.inkSoft)),
                    trailing: Icon(Icons.chevron_right,
                        color: c.inkSoft),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(
                                  chat: chat,
                                  user: widget.user,
                                  targetUser: {
                                    'id': chat['other_user_id'] ??
                                        (chat['user1_id'] == widget.user['id']
                                            ? chat['user2_id']
                                            : chat['user1_id'])
                                  },
                                ))),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
