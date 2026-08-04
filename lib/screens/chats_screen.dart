import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/catalog_cache.dart';
import '../services/chat_store.dart';
import '../services/socket_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/action_menu.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/pro_badge.dart';
import '../widgets/verified_badge.dart';
import '../widgets/notes_strip.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';
import 'group_create_screen.dart';
import 'search_screen.dart';

/// Built-in chat list (our own server).
class ChatsScreen extends StatefulWidget {
  final Map user;
  const ChatsScreen({super.key, required this.user});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List _chats = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  StreamSubscription? _msgSub;
  StreamSubscription? _readSub;
  StreamSubscription? _deliveredSub;
  StreamSubscription? _groupMsgSub;

  // Notes collapse smoothly as the list scrolls, tied straight to the
  // controller shared by all three list states below — NOT to unmounting
  // NotesStrip (see the comment on `body` for why that regressed before).
  final ScrollController _listCtrl = ScrollController();
  final ValueNotifier<double> _notesReveal = ValueNotifier(1.0);

  // Telegram-style multi-select: long-press a row to open its menu (which
  // offers "Select" as one option) or to enter select mode directly with
  // that row already checked. Keyed by kind+id since chat and group ids are
  // separate UUID spaces that could theoretically collide.
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};
  String _keyOf(Map chat) => '${chat['_kind']}_${chat['id']}';

  String? _otherUserId(Map chat) {
    final me = widget.user['id'].toString();
    for (final id in [
      chat['other_user_id'],
      chat['user1_id'],
      chat['user2_id'],
    ]) {
      if (id != null && id.toString() != me) return id.toString();
    }
    return null;
  }

  Future<bool> _confirm(String text) async {
    final c = context.k;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: c.surface,
            title:
                Text(context.t('areYouSure'), style: TextStyle(color: c.ink)),
            content: Text(text, style: TextStyle(color: c.inkSoft)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t('cancelBtn'),
                      style: TextStyle(color: c.inkSoft))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t('yesBtn'),
                      style: TextStyle(color: c.danger))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _removeOne(Map chat) async {
    final isGroup = chat['_kind'] == 'group';
    final ok = await _confirm(context.t(
        isGroup ? 'leaveGroupConfirm' : 'deleteChatConfirm'));
    if (!ok || !mounted) return;
    if (isGroup) {
      await ApiService.removeGroupMember(
          chat['id'].toString(), widget.user['id'].toString());
    } else {
      await ApiService.deleteChat(chat['id'].toString());
    }
    if (mounted) {
      setState(() => _chats.removeWhere((x) => _keyOf(x) == _keyOf(chat)));
    }
  }

  void _onLongPressChat(Map chat) {
    if (_selectMode) return; // already selecting — a tap toggles instead
    HapticFeedback.mediumImpact();
    final isGroup = chat['_kind'] == 'group';
    final last = (chat['last_message'] ?? '').toString();
    final otherId = _otherUserId(chat);
    ActionMenu.chat(
      context,
      isGroup: isGroup,
      onCopyLast: last.isEmpty
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: last));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(context.t('copiedShort'))));
            },
      onBlock: (!isGroup && otherId != null)
          ? () async {
              await ApiService.blockUser(otherId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t('blockedDone'))));
              setState(() => _chats.removeWhere((x) => _keyOf(x) == _keyOf(chat)));
            }
          : null,
      onDelete: () => _removeOne(chat),
      onSelect: () => setState(() {
        _selectMode = true;
        _selectedKeys.add(_keyOf(chat));
      }),
    );
  }

  void _onTapChat(Map chat) {
    if (_selectMode) {
      setState(() {
        final k = _keyOf(chat);
        if (!_selectedKeys.remove(k)) _selectedKeys.add(k);
        if (_selectedKeys.isEmpty) _selectMode = false;
      });
      return;
    }
    _openChat(chat);
  }

  void _exitSelectMode() => setState(() {
        _selectMode = false;
        _selectedKeys.clear();
      });

  Future<void> _deleteSelected() async {
    final targets =
        _chats.where((x) => _selectedKeys.contains(_keyOf(x))).toList();
    if (targets.isEmpty) return;
    final ok = await _confirm(context
        .t('deleteSelectedConfirm')
        .replaceAll('{n}', '${targets.length}'));
    if (!ok || !mounted) return;
    for (final chat in targets) {
      if (chat['_kind'] == 'group') {
        await ApiService.removeGroupMember(
            chat['id'].toString(), widget.user['id'].toString());
      } else {
        await ApiService.deleteChat(chat['id'].toString());
      }
    }
    if (!mounted) return;
    setState(() {
      _chats.removeWhere((x) => _selectedKeys.contains(_keyOf(x)));
      _selectedKeys.clear();
      _selectMode = false;
    });
  }

  void _onListScroll() {
    if (!_listCtrl.hasClients) return;
    final offset = _listCtrl.offset.clamp(0.0, 40.0);
    final v = 1.0 - (offset / 40.0);
    if (v != _notesReveal.value) _notesReveal.value = v;
  }

  @override
  void initState() {
    super.initState();
    _listCtrl.addListener(_onListScroll);
    _load();
    // This screen stays alive for the whole logged-in session (MainScreen
    // keeps it in an IndexedStack), so it's the natural place to persist
    // incoming messages / read receipts to on-device history EVEN when no
    // specific chat is open — otherwise a 'messages_read' event that arrives
    // while the user is just sitting on this list was lost forever (nothing
    // was listening, and the server drops the row once acked).
    SocketService().connect(widget.user['id'].toString());
    _msgSub = SocketService().onMessage.listen(_onIncoming);
    _readSub = SocketService().onRead.listen(_onRead);
    _deliveredSub = SocketService().onDelivered.listen(_onDelivered);
    _groupMsgSub = SocketService().onGroupMessage.listen(_onGroupIncoming);
  }

  /// Their phone picked our last message up — list tick goes ✓ → ✓✓ without
  /// waiting for a refresh.
  void _onDelivered(Map data) {
    final chatId = data['chatId']?.toString();
    if (chatId == null || !mounted) return;
    final i = _chats.indexWhere((c) => (c['id'] ?? '').toString() == chatId);
    if (i >= 0 && _chats[i]['last_delivered'] != true) {
      setState(() => _chats[i]['last_delivered'] = true);
    }
  }

  /// One-line preview for the list row, based on message type — same
  /// convention as _quoteSnippet in chat_detail_screen.dart.
  String _previewFor(Map data) {
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

  /// Patches the affected row in place and bumps it to the top, instead of
  /// re-fetching the whole list — a Render free-tier round trip on every
  /// single incoming message/group message made this screen (nicknamed
  /// "Sigmagram") feel sluggish the more active a user's chats got. Falls
  /// back to a real refresh only for a chat/group this screen hasn't seen
  /// yet (a brand-new conversation).
  void _bumpRow({required String id, required bool isGroup, required Map data}) {
    if (!mounted) return;
    final i = _chats.indexWhere(
        (c) => (c['id'] ?? '').toString() == id && (c['_kind'] == 'group') == isGroup);
    if (i < 0) {
      _load();
      return;
    }
    setState(() {
      final chat = _chats[i];
      chat['last_message'] = _previewFor(data);
      chat['last_sender_id'] = data['sender_id'];
      chat['last_read'] = false;
      chat['last_delivered'] = false;
      chat['updated_at'] = data['created_at'] ?? DateTime.now().toIso8601String();
      _chats
        ..removeAt(i)
        ..insert(0, chat);
    });
  }

  Future<void> _onGroupIncoming(Map data) async {
    final groupId = data['group_id']?.toString();
    final id = data['id']?.toString();
    if (groupId == null || id == null) return;
    final key = 'group_$groupId';
    final local = await ChatStore.load(key);
    if (!local.any((m) => m['id']?.toString() == id)) {
      await ChatStore.save(key, [...local, data]);
    }
    if (data['sender_id']?.toString() != widget.user['id'].toString()) {
      ApiService.ackGroupMessages(groupId, [id]);
    }
    _bumpRow(id: groupId, isGroup: true, data: data);
  }

  Future<void> _onIncoming(Map data) async {
    final chatId = data['chat_id']?.toString();
    final id = data['id']?.toString();
    if (chatId == null || id == null) return;
    final local = await ChatStore.load(chatId);
    if (!local.any((m) => m['id']?.toString() == id)) {
      await ChatStore.save(chatId, [...local, data]);
    }
    if (data['sender_id']?.toString() != widget.user['id'].toString()) {
      ApiService.ackMessages(chatId, [id]);
    }
    _bumpRow(id: chatId, isGroup: false, data: data);
  }

  Future<void> _onRead(Map data) async {
    final chatId = data['chatId']?.toString();
    if (chatId == null) return;
    // The server emits this to BOTH participants, so I also receive it when
    // *I* am the reader — acting on that marked my OWN messages as read the
    // moment I opened the chat, which is why the ticks looked wrong.
    if (data['reader']?.toString() == widget.user['id'].toString()) return;
    final ids = (data['ids'] as List?)?.map((e) => e.toString()).toSet();
    final local = await ChatStore.load(chatId);
    var changed = false;
    for (final m in local) {
      final mine = m['sender_id']?.toString() == widget.user['id'].toString();
      if (mine && (ids == null || ids.contains(m['id']?.toString())) && m['is_read'] != true) {
        m['is_read'] = true;
        changed = true;
      }
    }
    if (changed) await ChatStore.save(chatId, local);
    // Flip this row's ✓ → ✓✓ right away instead of waiting for the next
    // /api/chats refresh (the reader is the OTHER side, so my last message
    // has now been seen).
    if (data['reader']?.toString() != widget.user['id'].toString() && mounted) {
      final i = _chats.indexWhere((ch) => ch['id']?.toString() == chatId);
      if (i >= 0 && _chats[i]['last_read'] != true) {
        setState(() => _chats[i]['last_read'] = true);
      }
    }
  }

  Future<void> _load() async {
    // Cached copy first — the list appears instantly, network refreshes it.
    final key = 'chats_${widget.user['id']}';
    if (_chats.isEmpty) {
      final cached = CatalogCache.get(key);
      if (cached != null && cached.isNotEmpty) {
        setState(() { _chats = cached; _loading = false; });
      }
    }
    // Groups and 1:1 chats merge into ONE list (Telegram-style), sorted by
    // whichever was most recently active.
    final results = await Future.wait([
      ApiService.getChats(widget.user['id'].toString()),
      ApiService.getGroups(),
    ]);
    final chats = results[0].map((e) => {...Map.from(e), '_kind': 'chat'}).toList();
    final groups = results[1].map((e) => {...Map.from(e), '_kind': 'group'}).toList();
    final data = [...chats, ...groups]
      ..sort((a, b) => (b['updated_at'] ?? b['created_at'] ?? '')
          .toString()
          .compareTo((a['updated_at'] ?? a['created_at'] ?? '').toString()));
    if (!mounted) return;
    if (data.isNotEmpty) {
      CatalogCache.put(key, data.map((e) => Map.from(e)).toList());
    }
    if (data.isNotEmpty || _chats.isEmpty) {
      setState(() { _chats = data; _loading = false; });
    }
  }

  void _openChat(Map chat) {
    final isGroup = chat['_kind'] == 'group';
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => isGroup
              ? GroupChatScreen(user: widget.user, group: chat)
              : ChatDetailScreen(chat: chat, user: widget.user)),
    ).then((_) => _load());
  }

  void _openDiscover() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen(user: widget.user)),
    );
  }

  void _openNewGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupCreateScreen(user: widget.user)),
    ).then((_) => _load());
  }

  Future<void> _showNewMenu() async {
    final c = context.k;
    await showGlassSheet(
      context,
      title: context.t('newSheetTitle'),
      subtitle: context.t('newSheetSubtitle'),
      actions: [
        GlassAction(
          icon: Icons.person_rounded,
          title: context.t('newChatBtn'),
          subtitle: context.t('newChatSub'),
          onTap: _openDiscover,
        ),
        GlassAction(
          icon: Icons.groups_rounded,
          title: context.t('newGroupBtn'),
          subtitle: context.t('newGroupSub'),
          tint: c.accent2,
          onTap: _openNewGroup,
        ),
      ],
    );
  }

  List get _filtered {
    if (_query.trim().isEmpty) return _chats;
    final q = _query.trim().toLowerCase();
    return _chats
        .where((c) => (c['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final list = _filtered;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: _selectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectMode,
              ),
              title: Text(context
                  .t('chatsSelectedCount')
                  .replaceAll('{n}', '${_selectedKeys.length}')),
              actions: [
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(title: const Text('Sigmagram')),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton(
              backgroundColor: c.accentFill,
              onPressed: _showNewMenu,
              child: const Icon(Icons.add_comment_rounded, color: Colors.white),
            ),
      // Search and Notes are PINNED above the scrollable, not children of it.
      //
      // As ListView children they were unmounted once scrolled past the cache
      // extent, so scrolling back rebuilt NotesStrip from scratch: its state
      // reset to "not loaded", the note vanished, and it re-fetched from the
      // network — the disappearing-note bug, plus an API call per scroll.
      body: Column(children: [
        Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: context.t('searchChats'),
                  prefixIcon: Icon(Icons.search_rounded, color: c.inkSoft),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: c.inkSoft),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
        // Stays mounted at all times — only its reveal (size + opacity)
        // animates. Rebuilding NotesStrip itself from scratch on every
        // scroll tick is exactly the disappearing-note bug this class's
        // other comment describes, so the `child:` param below hands
        // ValueListenableBuilder the SAME instance across every rebuild
        // instead of a fresh one from a closure.
        ValueListenableBuilder<double>(
          valueListenable: _notesReveal,
          builder: (_, reveal, child) => ClipRect(
            child: Align(
              heightFactor: reveal,
              alignment: Alignment.topCenter,
              child: Opacity(opacity: reveal, child: child),
            ),
          ),
          child: NotesStrip(user: widget.user),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            // ListView.builder rather than a ListView of mapped children —
            // the old version built every row's widget tree (avatar image,
            // verified badge, tick icons) up front regardless of scroll
            // position, which only got heavier as the chat list grew.
            // Loading/empty states still need SOME scrollable so pull-to-
            // refresh keeps working even with nothing (or not yet anything)
            // to show. All three share _listCtrl so the notes-collapse
            // tracking above works no matter which state is on screen.
            child: _loading
                ? ListView(controller: _listCtrl, children: const [
                    Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(child: CircularProgressIndicator())),
                  ])
                : list.isEmpty
                    ? ListView(controller: _listCtrl, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Center(
                            child: Text(
                              _query.isEmpty
                                  ? context.t('noChats')
                                  : context.t('nothingFound'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.inkSoft, height: 1.4),
                            ),
                          ),
                        ),
                      ])
                    : ListView.builder(
                        controller: _listCtrl,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _chatTile(c, list[i]),
                      ),
          ),
        ),
      ]),
    );
  }

  Widget _chatTile(BrutalColors c, Map chat) {
    final isGroup = chat['_kind'] == 'group';
    final name = (chat['name'] ?? 'User').toString();
    final avatar = isGroup ? chat['avatar_url'] : chat['avatar'];
    final last = (chat['last_message'] ?? '').toString();
    final selected = _selectMode && _selectedKeys.contains(_keyOf(chat));
    return Container(
      color: selected ? c.accent.withOpacity(0.08) : null,
      child: ListTile(
      onTap: () => _onTapChat(chat),
      onLongPress: () => _onLongPressChat(chat),
      leading: Stack(children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: c.surface2,
          backgroundImage:
              avatar != null ? CachedNetworkImageProvider(avatar.toString()) : null,
          child: avatar == null
              ? Icon(isGroup ? Icons.groups_rounded : Icons.person, color: c.inkSoft)
              : null,
        ),
        // Telegram-style: a check overlays the avatar once in select mode,
        // instead of adding a whole extra leading column just for this.
        if (_selectMode)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : c.surface,
                border: Border.all(color: c.bg, width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 13)
                  : null,
            ),
          ),
      ]),
      // Groups aren't verified accounts, so the badge is 1:1 only.
      title: VerifiedName(
        name: name,
        verified: !isGroup && chat['is_verified'] == true,
        isPro: !isGroup && chat['is_pro'] == true,
        proBadgeGif: chat['pro_badge_gif']?.toString(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      // Telegram-style ✓/✓✓ before the preview, but only when the last
      // message is MINE — a tick on someone else's message would be
      // meaningless. Groups have no per-member tick here (that's what the
      // in-chat "Seen by" list is for).
      subtitle: Row(children: [
        if (!isGroup &&
            last.isNotEmpty &&
            (chat['last_sender_id'] ?? '').toString() ==
                widget.user['id'].toString()) ...[
          // Same three states as the in-chat tick: ✓ sent, ✓✓ delivered,
          // ✓✓ accent read.
          Icon(
              (chat['last_read'] == true || chat['last_delivered'] == true)
                  ? Icons.done_all_rounded
                  : Icons.done_rounded,
              size: 15,
              color: chat['last_read'] == true ? c.accent : c.inkSoft),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(last.isEmpty ? context.t('noMsgsShort') : last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.inkSoft)),
        ),
      ]),
      trailing: Icon(Icons.chevron_right, color: c.inkSoft),
      ),
    );
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _readSub?.cancel();
    _deliveredSub?.cancel();
    _groupMsgSub?.cancel();
    _searchCtrl.dispose();
    _listCtrl.removeListener(_onListScroll);
    _listCtrl.dispose();
    _notesReveal.dispose();
    super.dispose();
  }
}
