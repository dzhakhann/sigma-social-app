import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../services/active_chat.dart';
import '../services/api_service.dart';
import '../services/chat_sounds.dart';
import '../services/chat_mute.dart';
import '../services/chat_store.dart';
import '../services/chat_wallpaper.dart';
import '../services/socket_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_context_menu.dart';
import '../widgets/chat_extras_panel.dart';
import '../widgets/link_preview.dart';
import '../widgets/pinned_bar.dart';
import 'pro_screen.dart';
import '../widgets/wallpaper_picker.dart';
import '../widgets/chat_background.dart';
import '../widgets/chat_date_divider.dart';
import '../widgets/voice_bubble.dart';
import 'group_info_screen.dart';
import 'photo_view_screen.dart';

/// Group chat — a trimmed, group-aware sibling of ChatDetailScreen: text,
/// emoji and photo messages, replies, member list with admin actions. Same
/// device-stored-history model as 1:1 chat (ChatStore), N-way ack on the
/// server (a message is only dropped once EVERY member has picked it up).
class GroupChatScreen extends StatefulWidget {
  final Map user;
  final Map group; // at least {id, name, avatar_url, is_open, my_role}
  const GroupChatScreen({super.key, required this.user, required this.group});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late Map _group = widget.group;
  List members = [];
  List messages = [];
  bool isLoading = true;
  final _msgCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  String? _editingId;
  final _scrollCtrl = ScrollController();
  final _msgFocus = FocusNode();
  bool _showEmoji = false;
  bool _muted = false;

  // In-chat search — same model as 1:1 chat: searches the history stored on
  // THIS device, which is all we have (the server only keeps the undelivered
  // queue).
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();
  List<int> _searchMatches = [];
  int _searchIndex = -1;

  /// Briefly highlighted after jumping to a search hit or a quoted original.
  String? _flashId;

  /// Pinned-message snapshot for this group (null = nothing pinned).
  Map? _pinned;
  StreamSubscription? _pinSub;

  /// Pinning speaks for the whole group, so it's admin-only — mirrors the
  /// server check in PUT /api/groups/:groupId/pin.
  bool get _isAdmin => (_group['my_role'] ?? '').toString() == 'admin';

  /// Multi-select mode: ids of the messages currently ticked.
  final Set<String> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;

  /// Anchors for "scroll to this message". Pruned every build — see
  /// [_pruneBubbleKeys].
  final Map<String, GlobalKey> _bubbleKeys = {};

  // Voice playback (recording itself lives in ChatComposer).
  final _audioPlayer = AudioPlayer();
  String? _playingUrl;
  StreamSubscription? _playbackDoneSub;
  Map? _wallpaper;
  Map? _replyTo;
  StreamSubscription? _msgSub;
  StreamSubscription? _seenSub;
  StreamSubscription? _reactionSub;
  StreamSubscription? _editSub;
  Timer? _timer;
  // Telegram-style: unfurl a link WHILE typing, not just after sending.
  String? _liveLinkUrl;
  Timer? _linkDebounce;

  String get _groupId => _group['id'].toString();
  String get _myId => widget.user['id'].toString();

  // Same < 70s-since-last_seen threshold 1:1 chat uses for its "online" label.
  int get _onlineCount => members.where((m) {
        final ls = m['last_seen'];
        if (ls == null) return false;
        try {
          return DateTime.now()
                  .difference(ApiService.parseServerTime(ls.toString()))
                  .inSeconds <
              70;
        } catch (_) {
          return false;
        }
      }).length;

