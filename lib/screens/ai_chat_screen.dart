import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/emoji_picker.dart';

/// Chat with the Sigmacta AI assistant (goal coach). Talks to /api/ai/chat.
class AiChatScreen extends StatefulWidget {
  final Map user;
  const AiChatScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  // Each: {'role': 'user'|'model', 'text': '...'}
  List<Map<String, String>> _messages = [
    {
      'role': 'model',
      'text':
          'Привет! Я твой ИИ-коуч Sigmacta. Расскажи о своей цели — помогу '
              'разбить её на шаги и подскажу, с чего начать.',
    },
  ];
  bool _sending = false;

  String get _key => 'ai_chat_${widget.user['id']}';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key);
      if (s != null) {
        final list = (jsonDecode(s) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
        if (list.isNotEmpty && mounted) setState(() => _messages = list);
      }
    } catch (_) {}
    _scrollDown();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_messages));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _sending = true;
      _ctrl.clear();
    });
    _scrollDown();
    final reply = await ApiService.aiChat(_messages);
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'model', 'text': reply});
      _sending = false;
    });
    _save();
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 30, height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: c.buttonGradient,
                borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('ИИ-ассистент'),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) {
                  return _bubble(c, 'model', '…', typing: true);
                }
                final m = _messages[i];
                return _bubble(c, m['role']!, m['text']!);
              },
            ),
          ),
          _composer(c),
        ],
      ),
    );
  }

  Widget _bubble(BrutalColors c, String role, String text, {bool typing = false}) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? c.accent : c.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          typing ? 'печатает…' : text,
          style: TextStyle(
              color: isUser ? Colors.white : c.ink, fontSize: 15, height: 1.35),
        ),
      ),
    );
  }

  Widget _composer(BrutalColors c) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.ink.withOpacity(0.06))),
        ),
        child: Row(children: [
          EmojiPickerButton(controller: _ctrl),
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                  hintText: 'Спроси о своей цели…', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: c.accent, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
