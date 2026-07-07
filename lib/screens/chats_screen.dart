import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'chat_detail_screen.dart';
import 'ai_chat_screen.dart';

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
      appBar: AppBar(title: const Text('Чат')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _aiTile(c),
            Divider(height: 1, color: c.ink.withOpacity(0.06)),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()))
            else if (_chats.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    'Пока нет чатов.\nОткрой профиль человека и нажми «Написать».',
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

  Widget _aiTile(BrutalColors c) {
    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AiChatScreen(user: widget.user)),
      ),
      leading: Container(
        width: 46, height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            gradient: c.buttonGradient, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
      ),
      title: Row(children: [
        const Text('ИИ-ассистент',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Icon(Icons.push_pin, size: 13, color: c.inkSoft),
      ]),
      subtitle: Text('Твой коуч по целям · всегда на связи',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.inkSoft)),
      trailing: Icon(Icons.chevron_right, color: c.inkSoft),
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
      subtitle: Text(last.isEmpty ? 'Нет сообщений' : last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.inkSoft)),
      trailing: Icon(Icons.chevron_right, color: c.inkSoft),
    );
  }
}