  @override
  void initState() {
    super.initState();
    _init();
    _playbackDoneSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
    ActiveChat.openGroup(_groupId);
    _pinned = widget.group['pinned_message'] as Map?;
    _pinSub = SocketService().onGroupPin.listen((data) {
      if (data['group_id']?.toString() != _groupId || !mounted) return;
      setState(() => _pinned = data['pinned_message'] as Map?);
    });
    SocketService().connect(_myId);
    _msgSub = SocketService().onGroupMessage.listen((data) {
      if (data['group_id']?.toString() == _groupId && mounted) {
        _onIncoming(Map.from(data));
      }
    });
    // "Seen by" and reactions have no server-side history to re-fetch (see
    // the ack endpoint) — both are built up entirely from these live events,
    // same principle as 1:1 read receipts.
    _seenSub = SocketService().onGroupMessageSeen.listen((data) {
      if (data['group_id']?.toString() != _groupId || !mounted) return;
      final msgId = data['message_id']?.toString();
      final seenUid = data['user_id']?.toString();
      if (msgId == null || seenUid == null) return;
      var changed = false;
      setState(() {
        for (final m in messages) {
          if (m['id'].toString() == msgId) {
            final seen =
                (m['seen_by'] as List?)?.cast<String>().toSet() ?? <String>{};
            if (seen.add(seenUid)) changed = true;
            m['seen_by'] = seen.toList();
          }
        }
      });
      // Saving unconditionally is what truncated the history file: an event for
      // a message we don't have yet matched nothing, and the empty in-memory
      // list got written over the real archive.
      if (changed) _saveCache();
    });
    _reactionSub = SocketService().onGroupMessageReaction.listen((data) {
      if (data['group_id']?.toString() != _groupId || !mounted) return;
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
      if (changed) _saveCache();
    });
    _editSub = SocketService().onGroupMessageEdited.listen((data) {
      if (data['group_id']?.toString() != _groupId || !mounted) return;
      final msgId = data['message_id']?.toString();
      if (msgId == null) return;
      var changed = false;
      setState(() {
        for (final m in messages) {
          if (m['id'].toString() == msgId) {
            m['content'] = (data['content'] ?? '').toString();
            m['is_edited'] = true;
            changed = true;
          }
        }
      });
      if (changed) _saveCache();
    });
    _msgCtrl.addListener(_onComposerTextChanged);
  }

