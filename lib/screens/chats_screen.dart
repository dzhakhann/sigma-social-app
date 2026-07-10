import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'chat_detail_screen.dart';

/// Built-in chat list (our own server). Pinned AI assistant on top.
class ChatsScreen extends StatefulWidget {
  final Map user;
  const ChatsScreen({super.key, required this.user});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getChats(widget.user['id'].toString());
    if (mounted) setState(() { _chats = data; _loading = false; });
  }

  void _openChat(Map chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChatDetailScreen(chat: chat, user: widget.user)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('chatTitle'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()))
            else if (_chats.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    context.t('noChats'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.inkSoft, height: 1.4),
                  ),
                ),
              )
            else
              ..._chats.map((chat) => _chatTile(c, chat)),
          ],
        ),
      ),
    );
  }

  Widget _chatTile(BrutalColors c, Map chat) {
    final name = (chat['name'] ?? 'User').toString();
    final avatar = chat['avatar'];
    final last = (chat['last_message'] ?? '').toString();
    return ListTile(
      onTap: () => _openChat(chat),
      leading: CircleAvatar(
        radius: 23,
        backgroundColor: c.surface2,
        backgroundImage:
            avatar != null ? CachedNetworkImageProvider(avatar.toString()) : null,
        child: avatar == null ? Icon(Icons.person, color: c.inkSoft) : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(last.isEmpty ? context.t('noMsgsShort') : last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.inkSoft)),
      trailing: Icon(Icons.chevron_right, color: c.inkSoft),
    );
  }
}
