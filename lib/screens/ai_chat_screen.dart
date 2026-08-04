import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import '../services/pro_state.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/pro_upsell_sheet.dart';

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
  // '__greeting__' is rendered as the localized aiGreeting string.
  List<Map<String, String>> _messages = [
    {'role': 'model', 'text': '__greeting__'},
  ];
  bool _sending = false;

  // Voice mode — Pro-only. Text chat above stays free and unlimited exactly
  // as it already was; talking out loud and hearing her reply is the paid
  // add-on. Both speech_to_text and flutter_tts run through the OS's own
  // engine (no extra API, nothing to download), so the only thing that
  // actually costs anything is the existing /api/ai/chat call itself.
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  bool _speechReady = false;
  bool _listening = false;
  bool _voiceMode = false;

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
    if (_voiceMode) {
      _tts.setLanguage(appConfig.value.lang == 'ru' ? 'ru-RU' : 'en-US');
      _tts.speak(reply);
    }
  }

  void _showVoiceUpsell() {
    showProUpsell(context,
        user: widget.user,
        icon: Icons.graphic_eq_rounded,
        body: context.t('aiVoiceProOnly'));
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    return _speechReady;
  }

  Future<void> _toggleMic() async {
    if (!ProState.isPro.value) {
      _showVoiceUpsell();
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _ensureSpeechReady();
    if (!mounted) return;
    if (!ready) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('aiMicDenied'))));
      return;
    }
    setState(() => _listening = true);
    _speech.listen(
      listenOptions: SpeechListenOptions(
          localeId: appConfig.value.lang == 'ru' ? 'ru-RU' : 'en-US'),
      onResult: (result) {
        if (!mounted) return;
        _ctrl.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
          if (result.recognizedWords.trim().isNotEmpty) _send();
        }
      },
    );
  }

  void _toggleVoiceMode() {
    if (!ProState.isPro.value) {
      _showVoiceUpsell();
      return;
    }
    setState(() => _voiceMode = !_voiceMode);
    if (!_voiceMode) _tts.stop();
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
          Text(context.t('aiAssistant')),
        ]),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: ProState.isPro,
            builder: (_, isPro, __) => IconButton(
              tooltip: context.t('aiVoiceMode'),
              icon: Stack(clipBehavior: Clip.none, children: [
                Icon(_voiceMode
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded),
                if (!isPro)
                  Positioned(
                    right: -2, top: -2,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: c.accent, shape: BoxShape.circle),
                    ),
                  ),
              ]),
              onPressed: _toggleVoiceMode,
            ),
          ),
        ],
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
                final txt = m['text'] == '__greeting__'
                    ? context.t('aiGreeting')
                    : m['text']!;
                return _bubble(c, m['role']!, txt);
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
          typing ? context.t('typing') : text,
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
              decoration: InputDecoration(
                  hintText: _listening
                      ? context.t('aiListening')
                      : context.t('aiAskHint'),
                  isDense: true),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _toggleMic,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _listening ? c.accent : c.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _listening ? Colors.white : c.inkSoft),
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
    if (_listening) _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
