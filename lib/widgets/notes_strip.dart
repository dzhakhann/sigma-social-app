import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../screens/profile_screen.dart';

/// Instagram-style "Notes" strip: a short text-only note (no music — by
/// request), visible only to MUTUAL follows, auto-expiring after 24h
/// (entirely server-enforced — see /api/notes). Sits above the chat list.
class NotesStrip extends StatefulWidget {
  final Map user;
  const NotesStrip({super.key, required this.user});
  @override
  State<NotesStrip> createState() => _NotesStripState();
}

class _NotesStripState extends State<NotesStrip> {
  List<Map> _notes = [];
  bool _loaded = false;

  // Fixed tile geometry — text below is scale-locked to this budget (see
  // build()) so it can never overflow into the chat row underneath, which
  // is exactly the bug this replaced (the old fixed SizedBox(height: 92)
  // was a few pixels shorter than its own content at default font scale,
  // and shorter still under a larger system font — a plain list child has
  // no clip boundary of its own, so the overflow bled into the next tile).
  //
  // _speechBubble wraps up to 2 lines (fontSize 11, height 1.15 -> ~12.65px
  // per line) plus 12px vertical padding plus the tail's 4px margin, so a
  // 2-line note needs ~41px — 34 was sized for one line only. Any note past
  // roughly a dozen characters wrapped to a second line that this SizedBox
  // then clipped, and the avatar painted right below it covered what spilled
  // out: the "second half missing" bug.
  static const _bubbleH = 44.0;
  static const _avatarD = 54.0;
  static const _nameH = 15.0;
  static const _tileH = _bubbleH + 6 + _avatarD + 6 + _nameH;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getNotes();
    if (mounted) setState(() { _notes = data; _loaded = true; });
  }

  Map? get _mine {
    for (final n in _notes) {
      if (n['is_mine'] == true) return n;
    }
    return null;
  }

  List<Map> get _others => _notes.where((n) => n['is_mine'] != true).toList();

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (!_loaded) return SizedBox(height: _tileH + 16);
    // Scale-locked: this is small decorative chrome (avatar strip), not
    // reading content — letting the system font-size setting stretch it
    // is what caused the overflow bug in the first place.
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.0)),
      child: SizedBox(
        height: _tileH + 16,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _tile(
              c,
              avatar: (widget.user['avatar_url'] ?? '').toString(),
              username: context.t('yourNote'),
              noteText: (_mine?['text'] ?? '').toString(),
              isMine: true,
              onTap: _openCompose,
            ),
            for (final n in _others)
              _tile(
                c,
                avatar: (n['avatar_url'] ?? '').toString(),
                username: (n['username'] ?? '').toString(),
                noteText: (n['text'] ?? '').toString(),
                isMine: false,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      user: widget.user,
                      targetUserId: n['user_id'],
                      isOwnProfile: false,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BrutalColors c, {
    required String avatar,
    required String username,
    required String noteText,
    required bool isMine,
    required VoidCallback onTap,
  }) {
    final hasNote = noteText.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 8),
        child: Column(children: [
          SizedBox(
            height: _bubbleH,
            child: hasNote ? _speechBubble(c, noteText) : null,
          ),
          const SizedBox(height: 6),
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: _avatarD,
              height: _avatarD,
              padding: const EdgeInsets.all(2.4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasNote ? c.storyGradient : null,
                color: hasNote ? null : c.ink.withOpacity(0.12),
              ),
              child: ClipOval(
                child: Container(
                  color: c.surface2,
                  child: avatar.isEmpty
                      ? Icon(Icons.person_rounded, color: c.inkSoft)
                      : CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover),
                ),
              ),
            ),
            if (isMine)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 13),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: _nameH,
            child: Text(username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.inkSoft, fontSize: 11)),
          ),
        ]),
      ),
    );
  }

  /// Apple/Instagram-style speech bubble: rounded card + a small tail
  /// pointing down at the avatar, built as one fused shape (a rotated
  /// square tucked behind the card so only its bottom triangle peeks out —
  /// no seam between card and tail).
  Widget _speechBubble(BrutalColors c, String text) {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: 1,
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                      color: c.shadow.withOpacity(0.10),
                      blurRadius: 3,
                      offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
        Container(
          constraints: const BoxConstraints(maxWidth: 82),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: c.shadow.withOpacity(0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.ink, fontSize: 11, height: 1.15, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  List<String> _suggestions(BuildContext context) => [
        '💬 ${context.t('noteSuggChat')}',
        '📚 ${context.t('noteSuggStudy')}',
        '😴 ${context.t('noteSuggRest')}',
        '🎯 ${context.t('noteSuggBusy')}',
        '📞 ${context.t('noteSuggCall')}',
        '🚀 ${context.t('noteSuggGrind')}',
        '❤️ ${context.t('noteSuggGreat')}',
      ];

  Future<void> _openCompose() async {
    final c = context.k;
    final ctrl = TextEditingController(text: (_mine?['text'] ?? '').toString());
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: c.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2)),
              ),
              // A live preview of the bubble itself sells the feature much
              // better than a plain title — you see exactly what will show
              // up in the strip as you type.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: ctrl,
                builder: (_, value, __) {
                  final preview = value.text.trim();
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: preview.isEmpty
                        ? SizedBox(
                            key: const ValueKey('empty'),
                            height: _bubbleH,
                            child: Center(
                              child: Icon(Icons.chat_bubble_outline_rounded,
                                  color: c.inkSoft, size: 22),
                            ),
                          )
                        : SizedBox(
                            key: const ValueKey('preview'),
                            height: _bubbleH,
                            child: Center(child: _speechBubble(c, preview)),
                          ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(context.t('yourNoteTitle'),
                  style: TextStyle(
                      color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(context.t('noteHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 60,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink, fontSize: 15),
                decoration: InputDecoration(
                  hintText: context.t('noteFieldHint'),
                  counterStyle: TextStyle(color: c.inkSoft, fontSize: 11),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in _suggestions(context))
                    GestureDetector(
                      onTap: () => ctrl.text = s,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(s, style: TextStyle(color: c.ink, fontSize: 12)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                if (_mine != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        await ApiService.deleteNote();
                        _load();
                      },
                      child: Text(context.t('deleteNote')),
                    ),
                  ),
                if (_mine != null) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: c.accentFill),
                    onPressed: () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      Navigator.pop(sheetCtx);
                      await ApiService.postNote(text);
                      _load();
                    },
                    child: Text(context.t('shareNote')),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