  void _onComposerTextChanged() {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final url = firstUrl(_msgCtrl.text);
      if (url != _liveLinkUrl) setState(() => _liveLinkUrl = url);
    });
  }

  Future<void> _init() async {
    ChatMute.isMuted('group_$_groupId').then((m) {
      if (mounted) setState(() => _muted = m);
    });
    _loadWallpaper();
    final local = await ChatStore.load('group_$_groupId');
    if (local.isNotEmpty && mounted) {
      setState(() => messages = local);
      _scrollToBottom(animated: false);
      _syncMeta();
      _markRead();
    }
    final detail = await ApiService.getGroup(_groupId);
    if (detail != null && mounted) {
      setState(() {
        _group = detail;
        members = (detail['members'] as List?) ?? [];
      });
    }
    await _loadMessages();
    if (mounted) setState(() => isLoading = false);
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadMessages();
      _refreshGroupDetail();
    });
  }

  /// Refreshes reactions/seen-by for cached messages — a message that's
  /// already been fully acked stops being returned by GET .../messages, so a
  /// device that wasn't live-connected via socket when a reaction/ack
  /// happened would otherwise never learn about it (this was the actual bug
  /// behind reactions appearing to "not work at all" — they DID save
  /// server-side, this device just never re-checked). Best-effort.
  Future<void> _syncMeta() async {
    final ids = messages
        .whereType<Map>()
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => !id.startsWith('tmp_'))
        .toList();
    if (ids.isEmpty) return;
    final meta = await ApiService.syncGroupMessages(_groupId, ids);
    if (meta.isEmpty || !mounted) return;
    setState(() {
      for (final m in messages) {
        final id = m['id']?.toString();
        final mm = id == null ? null : meta[id];
        if (mm != null) {
          m['reactions'] = mm['reactions'] ?? {};
          m['seen_by'] = mm['seen_by'] ?? [];
        }
      }
    });
    _saveCache();
  }

  /// Keeps member last_seen (→ online status) fresh without waiting for the
  /// screen to be reopened — same 12s cadence as message polling.
  Future<void> _refreshGroupDetail() async {
    final detail = await ApiService.getGroup(_groupId);
    if (detail != null && mounted) {
      setState(() {
        _group = detail;
        members = (detail['members'] as List?) ?? [];
      });
    }
  }

  // ─── Group ⋮ menu: mute, wallpaper, clear history ──────────────────────────
  // Same generic per-chat-id services 1:1 chat uses (keyed 'group_<id>' so it
  // can never collide with a 1:1 chat's own key).

  Future<void> _loadWallpaper() async {
    final w = await ChatWallpaper.get('group_$_groupId');
    if (mounted) setState(() => _wallpaper = w);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    await ChatMute.setMuted('group_$_groupId', next);
  }

  Future<void> _openWallpaperPicker() async {
    final picked = await showWallpaperPicker(
      context,
      // No gallery for groups: a background from one member's camera roll
      // isn't something the others would ever see.
      allowGallery: false,
      onPickGallery: () {},
      onOpenPro: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProScreen(user: widget.user))),
    );
    if (picked == null) return;
    final w = picked.isEmpty ? null : picked;
    await ChatWallpaper.set('group_$_groupId', w);
    if (mounted) setState(() => _wallpaper = w);
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
    if (ok != true) return;
    await ChatStore.clear('group_$_groupId');
    if (mounted) setState(() => messages = []);
  }

  /// Reports which messages this user has now READ. Called on open and after
  /// every load, because opening the chat IS the read event — the same signal
  /// Telegram uses. Idempotent server-side, so repeating it is free.
  void _markRead() {
    final ids = messages
        .whereType<Map>()
        .where((m) => m['sender_id']?.toString() != _myId)
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => !id.startsWith('tmp_') && !id.startsWith('voice_'))
        .toList();
    if (ids.isEmpty) return;
    ApiService.markGroupRead(_groupId, ids);
  }

  Future<void> _loadMessages() async {
    final queued = await ApiService.getGroupMessages(_groupId);
    if (!mounted) return;
    final known = messages
        .whereType<Map>()
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toSet();
    final fresh =
        queued.where((m) => !known.contains(m['id']?.toString())).toList();
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
        .where((m) => m['sender_id']?.toString() != _myId)
        .map((m) => m['id'].toString())
        .toList();
    ApiService.ackGroupMessages(_groupId, ackIds);
    // Ack is delivery; this is the actual read.
    _markRead();
  }

  Future<void> _onIncoming(Map msg) async {
    final id = msg['id']?.toString();
    if (id == null) return;
    if (messages.any((m) => m['id']?.toString() == id)) return;
    setState(() => messages = [...messages, msg]);
    _saveCache();
    _scrollToBottom();
    if (msg['sender_id']?.toString() != _myId) {
      // Only somebody else's message earns a receive blip — my own arrives
      // back over the socket too, and it already made a send sound.
      ChatSounds.received();
      ApiService.ackGroupMessages(_groupId, [id]);
      // The chat is open, so it's read the moment it arrives.
      ApiService.markGroupRead(_groupId, [id]);
    }
  }

  /// Optimistic placeholders are excluded — see the 1:1 version for why a
  /// persisted `voice_…`/`tmp_…` row becomes a permanently broken bubble.
  void _saveCache() {
    final durable = messages.where((m) {
      final id = m['id']?.toString() ?? '';
      return !id.startsWith('voice_') && !id.startsWith('tmp_');
    }).toList();
    ChatStore.save('group_$_groupId', durable);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      animated
          ? _scrollCtrl.animateTo(target,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut)
          : _scrollCtrl.jumpTo(target);
    });
  }

  Future<void> _send(
      {String? text, String? mediaUrl, String type = 'text'}) async {
    final content = text ?? _msgCtrl.text.trim();
    if (content.isEmpty && mediaUrl == null) return;
    if (text == null) {
      _msgCtrl.clear();
      _linkDebounce?.cancel();
      if (_liveLinkUrl != null) setState(() => _liveLinkUrl = null);
    }
    final replyTo = _replyTo;
    if (replyTo != null) setState(() => _replyTo = null);
    final temp = {
      'id': 'tmp_${DateTime.now().microsecondsSinceEpoch}',
      'group_id': _groupId,
      'sender_id': _myId,
      'content': content,
      'message_type': type,
      'media_url': mediaUrl,
      'reply_to': replyTo,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_pending': true,
    };
    setState(() => messages = [...messages, temp]);
    ChatSounds.sent();
    _scrollToBottom();
    final r = await ApiService.sendGroupMessage(_groupId, content,
        mediaUrl: mediaUrl, messageType: type, replyTo: replyTo);
    if (!mounted) return;
    setState(() {
      final i = messages.indexWhere((m) => m['id'] == temp['id']);
      if (r['success'] == true && r['data'] != null) {
        if (i >= 0) messages[i] = Map.from(r['data']);
      } else if (i >= 0) {
        messages.removeAt(i);
      }
    });
    _saveCache();
  }

  /// Commits an in-progress edit — optimistic (the bubble updates instantly,
  /// the server call and the socket echo to other members follow).
  Future<void> _saveEdit() async {
    final id = _editingId;
    final text = _editCtrl.text.trim();
    if (id == null || text.isEmpty) return;
    setState(() {
      for (final m in messages) {
        if (m['id'].toString() == id) {
          m['content'] = text;
          m['is_edited'] = true;
        }
      }
      _editingId = null;
    });
    _editCtrl.clear();
    _saveCache();
    await ApiService.editGroupMessage(_groupId, id, text);
  }

  void _setReplyTo(Map msg) {
    setState(() {
      _replyTo = {
        'id': msg['id'].toString(),
        'sender_name': msg['sender_id']?.toString() == _myId
            ? context.t('youLabel')
            : _memberName(msg['sender_id']),
        'content': (msg['content'] ?? '').toString(),
        'type': (msg['message_type'] ?? 'text').toString(),
        'media_url': msg['media_url'],
      };
    });
    _msgFocus.requestFocus();
  }

  String _memberName(dynamic userId) {
    for (final m in members) {
      if (m['user_id'].toString() == userId.toString()) {
        return (m['username'] ?? 'User').toString();
      }
    }
    return 'User';
  }

  String? _memberAvatar(dynamic userId) {
    for (final m in members) {
      if (m['user_id'].toString() == userId.toString()) return m['avatar_url'];
    }
    return null;
  }

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  Future<void> _react(Map msg, String emoji) async {
    HapticFeedback.selectionClick();
    final id = msg['id'].toString();
    // Optimistic — the socket echo (including to ourselves) will reconcile
    // this with the server's version a moment later.
    final mine = (msg['reactions'] as Map?)
        ?.entries
        .firstWhere((e) => (e.value as List).contains(_myId),
            orElse: () => const MapEntry('', []))
        .key;
    setState(() {
      final reactions = Map<String, dynamic>.from(msg['reactions'] ?? {});
      if (mine != null && mine.isNotEmpty) {
        (reactions[mine] as List).remove(_myId);
        if ((reactions[mine] as List).isEmpty) reactions.remove(mine);
      }
      if (mine != emoji) {
        reactions[emoji] = [...?(reactions[emoji] as List?), _myId];
      }
      msg['reactions'] = reactions;
    });
    _saveCache();
    await ApiService.reactToGroupMessage(_groupId, id, emoji);
  }

  /// My reaction on this message, or null.
  ///
  /// Written to be incapable of throwing. It is called as an ARGUMENT to
  /// showChatContextMenu, so one unexpected shape in `reactions` threw before
  /// the menu could open — the error went to the console and the user saw a
  /// long-press that did nothing.
  String? _myReaction(Map msg) {
    final raw = msg['reactions'];
    if (raw is! Map) return null;
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is List && v.map((e) => e?.toString()).contains(_myId)) {
        return entry.key?.toString();
      }
    }
    return null;
  }

  /// Long-press menu for a group message. Deliberately the same set 1:1 chat
  /// offers, plus "Read by" — when this screen moved onto the shared menu its
  /// action list silently shrank, and a missing entry reads to the user as a
  /// deliberately removed feature.
  List<MenuAction> _actionsFor(Map msg, bool isOwn, BrutalColors c) {
    final content = (msg['content'] ?? '').toString();
    final isText = (msg['message_type'] ?? 'text').toString() == 'text';
    final pinnedHere =
        _pinned != null && _pinned!['id']?.toString() == msg['id'].toString();
    return [
      MenuAction(Icons.reply_rounded, context.t('replyAction'), c.ink,
          () => _setReplyTo(msg)),
      MenuAction(Icons.forward_rounded, context.t('forwardAction'), c.ink,
          () => _showForwardSheet(msg)),
      if (content.isNotEmpty)
        MenuAction(Icons.copy_rounded, context.t('copyAction'), c.ink, () {
          Clipboard.setData(ClipboardData(text: content));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.t('copiedToast'))));
        }),
      if (isOwn && isText && content.isNotEmpty)
        MenuAction(Icons.edit_rounded, context.t('editMsgLabel'), c.ink, () {
          _editCtrl.text = content;
          setState(() {
            _editingId = msg['id'].toString();
            _replyTo = null; // mutually exclusive with replying
          });
          _msgFocus.requestFocus();
        }),
      MenuAction(
          pinnedHere ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          pinnedHere ? context.t('unpinAction') : context.t('pinAction'),
          c.ink,
          () => _togglePin(msg)),
      MenuAction(Icons.checklist_rounded, context.t('selectAction'), c.ink, () {
        setState(() => _selected.add(msg['id'].toString()));
      }),
      if (isOwn)
        MenuAction(Icons.done_all_rounded, context.t('seenByAction'), c.ink,
            () => _showSeenBy(msg)),
      if (isOwn)
        MenuAction(Icons.delete_rounded, context.t('deleteMsg'), c.danger, () {
          setState(() => messages
              .removeWhere((m) => m['id'].toString() == msg['id'].toString()));
          _saveCache();
          ApiService.deleteGroupMessage(_groupId, msg['id'].toString());
        }),
    ];
  }

  /// Who actually read this message, and who hasn't.
  ///
  /// Fetched from the server rather than derived from `seen_by`: seen_by came
  /// from the delivery queue, so it listed everyone the message REACHED. Reading
  /// is a separate event with its own table.
  Future<void> _showSeenBy(Map msg) async {
    final c = context.k;
    final id = msg['id']?.toString();
    if (id == null) return;

    // Opened immediately with a spinner instead of blocking on the request —
    // tapping the tick and getting nothing for a second reads as a dead button.
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: FutureBuilder<Map>(
          future: ApiService.groupMessageReads(_groupId, id),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final read = (snap.data!['read'] as List?) ?? [];
            final unread = (snap.data!['unread'] as List?) ?? [];
            return Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.ink.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                    context
                        .t('readByCount')
                        .replaceAll('{n}', '${read.length}'),
                    style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in read) _readRow(c, u, true),
                    if (unread.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(context.t('notReadYet'),
                            style: TextStyle(
                                color: c.inkSoft,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    for (final u in unread) _readRow(c, u, false),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ]);
          },
        ),
      ),
    );
  }

  Widget _readRow(BrutalColors c, dynamic u, bool hasRead) {
    final avatar = (u['avatar_url'] ?? '').toString();
    final at = u['read_at'];
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: c.surface2,
        backgroundImage:
            avatar.isEmpty ? null : CachedNetworkImageProvider(avatar),
        child: avatar.isEmpty ? Icon(Icons.person, color: c.inkSoft) : null,
      ),
      title: Text((u['username'] ?? 'User').toString(),
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
      // The exact time is the useful part of a read receipt, not just the fact.
      subtitle: hasRead && at != null
          ? Text(_fmtTime(at), style: TextStyle(color: c.inkSoft, fontSize: 11.5))
          : null,
      trailing: hasRead
          ? Icon(Icons.done_all_rounded, size: 16, color: c.accent)
          : Icon(Icons.done_rounded, size: 16, color: c.inkSoft),
    );
  }

  Future<void> _showForwardSheet(Map msg) async {
    final c = context.k;
    final fromName = msg['sender_id']?.toString() == _myId
        ? (widget.user['username'] ?? '').toString()
        : _memberName(msg['sender_id']);
    final chats = await ApiService.getChats(_myId);
    final groups = (await ApiService.getGroups())
        .where((g) => g['id'].toString() != _groupId)
        .toList();
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
          if (chats.isEmpty && groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child:
                  Text(context.t('noChats'), style: TextStyle(color: c.inkSoft)),
            )
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final ch in chats)
                  _forwardTile(c, sheetCtx,
                      name: (ch['name'] ?? 'User').toString(),
                      avatar: ch['avatar']?.toString(),
                      isGroup: false,
                      onPick: () => ApiService.sendMessage(
                            (ch['id'] ?? '').toString(),
                            _myId,
                            (msg['content'] ?? '').toString(),
                            mediaUrl: msg['media_url'],
                            messageType:
                                (msg['message_type'] ?? 'text').toString(),
                            forwardedFrom: fromName,
                          )),
                for (final g in groups)
                  _forwardTile(c, sheetCtx,
                      name: (g['name'] ?? '').toString(),
                      avatar: g['avatar_url']?.toString(),
                      isGroup: true,
                      onPick: () => ApiService.sendGroupMessage(
                            g['id'].toString(),
                            (msg['content'] ?? '').toString(),
                            mediaUrl: msg['media_url'],
                            messageType:
                                (msg['message_type'] ?? 'text').toString(),
                          )),
              ]),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _forwardTile(BrutalColors c, BuildContext sheetCtx,
      {required String name,
      String? avatar,
      required bool isGroup,
      required Future<void> Function() onPick}) {
    final hasAvatar = (avatar ?? '').isNotEmpty;
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: c.surface2,
        backgroundImage:
            hasAvatar ? CachedNetworkImageProvider(avatar!) : null,
        child: hasAvatar
            ? null
            : Icon(isGroup ? Icons.groups_rounded : Icons.person,
                color: c.inkSoft),
      ),
      title: Text(name,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
      onTap: () async {
        Navigator.pop(sheetCtx);
        await onPick();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t('forwardedToast'))));
        }
      },
    );
  }

  /// Telegram-style animated menu — same widget 1:1 chat uses, so long-press
  /// looks and behaves identically in both (this replaces the old plain
  /// `showModalBottomSheet`).
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
        bubble: _bubble(c, msg, isOwn),
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


  // ─── Group info ─────────────────────────────────────────────────────────
  // Full screen (not a bottom sheet) — looks/behaves like a real profile
  // screen, per the "group info should open like a user profile" request.

  Future<void> _openGroupInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(
          user: widget.user,
          group: {..._group, 'members': members},
        ),
      ),
    );
    // Edits (rename, add/remove/promote member) happen on the pushed screen's
    // own copy of the data — resync ours now that we're back.
    _refreshGroupDetail();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _pruneBubbleKeys();
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
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
          onTap: _openGroupInfo,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            // Tapping the photo itself opens it fullscreen with the same
            // circle→square Hero animation a user's profile photo uses;
            // tapping anywhere else in the header still opens group info.
            GestureDetector(
              onTap: () {
                final url = (_group['avatar_url'] ?? '').toString();
                if (url.isEmpty) {
                  _openGroupInfo();
                  return;
                }
                Navigator.push(
                    context,
                    PhotoViewScreen.route(url,
                        heroTag: 'group_avatar_$_groupId'));
              },
              child: Hero(
                tag: 'group_avatar_$_groupId',
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: c.surface2,
                  backgroundImage:
                      (_group['avatar_url'] ?? '').toString().isNotEmpty
                          ? CachedNetworkImageProvider(_group['avatar_url'])
                          : null,
                  child: (_group['avatar_url'] ?? '').toString().isEmpty
                      ? Icon(Icons.groups_rounded, color: c.inkSoft, size: 18)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text((_group['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.ink)),
                  Text(
                      _onlineCount > 0
                          ? '${context.t('memberCountLabel').replaceAll('{n}', '${members.length}')} · '
                              '${context.t('onlineCountLabel').replaceAll('{n}', '$_onlineCount')}'
                          : context
                              .t('memberCountLabel')
                              .replaceAll('{n}', '${members.length}'),
                      style: TextStyle(
                          fontSize: 12,
                          color: _onlineCount > 0 ? c.accent : c.inkSoft)),
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
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'search',
                  child: _menuRow(
                      c, Icons.search_rounded, context.t('searchInChat'))),
              PopupMenuItem(
                  value: 'wallpaper',
                  child: _menuRow(c, Icons.wallpaper_rounded,
                      context.t('chatWallpaperTitle'))),
              PopupMenuItem(
                  value: 'mute',
                  child: _menuRow(
                      c,
                      _muted
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      _muted
                          ? context.t('unmuteChat')
                          : context.t('muteChat'))),
              PopupMenuItem(
                  value: 'clear',
                  child: _menuRow(
                      c, Icons.brush_rounded, context.t('clearHistoryTitle'))),
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
            // Non-admins see the pin but get no unpin button.
            onUnpin: _isAdmin
                ? () async {
                    setState(() => _pinned = null);
                    await ApiService.pinGroupMessage(_groupId, null);
                  }
                : null,
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
                          final isOwn = msg['sender_id']?.toString() == _myId;
                          final id = msg['id'].toString();
                          // One long-press handler per row, at the top of the
                          // item — see the 1:1 version for why it can't live
                          // inside the bubble.
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
                                          child: _bubble(c, msg, isOwn)),
                                    ),
                                  )
                                : MessageLongPress(
                                    onMenu: (o, sz) => _showContextMenu(
                                        msg, isOwn, c, o, sz),
                                    child: _bubble(c, msg, isOwn),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          // Live link preview — Telegram-style: unfurl while typing, before send.
          if (_liveLinkUrl != null)
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
          if (_replyTo != null) _replyBar(c),
          // Edit banner — same treatment as 1:1 chat.
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
          _inputBar(c),
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

  // Emoji handling matches 1:1 chat exactly. The old group version always
  // wrote into _msgCtrl — so typing an emoji while EDITING a message put it in
  // the wrong field — and it inserted at the selection start without replacing
  // the selected range.
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

  Widget _menuRow(BrutalColors c, IconData icon, String label,
      {bool danger = false}) {
    final color = danger ? c.danger : c.ink;
    return Row(children: [
      Icon(icon, color: color, size: 19),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: color)),
    ]);
  }

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
              Text((r['content'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
            ],
          ),
        ),
        GestureDetector(
            onTap: () => setState(() => _replyTo = null),
            child: Icon(Icons.close, color: c.inkSoft, size: 18)),
      ]),
    );
  }

  Widget _bubble(BrutalColors c, Map msg, bool isOwn) {
    final type = (msg['message_type'] ?? 'text').toString();
    final mediaUrl = msg['media_url'] as String?;

    // A media message with no media is not renderable — drop it rather than
    // laying out an empty avatar + padding, which showed up as a blank gap.
    const mediaTypes = {'image', 'video', 'voice', 'gif', 'sticker'};
    if (mediaTypes.contains(type) &&
        (mediaUrl == null || mediaUrl.trim().isEmpty)) {
      return const SizedBox.shrink();
    }
    final replyTo = msg['reply_to'] is Map
        ? Map<String, dynamic>.from(msg['reply_to'])
        : null;
    final reactions = Map<String, dynamic>.from(msg['reactions'] ?? {});
    final seenCount = ((msg['seen_by'] as List?) ?? []).length;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment:
              isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isOwn) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: c.surface2,
                    backgroundImage: _memberAvatar(msg['sender_id']) != null
                        ? CachedNetworkImageProvider(
                            _memberAvatar(msg['sender_id'])!)
                        : null,
                    child: _memberAvatar(msg['sender_id']) == null
                        ? Icon(Icons.person, color: c.inkSoft, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7),
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
                          ? Border.all(color: c.accent.withOpacity(0.25))
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isOwn)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Text(_memberName(msg['sender_id']),
                                style: TextStyle(
                                    color: c.accent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        if (replyTo != null)
                          // Tapping the quote jumps to the original, same as
                          // 1:1 chat — the group version was inert before.
                          GestureDetector(
                            onTap: () => _scrollToMessage(
                                (replyTo['id'] ?? '').toString()),
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                  color: c.ink.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      (replyTo['sender_name'] ?? '').toString(),
                                      style: TextStyle(
                                          color: c.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  Text((replyTo['content'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.inkSoft, fontSize: 11.5)),
                                ],
                              ),
                            ),
                          ),
                        if (type == 'image')
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                                imageUrl: mediaUrl ?? '',
                                width: 220,
                                height: 220,
                                fit: BoxFit.cover),
                          )
                        // GIFs could already be SENT here but had no renderer,
                        // so they arrived as blank bubbles.
                        else if (type == 'gif' || type == 'sticker')
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                                type == 'gif' ? 14 : 0),
                            child: CachedNetworkImage(
                              imageUrl: mediaUrl ?? '',
                              width: type == 'sticker' ? 150 : 220,
                              fit: BoxFit.contain,
                              // Short tinted strip, never a full square: a slow
                              // or dead URL used to reserve a tall invisible box
                              // and read as a random gap in the history.
                              placeholder: (_, __) => Container(
                                width: type == 'sticker' ? 150 : 220,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c.surface2.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          )
                        else if (type == 'voice')
                          VoiceBubble(
                            mediaUrl: mediaUrl,
                            duration: (msg['content'] ?? '').toString(),
                            isOwn: isOwn,
                            isPlaying: _playingUrl == mediaUrl,
                            onTap: mediaUrl != null
                                ? () => _playAudio(mediaUrl)
                                : null,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: _textWithLink(
                                (msg['content'] ?? '').toString(), c),
                          ),
                        if (reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
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
                                          color: (entry.value as List)
                                                  .contains(_myId)
                                              ? c.accent.withOpacity(0.18)
                                              : c.ink.withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: Text(
                                            '${entry.key} ${(entry.value as List).length}',
                                            style: TextStyle(
                                                fontSize: 12, color: c.ink)),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Group messages carried no timestamp at all — 1:1 has always
            // shown one. Same formatter, so both read identically.
            Padding(
              padding: EdgeInsets.only(
                  top: 2, right: isOwn ? 4 : 0, left: isOwn ? 0 : 42),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (msg['is_edited'] == true)
                  Text('${context.t('editedMark')} · ',
                      style: TextStyle(color: c.inkSoft, fontSize: 10)),
                Text(_fmtTime(msg['created_at']),
                    style: TextStyle(color: c.inkSoft, fontSize: 10)),
                if (isOwn) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showSeenBy(msg),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          seenCount > 0
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 13,
                          color: seenCount > 0 ? c.accent : c.inkSoft),
                      if (seenCount > 0) ...[
                        const SizedBox(width: 2),
                        Text('$seenCount',
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 10.5)),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ),
    );
  }

  /// Server timestamps come back without a 'Z' even though they're UTC —
  /// always via parseServerTime, never bare DateTime.parse.
  String _fmtTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = ApiService.parseServerTime(raw.toString());
      return '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _textWithLink(String content, BrutalColors c) {
    final url = firstUrl(content);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(content,
              style: TextStyle(color: c.ink, fontSize: 15, height: 1.3)),
          if (url != null)
            SizedBox(width: 220, child: LinkPreviewCard(url: url)),
        ]);
  }

  // ─── Search in chat ───────────────────────────────────────────────────────

  /// Drops anchors for messages that have left the list, so the map cannot
  /// grow without bound as `tmp_…` ids are swapped for server ids.
  void _pruneBubbleKeys() {
    if (_bubbleKeys.length <= messages.length) return;
    final live = messages.map((m) => m['id'].toString()).toSet();
    _bubbleKeys.removeWhere((id, _) => !live.contains(id));
  }

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

  void _toggleSearch() {
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchCtrl.clear();
        _searchMatches = [];
        _searchIndex = -1;
      }
    });
    if (_searchMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _msgFocus.unfocus());
    }
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
    _scrollToMessage(messages[_searchMatches[_searchIndex]]['id'].toString());
  }

  void _stepMatch(int delta) {
    if (_searchMatches.isEmpty) return;
    setState(() => _searchIndex =
        (_searchIndex + delta).clamp(0, _searchMatches.length - 1));
    _jumpToMatch();
  }

  /// Pin/unpin. Passing null to the endpoint unpins. Non-admins are told why
  /// instead of watching the action quietly do nothing.
  Future<void> _togglePin(Map msg) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('pinAdminOnly'))));
      return;
    }
    final id = msg['id'].toString();
    final unpin = _pinned != null && _pinned!['id']?.toString() == id;
    final snap = unpin
        ? null
        : {
            'id': id,
            'sender_id': msg['sender_id'],
            'sender_name': _memberName(msg['sender_id']),
            'content': msg['content'],
            'message_type': msg['message_type'] ?? 'text',
            'created_at': msg['created_at'],
          };
    setState(() => _pinned = snap); // optimistic — the socket confirms
    final r = await ApiService.pinGroupMessage(_groupId, snap);
    if (r['success'] != true && mounted) {
      // Roll back rather than leave a pin the server rejected.
      setState(() => _pinned = unpin ? _pinned : null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('pinAdminOnly'))));
    }
  }

  void _deleteSelected() {
    final mine = messages
        .where((m) =>
            _selected.contains(m['id'].toString()) &&
            m['sender_id']?.toString() == _myId)
        .map((m) => m['id'].toString())
        .toList();
    setState(() {
      messages.removeWhere((m) => mine.contains(m['id'].toString()));
      _selected.clear();
    });
    _saveCache();
    for (final id in mine) {
      ApiService.deleteGroupMessage(_groupId, id);
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

  AppBar _selectionAppBar(BrutalColors c) {
    final canDelete = messages.any((m) =>
        _selected.contains(m['id'].toString()) &&
        m['sender_id']?.toString() == _myId);
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
            onPressed: _copySelected),
        if (canDelete)
          IconButton(
              icon: Icon(Icons.delete_rounded, color: c.danger),
              onPressed: _deleteSelected),
      ],
    );
  }

  /// Tapping a voice bubble toggles it; starting another stops the first,
  /// since a single player is shared by the whole screen.
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

  Widget _inputBar(BrutalColors c) {
    // Shared with 1:1 chat — voice recording included, which group chat had
    // no way to reach before.
    return ChatComposer(
      msgCtrl: _msgCtrl,
      editCtrl: _editCtrl,
      focusNode: _msgFocus,
      showEmoji: _showEmoji,
      isEditing: _editingId != null,
      userId: _myId,
      onToggleEmoji: _toggleEmoji,
      onSend: _send,
      onSaveEdit: _saveEdit,
      onVoiceRecorded: _onVoiceRecorded,
      onVoiceUploaded: _onVoiceUploaded,
    );
  }

  /// Shows the voice bubble straight away, playable from the local file while
  /// the upload runs — same behaviour as 1:1 chat.
  void _onVoiceRecorded(String localPath, int secs) {
    setState(() {
      messages = [
        ...messages,
        {
          'id': 'voice_$localPath',
          'group_id': _groupId,
          'sender_id': _myId,
          'content': '${secs}s',
          'message_type': 'voice',
          'media_url': localPath,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          '_pending': true,
        }
      ];
    });
    _scrollToBottom();
  }

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

  @override
  void dispose() {
    _timer?.cancel();
    _linkDebounce?.cancel();
    ActiveChat.close(_groupId);
    _playbackDoneSub?.cancel();
    _pinSub?.cancel();
    _audioPlayer.dispose();
    _msgSub?.cancel();
    _seenSub?.cancel();
    _reactionSub?.cancel();
    _editSub?.cancel();
    _msgCtrl.dispose();
    _editCtrl.dispose();
    _searchCtrl.dispose();
    _msgFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
