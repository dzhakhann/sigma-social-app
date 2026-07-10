import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/emoji_picker.dart';

/// Threads-style thread view: the post at the top, replies below as a thread.
class CommentsScreen extends StatefulWidget {
  final Map post;
  final Map user;
  const CommentsScreen({Key? key, required this.post, required this.user})
      : super(key: key);

  /// Opens the thread as a bottom sheet (post on top, replies below).
  static Future<void> show(BuildContext context,
      {required Map post, required Map user}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsScreen(post: post, user: user),
    );
  }

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List comments = [];
  bool isLoading = false;
  bool _sending = false;
  String? _editingId; // if set, the composer edits this comment instead

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    comments = await ApiService.getComments(widget.post['id']);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    // Show the comment immediately, then sync with the server.
    setState(() {
      _sending = true;
      comments.add({
        'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        'user_id': widget.user['id'],
        'username': widget.user['username'] ?? 'you',
        'user_avatar': widget.user['avatar_url'],
        'content': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    await ApiService.addComment(widget.post['id'], widget.user['id'], text);
    comments = await ApiService.getComments(widget.post['id']);
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(String id) async {
    await ApiService.deleteComment(id);
    _load();
  }

  void _menu(Map cm) {
    final c = context.k;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: c.accent),
            title: Text(context.t('editComment')),
            onTap: () {
              Navigator.pop(context);
              _startEdit(cm);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: c.danger),
            title: Text(context.t('deleteComment'), style: TextStyle(color: c.danger)),
            onTap: () {
              Navigator.pop(context);
              _delete(cm['id'].toString());
            },
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  // Telegram-style inline edit: load the comment into the bottom input.
  void _startEdit(Map cm) {
    setState(() {
      _editingId = cm['id'].toString();
      _ctrl.text = (cm['content'] ?? '').toString();
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _ctrl.clear();
    });
    _focus.unfocus();
  }

  Future<void> _saveEdit() async {
    final id = _editingId;
    final t = _ctrl.text.trim();
    if (id == null || t.isEmpty) return;
    setState(() {
      for (final cm in comments) {
        if (cm['id'].toString() == id) {
          cm['content'] = t;
          cm['is_edited'] = true;
        }
      }
      _editingId = null;
      _ctrl.clear();
    });
    _focus.unfocus();
    await ApiService.editComment(id, t);
    comments = await ApiService.getComments(widget.post['id']);
    if (mounted) setState(() {});
  }

  String _time(dynamic raw) {
    if (raw == null) return '';
    try {
      return timeago.format(DateTime.parse(raw.toString()).toLocal(),
          locale: 'en_short');
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final size = MediaQuery.of(context).size;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle + close (no title here — the post comes first).
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: c.ink.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2))),
                Positioned(
                  right: 4, top: 0,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, color: c.inkSoft),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  // 1) the publication itself
                  _head(c),
                  Divider(height: 1, color: c.ink.withOpacity(0.07)),
                  // 2) the "Ответы" label under the publication
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(context.t('repliesLabel'),
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
                  // 3) the comments
                  if (isLoading)
                    const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: CircularProgressIndicator()))
                  else if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30, bottom: 40),
                      child: Center(
                          child: Text(context.t('noReplies'),
                              style: TextStyle(color: c.inkSoft))),
                    )
                  else
                    ...comments.map((cm) => _reply(c, cm)),
                ],
              ),
            ),
            _composer(c),
          ],
        ),
      ),
    );
  }

  Widget _avatar(BrutalColors c, dynamic url, {double r = 18}) => CircleAvatar(
        radius: r,
        backgroundColor: c.surface2,
        backgroundImage:
            url != null ? CachedNetworkImageProvider(url.toString()) : null,
        child: url == null
            ? Icon(Icons.person, color: c.inkSoft, size: r)
            : null,
      );

  Widget _head(BrutalColors c) {
    final p = widget.post;
    final img = p['image_url'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(c, p['user_avatar'] ?? p['avatar_url'], r: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(p['username'] ?? 'user',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (p['is_verified'] == true) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 14, color: c.ink),
                  ],
                ]),
                if ((p['content'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p['content'],
                      style: TextStyle(fontSize: 15, height: 1.35, color: c.ink)),
                ],
                if (img != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                        imageUrl: img.toString(),
                        width: double.infinity,
                        fit: BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reply(BrutalColors c, Map cm) {
    final isOwn = cm['user_id'] == widget.user['id'];
    return GestureDetector(
      onLongPress: isOwn ? () => _menu(cm) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: c.ink.withOpacity(0.05), width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(c, cm['user_avatar'], r: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(cm['username'] ?? 'user',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    Text(
                        _time(cm['created_at']) +
                            (cm['is_edited'] == true ? ' · ${context.t('editedMark')}' : ''),
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  ]),
                  const SizedBox(height: 2),
                  Text(cm['content'] ?? '',
                      style: TextStyle(fontSize: 14, height: 1.35, color: c.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BrutalColors c) {
    final editing = _editingId != null;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.ink.withOpacity(0.06))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Telegram-style "editing" banner
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: editing
                ? Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                    child: Row(children: [
                      Icon(Icons.edit_rounded, size: 16, color: c.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(context.t('editingComment'),
                            style: TextStyle(
                                color: c.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close, size: 18, color: c.inkSoft),
                        onPressed: _cancelEdit,
                      ),
                    ]),
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
          EmojiPickerButton(controller: _ctrl),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => editing ? _saveEdit() : _add(),
              decoration: InputDecoration(
                  hintText: editing ? context.t('editCommentHint') : context.t('writeReplyHint'),
                  isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: editing ? _saveEdit : _add,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: c.accent, borderRadius: BorderRadius.circular(12)),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }
}
