import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../theme/brutal_theme.dart';
import 'video_circle_recorder_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final Map chat;
  final Map user;
  final Map? targetUser;
  const ChatDetailScreen(
      {super.key, required this.chat, required this.user, this.targetUser});
  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with TickerProviderStateMixin {
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
  double _dragOffset = 0;
  bool _dragCancelled = false;

  // Voice recording animation
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  // Audio playback
  final _audioPlayer = AudioPlayer();
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _initChat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
    );
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

  Future<void> _send(
      {String? text, String? mediaUrl, String type = 'text'}) async {
    final content = text ?? _msgCtrl.text.trim();
    if (content.isEmpty && mediaUrl == null) return;
    if (text == null) _msgCtrl.clear();
    await ApiService.sendMessage(_chatId!, widget.user['id'], content,
        mediaUrl: mediaUrl, messageType: type);
    _loadMessages();
  }

  // ─── PHOTO ────────────────────────────────────────────────────────────────

  Future<void> _sendPhoto() async {
    final c = context.k;
    final picker = ImagePicker();
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(
            leading: _iconBox(Icons.camera_alt_rounded, c),
            title: Text('Camera', style: TextStyle(color: c.ink)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: _iconBox(Icons.photo_library_rounded, c),
            title: Text('Gallery', style: TextStyle(color: c.ink)),
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

  // ─── VIDEO CIRCLE (Telegram-style custom camera) ─────────────────────────

  Future<void> _sendVideo() async {
    // Open the custom round camera screen
    final File? file = await Navigator.push<File>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const VideoCircleRecorderScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    if (file == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Отправляем видеокружок...')));
    final bytes = await file.readAsBytes();
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

  // ─── VOICE (Telegram-style: hold to record, slide to cancel) ──────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _pulseCtrl?.repeat(reverse: true);
    setState(() {
      _isRecording = true;
      _recordSecs = 0;
      _dragOffset = 0;
      _dragCancelled = false;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSecs++);
    });
  }

  void _updateDrag(double dx) {
    if (!_isRecording) return;
    setState(() {
      _dragOffset = dx.clamp(-150.0, 0.0);
      if (_dragOffset < -100) {
        _dragCancelled = true;
      }
    });
  }

  Future<void> _stopAndSendVoice() async {
    _recordTimer?.cancel();
    _pulseCtrl?.stop();
    _pulseCtrl?.reset();

    if (_dragCancelled) {
      await _recorder.cancel();
      setState(() => _isRecording = false);
      return;
    }

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
    _pulseCtrl?.stop();
    _pulseCtrl?.reset();
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
    final c = context.k;
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          if (msg['message_type'] == 'text' || msg['message_type'] == null)
            ListTile(
              leading: _iconBox(Icons.edit_rounded, c),
              title: Text('Edit', style: TextStyle(color: c.ink)),
              onTap: () {
                Navigator.pop(context);
                _editCtrl.text = msg['content'];
                setState(() => _editingId = msg['id']);
              },
            ),
          ListTile(
            leading: _iconBox(Icons.delete_rounded, c, color: c.danger),
            title: Text('Delete', style: TextStyle(color: c.danger)),
            onTap: () {
              Navigator.pop(context);
              ApiService.deleteMessage(msg['id'])
                  .then((_) => _loadMessages());
            },
          ),
        ]),
      ),
    );
  }

  Widget _iconBox(IconData icon, BrutalColors c, {Color? color}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
          color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color ?? c.accent, size: 20),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final chatName =
        widget.chat['name'] ?? widget.targetUser?['username'] ?? 'Chat';
    final chatAvatar =
        widget.chat['avatar'] ?? widget.targetUser?['avatar_url'];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          _CircleAvatar(url: chatAvatar, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(chatName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.ink)),
          ),
        ]),
        actions: [
          IconButton(
              icon: Icon(Icons.videocam_rounded, color: c.inkSoft),
              onPressed: () {}),
          IconButton(
              icon: Icon(Icons.call_rounded, color: c.inkSoft),
              onPressed: () {}),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator(
                      color: c.accent, strokeWidth: 2))
              : messages.isEmpty
                  ? Center(
                      child: Text('No messages yet',
                          style: TextStyle(color: c.inkSoft)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isOwn =
                            msg['sender_id'] == widget.user['id'];
                        return _buildMessageBubble(msg, isOwn, c);
                      },
                    ),
        ),

        // Edit banner
        if (_editingId != null)
          Container(
            color: c.surface,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Edit message',
                      style:
                          TextStyle(color: c.accent, fontSize: 13))),
              GestureDetector(
                  onTap: () {
                    setState(() => _editingId = null);
                    _editCtrl.clear();
                  },
                  child: Icon(Icons.close, color: c.inkSoft, size: 18)),
            ]),
          ),

        // Input area
        _buildInput(c),
      ]),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isOwn, BrutalColors c) {
    final type = msg['message_type'] ?? 'text';
    final mediaUrl = msg['media_url'] as String?;

    // Video circles are NOT wrapped in a bubble — they stand alone
    if (type == 'video') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isOwn)
              _CircleAvatar(
                  url: widget.targetUser?['avatar_url'], size: 24),
            if (!isOwn) const SizedBox(width: 6),
            _VideoCircle(url: mediaUrl ?? '', size: 200),
          ],
        ),
      );
    }

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
                  color: isOwn
                      ? c.accent.withOpacity(0.15)
                      : c.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isOwn ? 18 : 4),
                    bottomRight: Radius.circular(isOwn ? 4 : 18),
                  ),
                  border: isOwn
                      ? Border.all(
                          color: c.accent.withOpacity(0.25), width: 1)
                      : null,
                ),
                child: _buildBubbleContent(type, mediaUrl, msg, isOwn, c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(
      String type, String? mediaUrl, Map msg, bool isOwn, BrutalColors c) {
    final textColor = isOwn ? c.ink : c.ink;
    final dimColor = isOwn ? c.inkSoft : c.inkSoft;

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
                width: 220,
                height: 220,
                color: c.surface2,
                child: Center(
                    child: CircularProgressIndicator(
                        color: c.accent, strokeWidth: 2))),
          ),
        );

      case 'voice':
        final isPlaying = _playingUrl == mediaUrl;
        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: mediaUrl != null ? () => _playAudio(mediaUrl) : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: isOwn
                        ? c.accent.withOpacity(0.2)
                        : c.surface2,
                    shape: BoxShape.circle),
                child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: c.accent,
                    size: 22),
              ),
            ),
            const SizedBox(width: 10),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Waveform placeholder
              Row(children: List.generate(
                16,
                (i) => Container(
                  width: 3,
                  height: (4 + (i % 5) * 3).toDouble(),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? c.accent
                        : c.inkSoft.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
              const SizedBox(height: 4),
              Text(msg['content'] ?? '',
                  style: TextStyle(color: dimColor, fontSize: 11)),
            ]),
          ]),
        );

      default:
        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(msg['content'] ?? '',
                style: TextStyle(
                    color: textColor, fontSize: 15, height: 1.3)),
            if (msg['is_edited'] == true)
              Text('edited',
                  style: TextStyle(color: dimColor, fontSize: 10)),
          ]),
        );
    }
  }

  Widget _buildInput(BrutalColors c) {
    // ─── RECORDING STATE ──────────────────────────────────────────────────
    if (_isRecording) {
      return Container(
        color: c.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: SafeArea(
          top: false,
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => _updateDrag(d.delta.dx + _dragOffset),
            onHorizontalDragEnd: (_) {
              if (_dragCancelled) _cancelRecording();
            },
            child: Row(children: [
              // Pulsing red dot
              AnimatedBuilder(
                animation: _pulseAnim!,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.danger,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: c.danger.withOpacity(0.4),
                        blurRadius: 6 * (_pulseAnim?.value ?? 1),
                        spreadRadius: 2 * ((_pulseAnim?.value ?? 1) - 1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Timer
              Text(
                _formatDuration(_recordSecs),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),

              const Spacer(),

              // Slide to cancel hint
              AnimatedOpacity(
                opacity: _dragCancelled ? 0.3 : 0.7,
                duration: const Duration(milliseconds: 150),
                child: Transform.translate(
                  offset: Offset(_dragOffset * 0.3, 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_left_rounded,
                        color: c.inkSoft, size: 18),
                    Text('Slide to cancel',
                        style:
                            TextStyle(color: c.inkSoft, fontSize: 13)),
                  ]),
                ),
              ),

              const SizedBox(width: 12),

              // Stop & send button
              GestureDetector(
                onTap: _stopAndSendVoice,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      gradient: c.buttonGradient,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    // ─── NORMAL INPUT ───────────────────────────────────────────────────
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: SafeArea(
        top: false,
        child: Row(children: [
          // Attach photo
          GestureDetector(
            onTap: _sendPhoto,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.image_rounded, color: c.inkSoft, size: 22),
            ),
          ),
          // Record video circle (Telegram-style)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _sendVideo();
            },
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: c.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.videocam_rounded, color: c.accent, size: 20),
            ),
          ),

          const SizedBox(width: 4),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller:
                    _editingId != null ? _editCtrl : _msgCtrl,
                maxLines: null,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: InputDecoration(
                  hintText: _editingId != null
                      ? 'Edit message...'
                      : 'Message...',
                  hintStyle: TextStyle(color: c.inkSoft),
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        gradient: c.buttonGradient,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                );
              }
              // Mic button — long press to record (Telegram-style)
              return GestureDetector(
                onLongPressStart: (_) {
                  HapticFeedback.mediumImpact();
                  _startRecording();
                },
                onLongPressMoveUpdate: (d) =>
                    _updateDrag(d.localOffsetFromOrigin.dx),
                onLongPressEnd: (_) => _stopAndSendVoice(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_rounded, color: c.accent, size: 22),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  String _formatDuration(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordTimer?.cancel();
    _pulseCtrl?.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    SocketService().onMessageReceived = null;
    _msgCtrl.dispose();
    _editCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}

// ─── VIDEO CIRCLE WIDGET (Telegram-style) ─────────────────────────────────────

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
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: () {
        if (_ctrl == null) return;
        setState(() {
          _playing = !_playing;
          _playing ? _ctrl!.play() : _ctrl!.pause();
        });
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: c.storyGradient,
        ),
        padding: const EdgeInsets.all(3), // gradient ring border
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface2,
          ),
          clipBehavior: Clip.antiAlias,
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
                      color: Colors.black26,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  // Duration badge
                  if (_initialized)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _formatDuration(_ctrl!.value.duration),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                ])
              : Center(
                  child: CircularProgressIndicator(
                      color: c.accent, strokeWidth: 2)),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final c = context.k;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: c.surface2,
        child: url != null
            ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
            : Icon(Icons.person_rounded, color: c.inkSoft, size: size * 0.6),
      ),
    );
  }
}
