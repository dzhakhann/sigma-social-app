import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../constants.dart';

class ChatDetailScreen extends StatefulWidget {
  final Map chat;
  final Map user;
  final Map? targetUser;
  const ChatDetailScreen(
      {Key? key, required this.chat, required this.user, this.targetUser})
      : super(key: key);
  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List messages = [];
  bool isLoading = false;
  String? _chatId;
  String? _editingId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initChat();
    SocketService().onMessageReceived = (data) {
      if (data['chat_id'] == _chatId && mounted) {
        _loadMessages();
      }
    };
  }

  Future<void> _initChat() async {
    setState(() => isLoading = true);
    final user2Id = widget.targetUser?['id'] ??
        widget.chat['user2_id'] ??
        widget.chat['other_user_id'];
    if (user2Id == null) {
      setState(() => isLoading = false);
      return;
    }
    final data =
        await ApiService.getOrCreateChat(widget.user['id'], user2Id);
    if (data['success'] == true) {
      _chatId = data['data']['id'];
      await _loadMessages();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) _loadMessages();
      });
    }
    setState(() => isLoading = false);
  }

  Future<void> _loadMessages() async {
    if (_chatId == null) return;
    final data = await ApiService.getMessages(_chatId!);
    if (mounted) {
      setState(() => messages = data);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _chatId == null) return;
    _msgCtrl.clear();
    await ApiService.sendMessage(_chatId!, widget.user['id'], text);
    _loadMessages();
  }

  Future<void> _delete(String id) async {
    await ApiService.deleteMessage(id);
    _loadMessages();
  }

  Future<void> _edit(String id, String content) async {
    await ApiService.editMessage(id, content);
    setState(() => _editingId = null);
    _editCtrl.clear();
    _loadMessages();
  }

  void _showOptions(Map message) {
    if (message['sender_id'] != widget.user['id']) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: kGold),
            title: const Text('Edit message'),
            onTap: () {
              Navigator.pop(context);
              _editCtrl.text = message['content'];
              setState(() => _editingId = message['id']);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title:
                const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _delete(message['id']);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatName =
        widget.chat['name'] ?? widget.targetUser?['username'] ?? 'Chat';
    final chatAvatar =
        widget.chat['avatar'] ?? widget.targetUser?['avatar_url'];

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          chatAvatar != null
              ? CircleAvatar(
                  radius: 18,
                  backgroundImage: CachedNetworkImageProvider(chatAvatar))
              : const CircleAvatar(
                  radius: 18,
                  backgroundColor: kBorder,
                  child: Icon(Icons.person, color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Text(chatName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? const Center(
                      child: Text('No messages yet',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isOwn = msg['sender_id'] == widget.user['id'];
                        final isEdited = msg['is_edited'] == true;
                        return GestureDetector(
                          onLongPress: () => _showOptions(msg),
                          child: Align(
                            alignment: isOwn
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width *
                                          0.75),
                              decoration: BoxDecoration(
                                color: isOwn ? kGold : kBorder,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(msg['content'] ?? '',
                                        style: TextStyle(
                                            color: isOwn
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 15)),
                                    if (isEdited)
                                      Text('edited',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: isOwn
                                                  ? Colors.black54
                                                  : Colors.grey)),
                                  ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_editingId != null)
          Container(
            color: kCard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Icon(Icons.edit, color: kGold, size: 16),
              const SizedBox(width: 8),
              const Text('Editing message',
                  style: TextStyle(color: kGold, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                  onTap: () {
                    setState(() => _editingId = null);
                    _editCtrl.clear();
                  },
                  child:
                      const Icon(Icons.close, color: Colors.grey, size: 16)),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          color: kDark,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller:
                    _editingId != null ? _editCtrl : _msgCtrl,
                decoration: InputDecoration(
                    hintText: _editingId != null
                        ? 'Edit message...'
                        : 'Type message...'),
                maxLines: null,
                onSubmitted: (_) =>
                    _editingId != null ? _edit(_editingId!, _editCtrl.text) : _send(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _editingId != null
                  ? () => _edit(_editingId!, _editCtrl.text)
                  : _send,
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size(56, 48)),
              child: Icon(
                  _editingId != null ? Icons.check : Icons.send,
                  color: Colors.black),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    SocketService().onMessageReceived = null;
    _msgCtrl.dispose();
    _editCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
