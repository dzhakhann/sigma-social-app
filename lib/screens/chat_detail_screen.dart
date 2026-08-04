import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'package:cached_network_image/cached_network_image.dart';
import 'sigma_gallery_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/active_chat.dart';
import '../services/api_service.dart';
import '../services/chat_sounds.dart';
import '../services/chat_mute.dart';
import '../services/chat_store.dart';
import '../services/chat_wallpaper.dart';
import '../services/socket_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../l10n/human_time.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_context_menu.dart';
import '../widgets/chat_extras_panel.dart';
import '../widgets/link_preview.dart';
import '../widgets/pinned_bar.dart';
import 'pro_screen.dart';
import '../widgets/wallpaper_picker.dart';
import '../widgets/chat_background.dart';
import '../widgets/chat_date_divider.dart';
import '../widgets/pro_badge.dart';
import '../widgets/verified_badge.dart';
import '../widgets/voice_bubble.dart';
import 'video_circle_recorder_screen.dart';
import 'profile_screen.dart';

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
  final _msgFocus = FocusNode();
  bool _showEmoji = false;
  Map? _targetInfo; // for online/last-seen status
  List messages = [];
  bool isLoading = false;
  String? _chatId;
  String? _editingId;
  Timer? _timer;
  StreamSubscription? _msgSub;
  // Telegram-style: unfurl a link WHILE typing, not just after sending.
  String? _liveLinkUrl;
  Timer? _linkDebounce;
  StreamSubscription? _readSub;
  StreamSubscription? _deliveredSub;
  StreamSubscription? _pinSub;

  /// Pinned-message snapshot for this chat (null = nothing pinned).
  Map? _pinned;

  /// Multi-select mode: ids of the messages currently ticked.
  final Set<String> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;
  StreamSubscription? _reactionSub;
  Map? _wallpaper;
  bool _muted = false;

  // In-chat search (Telegram-style ⋮ menu action) — searches messages
  // already loaded on this device, since that's the only history we have.
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();
  List<int> _searchMatches = [];
  int _searchIndex = -1;

  /// Compose-time reply target: a small self-contained snapshot (NOT a live
  /// reference), shown as the quoted bar above the input and baked into the
  /// next sent message's `reply_to`.
  Map? _replyTo;

  /// Briefly highlighted after "scroll to original" (tapping a quote).
  String? _flashId;

  /// One GlobalKey per rendered bubble — lets the context menu snapshot the
  /// bubble's exact on-screen rect, and lets quotes scroll back to it.
  final Map<String, GlobalKey> _bubbleKeys = {};

  // Voice recording lives in ChatComposer (shared with group chat).

  // Audio playback
  final _audioPlayer = AudioPlayer();
  String? _playingUrl;

  /// Subscribed ONCE. Re-listening inside `_playAudio` added a fresh
  /// subscription on every playback, and none of them were ever cancelled.
  StreamSubscription? _playbackDoneSub;

  @override
  void initState() {
    super.initState();
    _initChat();
    _playbackDoneSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
    // Realtime: the server pushes new messages to the two participants over
    // the socket — the 12s poll below is only a safety net. Connection is
    // actually established app-wide in MainScreen (so read receipts and
    // incoming messages are captured even while sitting on the chat list) —
    // this call is a no-op if already connected. Streams (not a single
    // callback) so this screen's listener doesn't clobber MainScreen's.
    SocketService().connect(widget.user['id'].toString());
    _msgSub = SocketService().onMessage.listen((data) {
      if (data['chat_id']?.toString() == _chatId && mounted) {
        _onIncoming(Map.from(data));
      }
    });
    // They opened the chat → my copies go to ✓✓ in accent (read). Reading
    // implies delivery, so set both.
    _readSub = SocketService().onRead.listen((data) {
      if (data['chatId']?.toString() != _chatId || !mounted) return;
      // Emitted to BOTH participants — ignore my own read, otherwise simply
      // opening the chat marked everything I had sent as read by them.
      if (data['reader']?.toString() == widget.user['id'].toString()) return;
      setState(() {
        for (final m in messages) {
          if (m is Map &&
              m['sender_id']?.toString() == widget.user['id'].toString()) {
            m['is_read'] = true;
            m['delivered'] = true;
          }
        }
      });
      _saveCache();
    });
    // Their phone picked the messages up but hasn't opened the chat → plain
    // ✓✓. Only the listed ids, unlike read which settles the whole chat.
    _deliveredSub = SocketService().onDelivered.listen((data) {
      if (data['chatId']?.toString() != _chatId || !mounted) return;
      final ids = ((data['ids'] as List?) ?? []).map((e) => e.toString()).toSet();
      if (ids.isEmpty) return;
      setState(() {
        for (final m in messages) {
          if (m is Map && ids.contains(m['id']?.toString())) {
            m['delivered'] = true;
          }
        }
      });
      _saveCache();
    });
    _reactionSub = SocketService().onMessageReaction.listen((data) {
      if (data['chat_id']?.toString() != _chatId || !mounted) return;
      final msgId = data['message_id']?.toString();
      if (msgId == null) return;
      var changed = false;
      setState(() {
        for (final m in messages) {
          if (m['id'].toString() == msgId) {
            m['reactions'] = Map<String, dynamic>.from(data['reactions'] ?? {});
            changed = true;
          }
        }
      });
      // See the group version: an unconditional save from a socket handler can
      // write an empty list over the on-device archive.
      if (changed) _saveCache();
    });
    ActiveChat.openChat(_chatId);
    _pinSub = SocketService().onChatPin.listen((data) {
      if (data['chat_id']?.toString() != _chatId || !mounted) return;
      setState(() => _pinned = data['pinned_message'] as Map?);
    });
    _msgCtrl.addListener(_onComposerTextChanged);
    // The pin travels on the chat row itself, so it's already here.
    _pinned = widget.chat['pinned_message'] as Map?;
  }

  /// Pin/unpin. Both directions go through the same endpoint — passing null
  /// unpins — and the snapshot is built here because the server deliberately
  /// keeps only the few fields the pinned bar renders.
  Future<void> _togglePin(Map msg) async {
    if (_chatId == null) return;
    final id = msg['id'].toString();
    final unpin = _pinned != null && _pinned!['id']?.toString() == id;
    final snap = unpin
        ? null
        : {
            'id': id,
            'sender_id': msg['sender_id'],
            'sender_name':
                msg['sender_id']?.toString() == widget.user['id'].toString()
                    ? _myName
                    : _otherName,
            'content': msg['content'],
            'message_type': msg['message_type'] ?? 'text',
            'created_at': msg['created_at'],
          };
    setState(() => _pinned = snap); // optimistic — the socket confirms
    await ApiService.pinChatMessage(_chatId!, snap);
  }

  void _onComposerTextChanged() {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final url = firstUrl(_msgCtrl.text);
      if (url != _liveLinkUrl) setState(() => _liveLinkUrl = url);
    });
  }

  /// Appends a socket-delivered message without a full reload, stores it on
  /// device and ACKs — the server then deletes its copy (device-stored
  /// history; the DB is just the in-flight queue).
  void _onIncoming(Map msg) {
    final id = msg['id']?.toString();
    if (id == null) return;
    if (messages.any((m) => m['id']?.toString() == id)) return;
    setState(() => messages = [...messages, msg]);
    _saveCache();
    // Only somebody else's message earns a receive blip — my own comes back
    // over the socket too, and it already made a send sound.
    if (msg['sender_id']?.toString() != widget.user['id'].toString()) {
      ChatSounds.received();
    }
    _scrollToBottom();
    if (msg['sender_id']?.toString() != widget.user['id'].toString()) {
      ApiService.ackMessages(_chatId!, [id]);
    }
  }

  void _saveCache() {
    if (_chatId == null) return;
    // Never persist optimistic placeholders. A `voice_…` row points at a temp
    // file that won't exist next launch, and a `tmp_…` row has no server id —
    // persisting either leaves a permanently broken bubble in the history,
    // which is how a failed upload turned into a blank gap that survived
    // restarts.
    final durable = messages
        .where((m) {
          final id = m['id']?.toString() ?? '';
          return !id.startsWith('voice_') && !id.startsWith('tmp_');
        })
        .toList();
    ChatStore.save(_chatId!, durable);
  }

  /// Refreshes reactions/read-status for cached messages — catches up on
  /// anything that changed while this screen wasn't open to catch the live
  /// socket event (device-stored history has no server-side backlog to
  /// replay otherwise). Best-effort; a failed sync just leaves the cache as
  /// it was until the next successful one.
  Future<void> _syncMeta() async {
    final ids = messages
        .whereType<Map>()
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => !id.startsWith('tmp_'))
        .toList();
    if (ids.isEmpty) return;
    final meta = await ApiService.syncMessages(ids);
    if (meta.isEmpty || !mounted) return;
    setState(() {
      for (final m in messages) {
        final id = m['id']?.toString();
        final mm = id == null ? null : meta[id];
        if (mm != null) {
          if (mm['is_read'] != null) m['is_read'] = mm['is_read'];
          if (mm['delivered'] != null) m['delivered'] = mm['delivered'];
          m['reactions'] = mm['reactions'] ?? {};
        }
      }
    });
    _saveCache();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  /// Drops keys for messages that have left the list. Without this the map
  /// grew forever: every optimistic `tmp_…` id orphans its entry the moment
  /// the server id replaces it, and deleted messages never released theirs.
  void _pruneBubbleKeys() {
    if (_bubbleKeys.length <= messages.length) return;
    final live = messages.map((m) => m['id'].toString()).toSet();
    _bubbleKeys.removeWhere((id, _) => !live.contains(id));
  }

  /// Tapping a quoted reply jumps to (and briefly highlights) the original
  /// bubble — only works while it's still in THIS device's local history.
  void _scrollToMessage(String id) {
    final ctx = _bubbleKeys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.5);
    setState(() => _flashId = id);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _flashId == id) setState(() => _flashId = null);
    });
  }

  // ─── Search in chat (Telegram-style ⋮ menu) ────────────────────────────────
  // Searches messages already on THIS device — that's the only history we
  // have (server only ever holds the undelivered queue).

  void _toggleSearch() {
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchCtrl.clear();
        _searchMatches = [];
        _searchIndex = -1;
      }
    });
    if (_searchMode)
      WidgetsBinding.instance.addPostFrameCallback((_) => _msgFocus.unfocus());
  }

  void _runSearch(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchMatches = [];
        _searchIndex = -1;
      });
      return;
    }
    final matches = <int>[];
    for (var i = 0; i < messages.length; i++) {
      final content = (messages[i]['content'] ?? '').toString().toLowerCase();
      if (content.contains(query)) matches.add(i);
    }
    setState(() {
      _searchMatches = matches;
      _searchIndex = matches.isEmpty ? -1 : matches.length - 1;
    });
    if (_searchIndex >= 0) _jumpToMatch();
  }

  void _jumpToMatch() {
    if (_searchIndex < 0 || _searchIndex >= _searchMatches.length) return;
    final msg = messages[_searchMatches[_searchIndex]];
    _scrollToMessage(msg['id'].toString());
  }

  void _stepMatch(int delta) {
    if (_searchMatches.isEmpty) return;
    setState(() => _searchIndex =
        (_searchIndex + delta).clamp(0, _searchMatches.length - 1));
    _jumpToMatch();
  }

  // ─── Chat ⋮ menu: mute, clear history, delete chat ─────────────────────────

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    await ChatMute.setMuted(_chatId!, next);
  }

  Future<void> _confirmClearHistory() async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('clearHistoryTitle')),
        content: Text(context.t('clearHistoryBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(context.t('clearBtn'),
                  style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true || _chatId == null) return;
    await ChatStore.clear(_chatId!);
    if (mounted) setState(() => messages = []);
  }

  Future<void> _confirmDeleteChat() async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('deleteChatTitle')),
        content: Text(context.t('deleteChatBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(context.t('deleteBtn'),
                  style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true || _chatId == null) return;
    await ChatStore.clear(_chatId!);
    await ApiService.deleteChat(_chatId!);
    if (mounted) Navigator.pop(context);
  }

  /// The display name to attribute a quoted message to.
  String get _myName =>
      (widget.user['username'] ?? context.t('youLabel')).toString();
  String get _otherName => (widget.targetUser?['username'] ??
          _targetInfo?['username'] ??
          widget.chat['name'] ??
          '')
      .toString();

  void _setReplyTo(Map msg) {
    final me = widget.user['id'].toString();
    setState(() {
      _replyTo = {
        'id': msg['id'].toString(),
        'sender_name': msg['sender_id']?.toString() == me
            ? context.t('youLabel')
            : _otherName,
        'content': (msg['content'] ?? '').toString(),
        'type': (msg['message_type'] ?? 'text').toString(),
        'media_url': msg['media_url'],
      };
      _editingId = null; // mutually exclusive with editing
    });
    _msgFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);

  /// One-line preview for a quote/reply-bar snippet, based on message type.
  String _quoteSnippet(Map data) {
    switch ((data['type'] ?? 'text').toString()) {
      case 'image':
        return '📷 ${context.t('photoLabel')}';
      case 'voice':
        return '🎤 ${context.t('voiceLabel')}';
      case 'gif':
      case 'sticker':
        return 'GIF';
      default:
        return (data['content'] ?? '').toString();
    }
  }

  /// The OTHER participant of this chat. `user2_id` is whoever was invited
  /// when the chat was created — if THEY started the chat, user2 is ME, which
  /// used to open my own profile and show my own status. Always resolve
  /// against my id.
  String? get _otherId {
    final me = widget.user['id'].toString();
    final candidates = [
      widget.targetUser?['id'],
      widget.chat['other_user_id'],
      widget.chat['user1_id'],
      widget.chat['user2_id'],
    ];
    for (final c in candidates) {
      if (c != null && c.toString() != me) return c.toString();
    }
    return null;
  }

  Future<void> _initChat() async {
    final user2Id = _otherId;
    // Opened from the chat list → the id is already known: render the DEVICE
    // history instantly and skip the get-or-create round-trip entirely.
    _chatId = widget.chat['id']?.toString();
    if (_chatId != null) {
      final local = await ChatStore.load(_chatId!);
      if (local.isNotEmpty && mounted) {
        setState(() => messages = local);
        _scrollToBottom(animated: false);
        _syncMeta();
      } else {
        setState(() => isLoading = true);
      }
    } else {
      setState(() => isLoading = true);
    }
    if (user2Id != null) _refreshStatus(user2Id);

    if (_chatId == null) {
      if (user2Id == null) {
        setState(() => isLoading = false);
        return;
      }
      final data = await ApiService.getOrCreateChat(widget.user['id'], user2Id);
      if (data['success'] == true && mounted) {
        _chatId = data['data']['id'].toString();
      }
    }
    if (_chatId == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }
    _loadWallpaper();
    ChatMute.isMuted(_chatId!).then((m) {
      if (mounted) setState(() => _muted = m);
    });
    await _loadMessages();
    if (mounted) setState(() => isLoading = false);
    // Fallback poll only — realtime comes over the socket.
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) {
        _loadMessages();
        if (user2Id != null) _refreshStatus(user2Id);
      }
    });
  }

  Future<void> _refreshStatus(String targetId) async {
    final d = await ApiService.getUser(targetId);
    if (d['success'] == true && mounted) {
      setState(() => _targetInfo = d['data']);
    }
  }

  String _statusLabel() {
    final ls = _targetInfo?['last_seen'];
    if (ls == null) return '';
    try {
      return HumanTime.lastSeen(
          context, ApiService.parseServerTime(ls.toString()));
    } catch (_) {
      return '';
    }
  }


  bool get _isOnline {
    final ls = _targetInfo?['last_seen'];
    if (ls == null) return false;
    try {
      return DateTime.now()
              .difference(ApiService.parseServerTime(ls.toString()))
              .inSeconds <
          70;
    } catch (_) {
      return false;
    }
  }

  // ─── WALLPAPER (Telegram-style chat background) ───────────────────────────

  Future<void> _loadWallpaper() async {
    if (_chatId == null) return;
    final w = await ChatWallpaper.get(_chatId!);
    if (mounted) setState(() => _wallpaper = w);
  }

  Future<void> _openWallpaperPicker() async {
    final chatId = _chatId;
    if (chatId == null) return;
    final picked = await showWallpaperPicker(
      context,
      allowGallery: true,
      onPickGallery: _pickWallpaperPhoto,
      onOpenPro: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProScreen(user: widget.user))),
    );
    if (picked == null) return; // dismissed
    // An empty map means "reset"; null storage clears the key.
    final w = picked.isEmpty ? null : picked;
    await ChatWallpaper.set(chatId, w);
    if (mounted) setState(() => _wallpaper = w);
  }

  Future<void> _pickWallpaperPhoto() async {
    final chatId = _chatId;
    if (chatId == null) return;
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (img == null) return;
    Map w;
    if (kIsWeb) {
      // No filesystem to copy a permanent file into (path_provider has no web
      // build) — the bytes themselves go into SharedPreferences instead,
      // same as everything else this device stores for itself on web.
      final bytes = await img.readAsBytes();
      w = {'type': 'image', 'dataB64': base64Encode(bytes)};
    } else {
      // Copied into app documents: the picker's temp path is not guaranteed to
      // survive, and this wallpaper has to still resolve on the next launch.
      final dir = await getApplicationDocumentsDirectory();
      final dest =
          '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(img.path).copy(dest);
      w = {'type': 'image', 'path': dest};
    }
    await ChatWallpaper.set(chatId, w);
    if (mounted) setState(() => _wallpaper = w);
  }

  // Tapping the chat header opens the person's profile (Telegram-style),
  // with a smooth fade + scale ("expand from header") transition.
  void _openTargetProfile() {
    final id = _otherId;
    if (id == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (_, __, ___) => ProfileScreen(
          user: widget.user,
          targetUserId: id,
          isOwnProfile: false,
        ),
        transitionsBuilder: (_, a, __, child) {
          final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// Device-stored history model: the server only holds messages this phone
  /// hasn't confirmed yet. Fetch the queue, MERGE it into the local history
  /// (never replace — the server no longer has the old messages), store, and
  /// ACK the foreign ones so the server can drop its rows.
  Future<void> _loadMessages() async {
    if (_chatId == null) return;
    final queued = await ApiService.getMessages(_chatId!);
    if (!mounted) return;
    final me = widget.user['id'].toString();
    final known = messages
        .whereType<Map>()
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toSet();
    final fresh = queued
        .whereType<Map>()
        .where((m) => !known.contains(m['id']?.toString()))
        .map((m) => Map.from(m))
        .toList();
    // My own queued rows (other phone hasn't picked them up yet) may already
    // be in the local list from the optimistic send — they're filtered above.
    if (fresh.isNotEmpty) {
      setState(() {
        messages = [...messages, ...fresh]..sort((a, b) =>
            ((a as Map)['created_at'] ?? '')
                .toString()
                .compareTo(((b as Map)['created_at'] ?? '').toString()));
      });
      _saveCache();
      _scrollToBottom();
    }
    final ackIds = fresh
        .where((m) => m['sender_id']?.toString() != me)
        .map((m) => m['id'].toString())
        .toList();
    ApiService.ackMessages(_chatId!, ackIds);
  }

  /// Optimistic send: the bubble appears INSTANTLY (marked pending), then is
  /// swapped for the server row — the input never waits for the network.
  Future<void> _send(
      {String? text, String? mediaUrl, String type = 'text'}) async {
    final content = text ?? _msgCtrl.text.trim();
    if (content.isEmpty && mediaUrl == null) return;
    if (text == null) {
      _msgCtrl.clear();
      _linkDebounce?.cancel();
      if (_liveLinkUrl != null) setState(() => _liveLinkUrl = null);
    }
    if (_chatId == null) return;
    final replyTo = _replyTo; // snapshot, then clear the compose bar
    if (replyTo != null) setState(() => _replyTo = null);
    final temp = {
      'id': 'tmp_${DateTime.now().microsecondsSinceEpoch}',
      'chat_id': _chatId,
      'sender_id': widget.user['id'].toString(),
      'content': content,
      'message_type': type,
      'media_url': mediaUrl,
      'reply_to': replyTo,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
      '_pending': true,
    };
    setState(() => messages = [...messages, temp]);
    // Fires on the optimistic row, not after the server replies — the sound
    // should land with the bubble, not a network round-trip later.
    ChatSounds.sent();
    _scrollToBottom();
    Map r;
    try {
      r = await ApiService.sendMessage(_chatId!, widget.user['id'], content,
          mediaUrl: mediaUrl, messageType: type, replyTo: replyTo);
    } catch (_) {
      r = {'success': false};
    }
    if (!mounted) return;
    setState(() {
      final i = messages.indexWhere((m) => m['id'] == temp['id']);
      if (r['success'] == true && r['data'] != null) {
        final real = Map.from(r['data']);
        if (i >= 0) {
          messages[i] = real;
        } else if (!messages.any((m) => m['id'] == real['id'])) {
          messages.add(real);
        }
      } else if (i >= 0) {
        messages.removeAt(i); // failed — drop the ghost and tell the user
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t('chatOpenFailed'))));
      }
    });
    _saveCache();
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            title: Text(context.t('camera'), style: TextStyle(color: c.ink)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: _iconBox(Icons.photo_library_rounded, c),
            title: Text(context.t('gallery'), style: TextStyle(color: c.ink)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    Uint8List? bytes;
    if (src == ImageSource.gallery) {
      // Sigmacta's own gallery instead of the system picker.
      final picked = await Navigator.push<dynamic>(
        context,
        MaterialPageRoute(
            builder: (_) => const SigmaGalleryScreen(type: RequestType.image)),
      );
      if (picked is Uint8List) {
        bytes = picked;
      } else if (picked is List<Uint8List> && picked.isNotEmpty) {
        bytes = picked.first; // web: bytes read already, no dart:io File
      } else if (picked is List<File> && picked.isNotEmpty) {
        bytes = await picked.first.readAsBytes();
      }
    } else {
      final file =
          await picker.pickImage(source: src, maxWidth: 1080, imageQuality: 80);
      if (file != null) bytes = await File(file.path).readAsBytes();
    }
    if (bytes == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(context.t('sendingPhoto'))));
    final url = await ApiService.uploadMedia(
      bytes,
      folder: 'msg',
      ext: 'jpg',
      contentType: 'image/jpeg',
      userId: widget.user['id'].toString(),
    );
    if (url != null) {
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
    messenger.showSnackBar(SnackBar(content: Text(context.t('sendingVideo'))));
    final bytes = await file.readAsBytes();
    final url = await ApiService.uploadMedia(
      bytes,
      folder: 'vid',
      ext: 'mp4',
      contentType: 'video/mp4',
      userId: widget.user['id'].toString(),
    );
    if (url != null) {
      await _send(text: '', mediaUrl: url, type: 'video');
    }
    messenger.hideCurrentSnackBar();
  }

  // ─── PLAYBACK ─────────────────────────────────────────────────────────────

  Future<void> _playAudio(String url) async {
    if (_playingUrl == url) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingUrl = null);
      return;
    }
    setState(() => _playingUrl = url);
    // A just-recorded clip is still a local temp file, not a URL — playing it
    // through UrlSource would fail, so the optimistic bubble would be mute.
    final src = url.startsWith('http')
        ? UrlSource(url)
        : DeviceFileSource(url);
    await _audioPlayer.play(src);
  }

  // ─── MESSAGE OPTIONS (Telegram-style animated context menu) ───────────────

  Widget _iconBox(IconData icon, BrutalColors c, {Color? color}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
          color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color ?? c.accent, size: 20),
    );
  }

  Widget _menuRow(IconData icon, String label, {bool danger = false}) {
    final c = context.k;
    final color = danger ? c.danger : c.ink;
    return Row(children: [
      Icon(icon, color: color, size: 19),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: color)),
    ]);
  }

  /// Reply / Forward / Copy / Edit / Delete, filtered by message type and
  /// ownership. Edit/Delete only make sense for my own text messages.
  List<MenuAction> _actionsFor(Map msg, bool isOwn, BrutalColors c) {
    final type = (msg['message_type'] ?? 'text').toString();
    final isText = type == 'text';
    final content = (msg['content'] ?? '').toString();
    return [
      MenuAction(Icons.reply_rounded, context.t('replyAction'), c.ink,
          () => _setReplyTo(msg)),
      MenuAction(Icons.forward_rounded, context.t('forwardAction'), c.ink,
          () => _showForwardSheet(msg)),
      if (isText && content.isNotEmpty)
        MenuAction(Icons.copy_rounded, context.t('copyAction'), c.ink, () {
          Clipboard.setData(ClipboardData(text: content));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.t('copiedToast'))));
        }),
      if (isOwn && isText)
        MenuAction(Icons.edit_rounded, context.t('editMsgLabel'), c.ink, () {
          _editCtrl.text = content;
          setState(() {
            _editingId = msg['id'].toString();
            _replyTo = null;
          });
          _msgFocus.requestFocus();
        }),
      MenuAction(
          _pinned != null && _pinned!['id']?.toString() == msg['id'].toString()
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          _pinned != null && _pinned!['id']?.toString() == msg['id'].toString()
              ? context.t('unpinAction')
              : context.t('pinAction'),
          c.ink,
          () => _togglePin(msg)),
      MenuAction(Icons.checklist_rounded, context.t('selectAction'), c.ink, () {
        setState(() => _selected.add(msg['id'].toString()));
      }),
      if (isOwn)
        MenuAction(Icons.delete_rounded, context.t('deleteMsg'), c.danger, () {
          setState(() => messages
              .removeWhere((m) => m['id'].toString() == msg['id'].toString()));
          _saveCache();
          ApiService.deleteMessage(msg['id'].toString());
        }),
    ];
  }

  AppBar _selectionAppBar(BrutalColors c) {
    final canDelete = messages.any((m) =>
        _selected.contains(m['id'].toString()) &&
        m['sender_id']?.toString() == widget.user['id'].toString());
    return AppBar(
      backgroundColor: c.surface,
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: c.ink),
        onPressed: () => setState(() => _selected.clear()),
      ),
      title: Text(
          context.t('selectedCount').replaceAll('{n}', '${_selected.length}'),
          style: TextStyle(
              color: c.ink, fontSize: 16, fontWeight: FontWeight.w700)),
      actions: [
        IconButton(
          icon: Icon(Icons.copy_rounded, color: c.ink),
          onPressed: _copySelected,
        ),
        // Only offered when at least one of the picked messages is mine —
        // there's nothing the server would let me delete otherwise.
        if (canDelete)
          IconButton(
            icon: Icon(Icons.delete_rounded, color: c.danger),
            onPressed: _deleteSelected,
          ),
      ],
    );
  }

  /// Deletes every ticked message. Only my own can go — the server rejects the
  /// rest anyway, so they're filtered out rather than silently failing.
  void _deleteSelected() {
    final mine = messages
        .where((m) =>
            _selected.contains(m['id'].toString()) &&
            m['sender_id']?.toString() == widget.user['id'].toString())
        .map((m) => m['id'].toString())
        .toList();
    setState(() {
      messages.removeWhere((m) => mine.contains(m['id'].toString()));
      _selected.clear();
    });
    _saveCache();
    for (final id in mine) {
      ApiService.deleteMessage(id);
    }
  }

  void _copySelected() {
    final text = messages
        .where((m) => _selected.contains(m['id'].toString()))
        .map((m) => (m['content'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _selected.clear());
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.t('copiedToast'))));
  }

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  /// My reaction on this message, or null.
  ///
  /// Written to be incapable of throwing. It used to cast `e.value as List`,
  /// and it is called as an ARGUMENT to showChatContextMenu — so one unexpected
  /// shape in `reactions` threw before the menu could open, the error went to
  /// the console, and the user just saw a long-press that did nothing. Any
  /// malformed entry is now ignored instead of taking the menu down with it.
  String? _myReaction(Map msg) {
    final raw = msg['reactions'];
    if (raw is! Map) return null;
    final me = widget.user['id'].toString();
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is List && v.map((e) => e?.toString()).contains(me)) {
        return entry.key?.toString();
      }
    }
    return null;
  }


  Future<void> _react(Map msg, String emoji) async {
    HapticFeedback.selectionClick();
    final id = msg['id'].toString();
    final myId = widget.user['id'].toString();
    final mine = _myReaction(msg);
    setState(() {
      final reactions = Map<String, dynamic>.from(msg['reactions'] ?? {});
      if (mine != null) {
        (reactions[mine] as List).remove(myId);
        if ((reactions[mine] as List).isEmpty) reactions.remove(mine);
      }
      if (mine != emoji) {
        reactions[emoji] = [...?(reactions[emoji] as List?), myId];
      }
      msg['reactions'] = reactions;
    });
    _saveCache();
    await ApiService.reactToMessage(id, emoji);
  }

  /// Telegram-style: long-press scales the bubble up in place behind a
  /// blurred backdrop and a spring-animated floating menu — replaces the
  /// old plain bottom sheet.
  Future<void> _showContextMenu(
      Map msg, bool isOwn, BrutalColors c, Offset origin, Size size) async {
    HapticFeedback.mediumImpact();
    // Everything the menu needs is built INSIDE the try.
    //
    // These arguments are evaluated before showChatContextMenu is even called,
    // so one bad message could throw here — and because this runs from a
    // gesture callback, the error went to the console and the user simply saw a
    // long-press that did nothing. A silent failure in the only path to
    // reply/forward/delete is worse than an ugly error, so it surfaces now.
    try {
      await showChatContextMenu(
        context,
        origin: origin,
        size: size,
        isOwn: isOwn,
        c: c,
        bubble: _buildMessageBubble(msg, isOwn, c),
        actions: _actionsFor(msg, isOwn, c),
        quickReactions: _quickReactions,
        myReaction: _myReaction(msg),
        onReact: (e) => _react(msg, e),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Menu error: $e')));
    }
  }

  /// Picks one of my existing chats and re-sends this message's content
  /// there, tagged "Forwarded from …" — content/media only, no reply quote.
  Future<void> _showForwardSheet(Map msg) async {
    final c = context.k;
    final me = widget.user['id'].toString();
    final fromName = msg['sender_id']?.toString() == me ? _myName : _otherName;
    List chats = await ApiService.getChats(me);
    chats =
        chats.where((ch) => (ch['id'] ?? '').toString() != _chatId).toList();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Text(context.t('forwardTo'),
                  style: TextStyle(
                      color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
          if (chats.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.t('noChats'),
                  style: TextStyle(color: c.inkSoft)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (_, i) {
                  final ch = chats[i];
                  final avatar = ch['avatar'];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: c.surface2,
                      backgroundImage: avatar != null
                          ? CachedNetworkImageProvider(avatar.toString())
                          : null,
                      child: avatar == null
                          ? Icon(Icons.person, color: c.inkSoft)
                          : null,
                    ),
                    title: Text((ch['name'] ?? 'User').toString(),
                        style: TextStyle(
                            color: c.ink, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      await ApiService.sendMessage(
                        (ch['id'] ?? '').toString(),
                        me,
                        (msg['content'] ?? '').toString(),
                        mediaUrl: msg['media_url'],
                        messageType: (msg['message_type'] ?? 'text').toString(),
                        forwardedFrom: fromName,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(context.t('forwardedToast'))));
                      }
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Compose-time reply preview above the input, dismissible with ✕.
  Widget _replyBar(BrutalColors c) {
    final r = _replyTo!;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
                color: c.accent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${context.t('replyLabel')} ${r['sender_name']}',
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
              Text(_quoteSnippet(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
            ],
          ),
        ),
        GestureDetector(
            onTap: _cancelReply,
            child: Icon(Icons.close, color: c.inkSoft, size: 18)),
      ]),
    );
  }

  /// A quoted strip rendered INSIDE a bubble (kind == 'message' reply) —
  /// tapping it scrolls back to the original.
  Widget _quoteStrip(Map replyTo, BrutalColors c) {
    final thumb =
        (replyTo['type'] == 'image') ? replyTo['media_url'] as String? : null;
    return GestureDetector(
      onTap: () => _scrollToMessage((replyTo['id'] ?? '').toString()),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: c.ink.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                  color: c.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text((replyTo['sender_name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                Text(_quoteSnippet(replyTo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ],
            ),
          ),
          if (thumb != null && thumb.isNotEmpty) ...[
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                  imageUrl: thumb, width: 32, height: 32, fit: BoxFit.cover),
            ),
          ],
        ]),
      ),
    );
  }

  /// Instagram-style card for a story reply/like: thumbnail + label, in place
  /// of the old plain "Ответ на историю: …" text bubble.
  Widget _storyReplyContent(
      Map replyTo, String content, bool isOwn, BrutalColors c) {
    final isLike = replyTo['is_like'] == true;
    final isVideo = replyTo['is_video'] == true;
    final thumb = (replyTo['media_url'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: thumb.isEmpty
                      ? Container(color: c.surface2)
                      : CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                ),
              ),
              if (isVideo)
                const Positioned(
                  right: 3,
                  bottom: 3,
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 15, color: Colors.white),
                ),
              if (isLike)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: c.surface),
                    child: const Icon(Icons.favorite_rounded,
                        size: 13, color: Colors.redAccent),
                  ),
                ),
            ]),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      isLike
                          ? context.t('storyLikedLabel')
                          : context.t('storyReplyLabel'),
                      style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
                  if (content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(content,
                          style: TextStyle(color: c.ink, fontSize: 14.5)),
                    ),
                ],
              ),
            ),
          ]),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _pruneBubbleKeys();
    final c = context.k;
    final chatName =
        widget.chat['name'] ?? widget.targetUser?['username'] ?? 'Chat';
    final chatAvatar =
        widget.chat['avatar'] ?? widget.targetUser?['avatar_url'];

    return Scaffold(
      backgroundColor: c.bg,
      // Selection mode replaces the whole header — count on the left, bulk
      // actions on the right — so it's unmistakable that taps now tick rows.
      appBar: _selectMode
          ? _selectionAppBar(c)
          : AppBar(
        backgroundColor: c.surface,
        leading: IconButton(
          icon: Icon(
              _searchMode
                  ? Icons.arrow_back_rounded
                  : Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: c.ink),
          onPressed: () =>
              _searchMode ? _toggleSearch() : Navigator.pop(context),
        ),
        title: _searchMode
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _runSearch,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: InputDecoration(
                  hintText: context.t('searchInChat'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              )
            : GestureDetector(
                onTap: _openTargetProfile,
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  _CircleAvatar(url: chatAvatar, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: VerifiedName(
                              name: chatName.toString(),
                              // Either the row we were opened with, or the
                              // freshly synced profile — whichever we have.
                              verified: (widget.targetUser?['is_verified'] ??
                                      _targetInfo?['is_verified'] ??
                                      widget.chat['is_verified']) ==
                                  true,
                              isPro: (widget.targetUser?['is_pro'] ??
                                      _targetInfo?['is_pro'] ??
                                      widget.chat['is_pro']) ==
                                  true,
                              proBadgeGif: (widget.targetUser?['pro_badge_gif'] ??
                                      _targetInfo?['pro_badge_gif'] ??
                                      widget.chat['pro_badge_gif'])
                                  ?.toString(),
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: c.ink),
                              badgeSize: 15,
                            ),
                          ),
                          if (_muted) ...[
                            const SizedBox(width: 5),
                            Icon(Icons.notifications_off_rounded,
                                size: 14, color: c.inkSoft),
                          ],
                        ]),
                        if (_statusLabel().isNotEmpty)
                          Text(_statusLabel(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _isOnline ? c.accent : c.inkSoft)),
                      ],
                    ),
                  ),
                ]),
              ),
        actions: _searchMode
            ? [
                Text(
                    '${_searchMatches.isEmpty ? 0 : _searchIndex + 1}/${_searchMatches.length}',
                    style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                IconButton(
                  icon: Icon(Icons.keyboard_arrow_up_rounded, color: c.ink),
                  onPressed:
                      _searchMatches.isEmpty ? null : () => _stepMatch(-1),
                ),
                IconButton(
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.ink),
                  onPressed:
                      _searchMatches.isEmpty ? null : () => _stepMatch(1),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: c.ink),
                  onSelected: (v) {
                    switch (v) {
                      case 'search':
                        _toggleSearch();
                        break;
                      case 'wallpaper':
                        _openWallpaperPicker();
                        break;
                      case 'mute':
                        _toggleMute();
                        break;
                      case 'clear':
                        _confirmClearHistory();
                        break;
                      case 'delete':
                        _confirmDeleteChat();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'search',
                        child: _menuRow(
                            Icons.search_rounded, context.t('searchInChat'))),
                    PopupMenuItem(
                        value: 'wallpaper',
                        child: _menuRow(Icons.wallpaper_rounded,
                            context.t('chatWallpaperTitle'))),
                    PopupMenuItem(
                        value: 'mute',
                        child: _menuRow(
                            _muted
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_off_rounded,
                            _muted
                                ? context.t('unmuteChat')
                                : context.t('muteChat'))),
                    PopupMenuItem(
                        value: 'clear',
                        child: _menuRow(Icons.brush_rounded,
                            context.t('clearHistoryTitle'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: _menuRow(Icons.delete_outline_rounded,
                            context.t('deleteChatTitle'),
                            danger: true)),
                  ],
                ),
              ],
      ),
      body: ChatBackground(
        wallpaper: _wallpaper,
        child: Column(children: [
          PinnedBar(
            pinned: _pinned,
            onTap: () => _scrollToMessage((_pinned?['id'] ?? '').toString()),
            // Either participant may unpin in a 1:1 chat.
            onUnpin: () async {
              setState(() => _pinned = null);
              if (_chatId != null) {
                await ApiService.pinChatMessage(_chatId!, null);
              }
            },
          ),
          Expanded(
            child: isLoading
                ? Center(
                    child: CircularProgressIndicator(
                        color: c.accent, strokeWidth: 2))
                : messages.isEmpty
                    ? Center(
                        child: Text(context.t('noMessages'),
                            style: TextStyle(color: c.inkSoft)))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final msg = messages[i];
                          final isOwn = msg['sender_id'] == widget.user['id'];
                          final id = msg['id'].toString();
                          // ONE long-press handler per row, at the very top of
                          // the item. It used to live inside the bubble, where
                          // it competed in the gesture arena with link taps,
                          // reaction chips and the quote tap — here there is
                          // nothing above it and nothing to lose to.
                          // A day boundary prepends a separator to THIS row
                          // instead of inserting a row of its own, so indices
                          // stay 1:1 with `messages`.
                          final prev = i > 0 ? messages[i - 1] : null;
                          final dayChanged = prev == null ||
                              !ChatDateDivider.sameDay(
                                  prev['created_at'], msg['created_at']);
                          final day =
                              ChatDateDivider.parse(msg['created_at']);
                          return KeyedSubtree(
                            key: _bubbleKeys.putIfAbsent(id, () => GlobalKey()),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (dayChanged && day != null)
                                  ChatDateDivider(day: day),
                                _selectMode
                                // In selection mode a tap ticks the row instead
                                // of doing whatever that bubble normally does,
                                // so the wrapper has to swallow the gesture.
                                ? GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() {
                                      if (!_selected.remove(id)) {
                                        _selected.add(id);
                                      }
                                    }),
                                    child: Container(
                                      color: _selected.contains(id)
                                          ? c.accent.withOpacity(0.14)
                                          : Colors.transparent,
                                      child: IgnorePointer(
                                        child: _buildMessageBubble(
                                            msg, isOwn, c),
                                      ),
                                    ),
                                  )
                                : MessageLongPress(
                                    onMenu: (o, sz) => _showContextMenu(
                                        msg, isOwn, c, o, sz),
                                    child: _buildMessageBubble(msg, isOwn, c),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Live link preview — Telegram-style: unfurl while typing, before send.
          if (_liveLinkUrl != null && _editingId == null)
            Container(
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Stack(children: [
                LinkPreviewCard(
                    key: ValueKey(_liveLinkUrl), url: _liveLinkUrl!),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      _linkDebounce?.cancel();
                      setState(() => _liveLinkUrl = null);
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          color: Colors.black45, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ]),
            ),

          // Reply bar — quoted snippet of what's being replied to.
          if (_replyTo != null) _replyBar(c),

          // Edit banner
          if (_editingId != null)
            Container(
              color: c.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Container(
                    width: 3,
                    height: 32,
                    decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(context.t('editMsg'),
                        style: TextStyle(color: c.accent, fontSize: 13))),
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
          if (_showEmoji)
            ExtrasPanel(
              onEmoji: _insertEmoji,
              onBackspace: _backspaceEmoji,
              onGif: (url) => _send(text: 'GIF', mediaUrl: url, type: 'gif'),
            ),
        ]),
      ),
    );
  }

  TextEditingController get _activeCtrl =>
      _editingId != null ? _editCtrl : _msgCtrl;

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _msgFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus(); // hide keyboard first
      setState(() => _showEmoji = true);
    }
  }

  void _insertEmoji(String e) {
    final ctrl = _activeCtrl;
    final sel = ctrl.selection;
    final text = ctrl.text;
    final start =
        (sel.start < 0 ? text.length : sel.start).clamp(0, text.length);
    final end = (sel.end < 0 ? text.length : sel.end).clamp(0, text.length);
    ctrl.text = text.replaceRange(start, end, e);
    ctrl.selection = TextSelection.collapsed(offset: start + e.length);
  }

  void _backspaceEmoji() {
    final ctrl = _activeCtrl;
    if (ctrl.text.isEmpty) return;
    // Remove the last grapheme (correctly deletes a whole emoji).
    final newText = ctrl.text.characters.skipLast(1).toString();
    ctrl.text = newText;
    ctrl.selection = TextSelection.collapsed(offset: newText.length);
  }

  Widget _buildMessageBubble(Map msg, bool isOwn, BrutalColors c) {
    final type = msg['message_type'] ?? 'text';
    final mediaUrl = msg['media_url'] as String?;
    final replyTo = msg['reply_to'] is Map
        ? Map<String, dynamic>.from(msg['reply_to'])
        : null;
    final forwardedFrom = (msg['forwarded_from'] ?? '').toString();

    // A media message with no media is not renderable — drop it entirely
    // rather than laying out an empty avatar + padding, which is what left
    // blank vertical gaps in the history.
    const mediaTypes = {'image', 'video', 'voice', 'gif', 'sticker'};
    if (mediaTypes.contains(type) &&
        (mediaUrl == null || mediaUrl.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    // Video circles are NOT wrapped in a bubble — they stand alone.
    // Long-press your own circle to delete it.
    if (type == 'video') {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _withReactions(
              Row(
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
              msg,
              isOwn,
              c));
    }

    // GIFs and stickers stand alone — no bubble background (Telegram-style).
    // Stickers are transparent Giphy webp/gifs, so a bubble would look boxy.
    if (type == 'gif' || type == 'sticker') {
      final w = type == 'sticker' ? 150.0 : 220.0;
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _withReactions(
              Row(
                mainAxisAlignment:
                    isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!isOwn)
                    _CircleAvatar(
                        url: widget.targetUser?['avatar_url'], size: 24),
                  if (!isOwn) const SizedBox(width: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(type == 'gif' ? 14 : 0),
                    child: CachedNetworkImage(
                      imageUrl: mediaUrl ?? '',
                      width: w,
                      fit: BoxFit.contain,
                      // A SQUARE placeholder reserved w×w — and for stickers it
                      // was fully transparent. A slow or dead URL therefore left
                      // an invisible 150px hole between messages, which is the
                      // mysterious gap in the chat. Now it's a short, visibly
                      // tinted strip: still a placeholder, but it reads as one.
                      placeholder: (_, __) => Container(
                        width: w,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.surface2.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
              msg,
              isOwn,
              c));
    }

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: _withReactions(
            Row(
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: _flashId == msg['id'].toString()
                          ? c.accent.withOpacity(0.35)
                          : (isOwn ? c.accent.withOpacity(0.15) : c.surface),
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
                    child: replyTo != null && replyTo['kind'] == 'story'
                        ? _storyReplyContent(replyTo,
                            (msg['content'] ?? '').toString(), isOwn, c)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (forwardedFrom.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                  child: Text(
                                      '${context.t('forwardedLabel')} $forwardedFrom',
                                      style: TextStyle(
                                          color: c.inkSoft,
                                          fontSize: 11.5,
                                          fontStyle: FontStyle.italic)),
                                ),
                              if (replyTo != null &&
                                  replyTo['kind'] == 'message')
                                _quoteStrip(replyTo, c),
                              _buildBubbleContent(
                                  type, mediaUrl, msg, isOwn, c),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            msg,
            isOwn,
            c));
  }

  /// Reaction chips docked below the bubble row — same presentation group
  /// chat already uses, so both look identical. Returns [row] unchanged when
  /// there's nothing to show.
  Widget _withReactions(Widget row, Map msg, bool isOwn, BrutalColors c) {
    final reactions = Map<String, dynamic>.from(msg['reactions'] ?? {});
    if (reactions.values.every((v) => (v as List).isEmpty)) return row;
    final myId = widget.user['id'].toString();
    return Column(
      crossAxisAlignment:
          isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: EdgeInsets.only(
              top: 2, left: isOwn ? 0 : 34, right: isOwn ? 4 : 0),
          child: Wrap(
            spacing: 4,
            children: [
              for (final entry in reactions.entries)
                if ((entry.value as List).isNotEmpty)
                  GestureDetector(
                    onTap: () => _react(msg, entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (entry.value as List).contains(myId)
                            ? c.accent.withOpacity(0.18)
                            : c.ink.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                          '${entry.key} ${(entry.value as List).length}',
                          style: TextStyle(fontSize: 12, color: c.ink)),
                    ),
                  ),
            ],
          ),
        ),
      ],
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
        return VoiceBubble(
          mediaUrl: mediaUrl,
          duration: (msg['content'] ?? '').toString(),
          isOwn: isOwn,
          isPlaying: _playingUrl == mediaUrl,
          onTap: mediaUrl != null ? () => _playAudio(mediaUrl) : null,
        );

      default:
        final content = (msg['content'] ?? '').toString();
        // Telegram-style: a message that is a single emoji renders big with a
        // pop-in animation (tap to replay). Stored as plain Unicode text.
        if (_isSingleEmoji(content)) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BigEmoji(emoji: content),
                  _metaRow(msg, isOwn, c),
                ]),
          );
        }
        // Telegram-style: a message with a link gets a rich preview card
        // (site · title · description · picture) under the text.
        final url = firstUrl(content);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _linkifiedText(content, textColor),
                if (url != null)
                  GestureDetector(
                    onTap: () => _openUrl(url),
                    child:
                        SizedBox(width: 236, child: LinkPreviewCard(url: url)),
                  ),
                const SizedBox(height: 3),
                _metaRow(msg, isOwn, c),
              ]),
        );
    }
  }

  // One emoji and nothing else (multi-codepoint emoji like ❤️/👍🏽 count too).
  static bool _isSingleEmoji(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 8) return false;
    if (t.characters.length != 1) return false;
    final code = t.runes.first;
    return code > 0x2000; // beyond regular text/latin/cyrillic ranges
  }

  String _fmtTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = ApiService.parseServerTime(raw.toString());
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  // Telegram-style meta: time + (for own messages) ✓ sent / ✓✓ read.
  Widget _metaRow(Map msg, bool isOwn, BrutalColors c) {
    final read = msg['is_read'] == true;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (msg['is_edited'] == true)
        Text('${context.t('editedMark')} · ',
            style: TextStyle(color: c.inkSoft, fontSize: 10)),
      Text(_fmtTime(msg['created_at']),
          style: TextStyle(color: c.inkSoft, fontSize: 10)),
      if (isOwn) ...[
        const SizedBox(width: 4),
        // Three states, Telegram-style:
        //   ✓  sent      — on the server, their phone hasn't fetched it
        //   ✓✓ delivered — their phone has it, chat not opened
        //   ✓✓ accent    — they opened the chat
        // `delivered` is implied by `is_read`, so an old cached message that
        // predates the delivered flag still shows ✓✓ rather than dropping
        // back to a single tick.
        Icon(
            (read || msg['delivered'] == true)
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size: 14,
            color: read ? c.accent : c.inkSoft),
      ],
    ]);
  }

  /// Local-first edit — the server copy may already be gone (history lives on
  /// the device), so the bubble is rewritten before the request goes out.
  void _saveEdit() {
    final id = _editingId;
    if (id == null) return;
    final text = _editCtrl.text;
    setState(() {
      final i = messages.indexWhere((m) => m['id'].toString() == id);
      if (i >= 0) {
        messages[i] = Map.from(messages[i])
          ..['content'] = text
          ..['is_edited'] = true;
      }
      _editingId = null;
    });
    _editCtrl.clear();
    _saveCache();
    ApiService.editMessage(id, text);
  }

  Widget _buildInput(BrutalColors c) {
    // Shared with group chat — one composer, so voice/emoji/send behave
    // identically in both.
    return ChatComposer(
      msgCtrl: _msgCtrl,
      editCtrl: _editCtrl,
      focusNode: _msgFocus,
      showEmoji: _showEmoji,
      isEditing: _editingId != null,
      userId: widget.user['id'].toString(),
      onToggleEmoji: _toggleEmoji,
      onSend: _send,
      onSaveEdit: _saveEdit,
      onVoiceRecorded: _onVoiceRecorded,
      onVoiceUploaded: _onVoiceUploaded,
    );
  }

  /// Shows the voice bubble straight away, playable from the local file while
  /// the upload runs. Keyed by the temp path so the upload can find it again.
  void _onVoiceRecorded(String localPath, int secs) {
    setState(() {
      messages = [
        ...messages,
        {
          'id': 'voice_$localPath',
          'chat_id': _chatId,
          'sender_id': widget.user['id'].toString(),
          'content': '${secs}s',
          'message_type': 'voice',
          'media_url': localPath,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'is_read': false,
          '_pending': true,
        }
      ];
    });
    _scrollToBottom();
  }

  /// Upload finished: drop the placeholder and send for real, or mark it failed
  /// so the user knows rather than staring at a bubble that never arrives.
  void _onVoiceUploaded(String localPath, String? url, int secs) {
    setState(() =>
        messages.removeWhere((m) => m['id'] == 'voice_$localPath'));
    if (url == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('storyUploadFailed'))));
      }
      return;
    }
    _send(text: '${secs}s', mediaUrl: url, type: 'voice');
  }

  Future<void> _openUrl(String raw) async {
    var u = raw.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    try {
      await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Message text where URLs are accent-coloured and tappable.
  Widget _linkifiedText(String content, Color textColor) {
    final c = context.k;
    final reg = RegExp(r'(https?:\/\/[^\s]+)');
    if (!reg.hasMatch(content)) {
      return Text(content,
          style: TextStyle(color: textColor, fontSize: 15, height: 1.3));
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in reg.allMatches(content)) {
      if (m.start > last) {
        spans.add(TextSpan(text: content.substring(last, m.start)));
      }
      final link = m.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => _openUrl(link),
          child: Text(link,
              style: TextStyle(
                  color: c.accent,
                  fontSize: 15,
                  height: 1.3,
                  decoration: TextDecoration.underline,
                  decorationColor: c.accent)),
        ),
      ));
      last = m.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return Text.rich(
      TextSpan(
          style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
          children: spans),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _linkDebounce?.cancel();
    _playbackDoneSub?.cancel();
    _audioPlayer.dispose();
    _msgSub?.cancel();
    ActiveChat.close(_chatId);
    _readSub?.cancel();
    _deliveredSub?.cancel();
    _pinSub?.cancel();
    _reactionSub?.cancel();
    _msgCtrl.dispose();
    _editCtrl.dispose();
    _searchCtrl.dispose();
    _msgFocus.dispose();
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

// Telegram-style animated single emoji: pops in with an elastic bounce,
// tap to replay. Purely visual — the message stays plain Unicode text.
class _BigEmoji extends StatefulWidget {
  final String emoji;
  const _BigEmoji({required this.emoji});
  @override
  State<_BigEmoji> createState() => _BigEmojiState();
}

class _BigEmojiState extends State<_BigEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _scale =
      CurvedAnimation(parent: _ac, curve: Curves.elasticOut);

  @override
  void initState() {
    super.initState();
    _ac.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _ac.forward(from: 0),
      child: ScaleTransition(
        scale: _scale,
        child: Text(widget.emoji, style: const TextStyle(fontSize: 52)),
      ),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }
}
