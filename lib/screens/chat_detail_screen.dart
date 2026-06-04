import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../constants.dart';

class ChatDetailScreen extends StatefulWidget {
  final Map chat;
  final Map user;
  final Map? targetUser;
  const ChatDetailScreen(
      {super.key, required this.chat, required this.user, this.targetUser});
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

  // Voice recording
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordSecs = 0;
  Timer? _recordTimer;

  // Audio playback
  final _audioPlayer = AudioPlayer();
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _initChat();
    SocketService().onMessageReceived = (data) {
      if (data['chat_id'] == _chatId && mounted) _loadMessages();
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
    final data = await ApiService.getOrCreateChat(widget.user['id'], user2Id);
    if (data['success'] == true) {
      _chatId = data['data']['id'];
      await _loadMessages();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) _loadMessages();
      });
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadMessages() async {
    if (_chatId == null) return;
    final data = await ApiService.getMessages(_chatId!);
    if (mounted) {
      setState(() => messages = data);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _send({String? text, String? mediaUrl, String type = 'text'}) async {
    final content = text ?? _msgCtrl.text.trim();
    if (content.isEmpty && mediaUrl == null) return;
    if (text == null) _msgCtrl.clear();
    await ApiService.sendMessage(_chatId!, widget.user['id'], content,
        mediaUrl: mediaUrl, messageType: type);
    _loadMessages();
  }

  // ─── PHOTO ────────────────────────────────────────────────────────────────

  Future<void> _sendPhoto() async {
    final picker = ImagePicker();
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(
            leading: _iconBox(Icons.camera_alt_rounded),
            title: const Text('Camera', style: TextStyle(color: kText)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: _iconBox(Icons.photo_library_rounded),
            title: const Text('Gallery', style: TextStyle(color: kText)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    final file = await picker.pickImage(
        source: src, maxWidth: 1080, imageQuality: 80);
    if (file == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Sending photo...')));
    final bytes = await File(file.path).readAsBytes();
    final fileName =
        '${widget.user['id']}_msg_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final res = await http.put(
      Uri.parse('$kSupabaseUrl/storage/v1/object/avatars/$fileName'),
      headers: {
        'Authorization': 'Bearer $kSupabaseKey',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final url =
          '$kSupabaseUrl/storage/v1/object/public/avatars/$fileName';
      await _send(text: '', mediaUrl: url, type: 'image');
    }
    messenger.hideCurrentSnackBar();
  }

  // ─── VIDEO CIRCLE ─────────────────────────────────────────────────────────

  Future<void> _sendVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30));
    if (file == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Sending video...')));
    final bytes = await File(file.path).readAsBytes();
    final fileName =
        '${widget.user['id']}_vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final res = await http.put(
      Uri.parse('$kSupabaseUrl/storage/v1/object/avatars/$fileName'),
      headers: {
        'Authorization': 'Bearer $kSupabaseKey',
        'Content-Type': 'video/mp4',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final url =
          '$kSupabaseUrl/storage/v1/object/public/avatars/$fileName';
      await _send(text: '', mediaUrl: url, type: 'video');
    }
    messenger.hideCurrentSnackBar();
  }

  // ─── VOICE ────────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() {
      _isRecording = true;
      _recordSecs = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSecs++);
    });
  }

  Future<void> _stopAndSendVoice() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Sending voice...')));
    final bytes = await File(path).readAsBytes();
    final fileName =
        '${widget.user['id']}_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final res = await http.put(
      Uri.parse('$kSupabaseUrl/storage/v1/object/avatars/$fileName'),
      headers: {
        'Authorization': 'Bearer $kSupabaseKey',
        'Content-Type': 'audio/m4a',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final url =
          '$kSupabaseUrl/storage/v1/object/public/avatars/$fileName';
      final dur = '${_recordSecs}s';
      await _send(text: dur, mediaUrl: url, type: 'voice');
    }
    messenger.hideCurrentSnackBar();
  }

  void _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.cancel();
    setState(() => _isRecording = false);
  }

  // ─── PLAYBACK ─────────────────────────────────────────────────────────────

  Future<void> _playAudio(String url) async {
    if (_playingUrl == url) {
      await _audioPlayer.stop();
      setState(() => _playingUrl = null);
    } else {
      setState(() => _playingUrl = url);
      await _audioPlayer.play(UrlSource(url));
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playingUrl = null);
      });
    }
  }

  // ─── MESSAGE OPTIONS ──────────────────────────────────────────────────────

  void _showOptions(Map msg) {
    if (msg['sender_id'] != widget.user['id']) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          if (msg['message_type'] == 'text' || msg['message_type'] == null)
            ListTile(
              leading: _iconBox(Icons.edit_rounded),
              title: const Text('Edit', style: TextStyle(color: kText)),
              onTap: () {
                Navigator.pop(context);
                _editCtrl.text = msg['content'];
                setState(() => _editingId = msg['id']);
              },
            ),
          ListTile(
            leading: _iconBox(Icons.delete_rounded, color: Colors.red.shade400),
            title: Text('Delete',
                style: TextStyle(color: Colors.red.shade400)),
            onTap: () {
              Navigator.pop(context);
              ApiService.deleteMessage(msg['id']).then((_) => _loadMessages());
            },
          ),
        ]),
      ),
    );
  }

  Widget _iconBox(IconData icon, {Color color = kAccentLit}) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: kSurface2, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatName =
        widget.chat['name'] ?? widget.targetUser?['username'] ?? 'Chat';
    final chatAvatar =
        widget.chat['avatar'] ?? widget.targetUser?['avatar_url'];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          _CircleAvatar(url: chatAvatar, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(chatName,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kText)),
          ),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.videocam_rounded, color: kMuted),
              onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.call_rounded, color: kMuted),
              onPressed: () {}),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: kAccent, strokeWidth: 2))
              : messages.isEmpty
                  ? const Center(
                      child: Text('No messages yet',
                          style: TextStyle(color: kDim)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isOwn =
                            msg['sender_id'] == widget.user['id'];
                        return _buildMessageBubble(msg, isOwn);
                      },
                    ),
        ),

        // Edit banner
        if (_editingId != null)
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(
                  width: 3, height: 32,
                  decoration: BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Edit message',
                      style: TextStyle(color: kAccentLit, fontSize: 13))),
              GestureDetector(
                  onTap: () {
                    setState(() => _editingId = null);
                    _editCtrl.clear();
                  },
                  child: const Icon(Icons.close, color: kDim, size: 18)),
            ]),
          ),

        // Input area
        _buildInput(),
      ]),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isOwn) {
    final type = msg['message_type'] ?? 'text';
    final mediaUrl = msg['media_url'] as String?;

    return GestureDetector(
      onLongPress: () => _showOptions(msg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment:
              isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isOwn)
              _CircleAvatar(
                  url: widget.targetUser?['avatar_url'], size: 28),
            if (!isOwn) const SizedBox(width: 6),

            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              child: Container(
                decoration: BoxDecoration(
                  color: isOwn ? kAccent : kSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isOwn ? 18 : 4),
                    bottomRight: Radius.circular(isOwn ? 4 : 18),
                  ),
                ),
                child: _buildBubbleContent(type, mediaUrl, msg, isOwn),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(
      String type, String? mediaUrl, Map msg, bool isOwn) {
    final textColor = isOwn ? Colors.white : kText;
    final dimColor = isOwn ? Colors.white60 : kDim;

    switch (type) {
      case 'image':
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: mediaUrl ?? '',
            width: 220,
            height: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
                width: 220, height: 220,
                color: kSurface2,
                child: const Center(
                    child: CircularProgressIndicator(
                        color: kAccent, strokeWidth: 2))),
          ),
        );

      case 'voice':
        final isPlaying = _playingUrl == mediaUrl;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: mediaUrl != null ? () => _playAudio(mediaUrl) : null,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: isOwn ? Colors.white24 : kSurface2,
                    shape: BoxShape.circle),
                child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: isOwn ? Colors.white : kAccentLit,
                    size: 22),
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 100, height: 2,
                  decoration: BoxDecoration(
                      color: isOwn ? Colors.white38 : kBorder,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 4),
              Text(msg['content'] ?? '',
                  style: TextStyle(color: dimColor, fontSize: 11)),
            ]),
          ]),
        );

      case 'video':
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _VideoCircle(url: mediaUrl ?? '', size: 180),
        );

      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(msg['content'] ?? '',
                style: TextStyle(color: textColor, fontSize: 15, height: 1.3)),
            if (msg['is_edited'] == true)
              Text('edited',
                  style: TextStyle(color: dimColor, fontSize: 10)),
          ]),
        );
    }
  }

  Widget _buildInput() {
    if (_isRecording) {
      return Container(
        color: kSurface,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.mic_rounded, color: kPink, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recording... ${_recordSecs}s',
              style: const TextStyle(color: kPink, fontSize: 15),
            ),
          ),
          TextButton(
              onPressed: _cancelRecording,
              child: const Text('Cancel',
                  style: TextStyle(color: kDim))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _stopAndSendVoice,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                  gradient: kButtonGradient, shape: BoxShape.circle),
              child: const Icon(Icons.stop_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ]),
      );
    }

    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: SafeArea(
        top: false,
        child: Row(children: [
          // Attach buttons
          GestureDetector(
            onTap: _sendPhoto,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.image_rounded, color: kAccentLit, size: 22),
            ),
          ),
          GestureDetector(
            onTap: _sendVideo,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.radio_button_checked_rounded,
                  color: kAccentLit, size: 22),
            ),
          ),

          const SizedBox(width: 4),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                  color: kSurface2, borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller: _editingId != null ? _editCtrl : _msgCtrl,
                maxLines: null,
                style: const TextStyle(color: kText, fontSize: 15),
                decoration: InputDecoration(
                  hintText: _editingId != null
                      ? 'Edit message...'
                      : 'Message...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send / Voice button
          ListenableBuilder(
            listenable: _editingId != null ? _editCtrl : _msgCtrl,
            builder: (_, __) {
              final hasText = (_editingId != null
                      ? _editCtrl.text
                      : _msgCtrl.text)
                  .trim()
                  .isNotEmpty;
              if (hasText) {
                return GestureDetector(
                  onTap: _editingId != null
                      ? () async {
                          await ApiService.editMessage(
                              _editingId!, _editCtrl.text);
                          setState(() => _editingId = null);
                          _editCtrl.clear();
                          _loadMessages();
                        }
                      : _send,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                        gradient: kButtonGradient,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                );
              }
              return GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopAndSendVoice(),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: kSurface2, shape: BoxShape.circle),
                  child: const Icon(Icons.mic_rounded,
                      color: kMuted, size: 22),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    SocketService().onMessageReceived = null;
    _msgCtrl.dispose();
    _editCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}

// ─── VIDEO CIRCLE WIDGET ──────────────────────────────────────────────────────

class _VideoCircle extends StatefulWidget {
  final String url;
  final double size;
  const _VideoCircle({required this.url, required this.size});
  @override
  State<_VideoCircle> createState() => _VideoCircleState();
}

class _VideoCircleState extends State<_VideoCircle> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_ctrl == null) return;
        setState(() {
          _playing = !_playing;
          _playing ? _ctrl!.play() : _ctrl!.pause();
        });
      },
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: ClipOval(
          child: _initialized
              ? Stack(fit: StackFit.expand, children: [
                  FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                          width: _ctrl!.value.size.width,
                          height: _ctrl!.value.size.height,
                          child: VideoPlayer(_ctrl!))),
                  if (!_playing)
                    Container(
                      color: Colors.black38,
                      child: const Center(
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 40)),
                    ),
                ])
              : Container(
                  color: kSurface2,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: kAccent, strokeWidth: 2))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }
}

class _CircleAvatar extends StatelessWidget {
  final String? url;
  final double size;
  const _CircleAvatar({this.url, required this.size});
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: size, height: size, color: kSurface2,
        child: url != null
            ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
            : Icon(Icons.person_rounded, color: kMuted, size: size * 0.6),
      ),
    );
  }
}
