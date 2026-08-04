import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/pro_badge.dart';
import '../widgets/verified_badge.dart';
import '../l10n/app_strings.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/action_menu.dart';
import '../widgets/post_media_carousel.dart';
import '../widgets/link_preview.dart';
import '../widgets/music_widgets.dart';

/// Instagram-style single-post view: the post (carousel + engagement row) at
/// the top, replies below as a thread. A full screen (was a bottom sheet) —
/// matches Instagram's own post-detail view instead of a partial sheet.
class CommentsScreen extends StatefulWidget {
  final Map post;
  final Map user;
  const CommentsScreen({Key? key, required this.post, required this.user})
      : super(key: key);

  /// Opens the post as a full-screen route (post on top, replies below).
  static Future<void> show(BuildContext context,
      {required Map post, required Map user}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommentsScreen(post: post, user: user)),
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

  // Local copy so liking/reposting updates instantly without re-fetching
  // the whole post from the server.
  late bool _isLiked = widget.post['is_liked'] == true;
  late int _likesCount = (widget.post['likes_count'] ?? 0) as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _toggleLike() async {
    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !wasLiked;
      _likesCount += wasLiked ? -1 : 1;
    });
    try {
      await ApiService.likePost(widget.post['id'].toString(), widget.user['id'].toString());
    } catch (_) {
      if (mounted) setState(() { _isLiked = wasLiked; _likesCount -= wasLiked ? -1 : 1; });
    }
  }

  Future<void> _repost() async {
    // Optimistic: confirm instantly and let the request finish in the
    // background — waiting on a sleepy free-tier backend made every repost
    // feel like the button hadn't registered.
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.t('reposted'))));
    try {
      await ApiService.repostPost(widget.post['id'].toString());
    } catch (_) {}
  }

  Future<void> _editPost() async {
    final c = context.k;
    final ctrl = TextEditingController(text: (widget.post['content'] ?? '').toString());
    final newContent = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.t('mEdit'),
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 6,
                minLines: 1,
                style: TextStyle(color: c.ink),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.accentFill),
                  onPressed: () => Navigator.pop(sheetCtx, ctrl.text.trim()),
                  child: Text(context.t('saveBtn')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (newContent == null || newContent.isEmpty || !mounted) return;
    final r = await ApiService.editPost(widget.post['id'].toString(), newContent);
    if (r['success'] == true) {
      setState(() => widget.post['content'] = newContent);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Failed')));
    }
  }

  Future<void> _deletePost() async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('deletePostTitle')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(context.t('cancelBtn'))),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(context.t('mDelete'), style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ApiService.deletePost(widget.post['id'].toString());
    if (r['success'] == true) {
      if (mounted) Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r['error']?.toString() ?? 'Failed')));
    }
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
      return timeago.format(ApiService.parseServerTime(raw.toString()),
          locale: 'en_short');
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(context.t('postLabel')),
      ),
      body: Column(
          children: [
            Flexible(
              child: ListView(
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
    final hasMedia = PostMediaCarousel.urlsOf(p).isNotEmpty;
    final isOwn = p['user_id'] == widget.user['id'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
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
                      const VerifiedBadge(),
                    ],
                    if (p['is_pro'] == true) ...[
                      const SizedBox(width: 4),
                      ProBadge(
                          isPro: true,
                          gifUrl: p['pro_badge_gif']?.toString(),
                          height: 18),
                    ],
                    const Spacer(),
                    Text(_time(p['created_at']),
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    GestureDetector(
                      onTap: () => ActionMenu.post(
                        context,
                        postId: p['id'].toString(),
                        authorId: (p['user_id'] ?? '').toString(),
                        isOwn: isOwn,
                        onEdit: _editPost,
                        onDelete: _deletePost,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.more_vert_rounded,
                            size: 18, color: c.inkSoft),
                      ),
                    ),
                  ]),
                  if ((p['content'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p['content'],
                        style: TextStyle(fontSize: 15, height: 1.35, color: c.ink)),
                  ],
                  // Link preview (Telegram-style unfurl) — same rule as the
                  // feed: only when the post has no photos of its own.
                  if (!hasMedia && firstUrl((p['content'] ?? '').toString()) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: () {
                          final u = firstUrl((p['content'] ?? '').toString())!;
                          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                        },
                        child: LinkPreviewCard(
                            url: firstUrl((p['content'] ?? '').toString())!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (hasMedia)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PostMediaCarousel(post: p, height: 340),
        ),
      if (p['music'] is Map)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: PostMusicBar(track: Map<String, dynamic>.from(p['music'])),
        ),
      // ── Instagram-style engagement row: like / comment / repost / save ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 0),
        child: Row(children: [
          IconButton(
            icon: Icon(
                _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _isLiked ? c.danger : c.inkSoft),
            onPressed: _toggleLike,
          ),
          if (_likesCount > 0)
            Text('$_likesCount',
                style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600)),
          IconButton(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: c.inkSoft),
            onPressed: () => _focus.requestFocus(),
          ),
          if (comments.isNotEmpty) Text('${comments.length}', style: TextStyle(color: c.inkSoft)),
          IconButton(
            icon: Icon(Icons.repeat_rounded, color: c.inkSoft),
            onPressed: _repost,
          ),
          const Spacer(),
        ]),
      ),
    ]);
  }

  Widget _reply(BrutalColors c, Map cm) {
    final isOwn = cm['user_id'] == widget.user['id'];
    return GestureDetector(
      onLongPress: isOwn
          ? () => _menu(cm) // own: edit / delete
          : () => ActionMenu.comment(
                context,
                text: (cm['content'] ?? '').toString(),
                isOwn: false,
                commentId: '${cm['id']}',
              ),
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
