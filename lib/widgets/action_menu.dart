import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';

/// Instagram/Telegram-style "⋯" action sheets, shared across the app
/// (profiles, posts, comments). Also hosts the report reason picker.
class ActionMenu {
  static const String base = 'https://sigmacta.pages.dev';

  static void _snack(BuildContext c, String msg) {
    ScaffoldMessenger.of(c)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  static Widget _tile(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap, {bool danger = false}) {
    final c = ctx.k;
    return ListTile(
      leading: Icon(icon, color: danger ? c.danger : c.ink),
      title: Text(label,
          style: TextStyle(
              color: danger ? c.danger : c.ink,
              fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  static Future<T?> _sheet<T>(BuildContext context, List<Widget> children) {
    final c = context.k;
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ...children,
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  // ─── PROFILE menu ──────────────────────────────────────────────────────────
  static void profile(BuildContext context, {
    required String userId,
    required String username,
    required bool isBlocked,
    VoidCallback? onChanged,
  }) {
    final link = '$base/@$username';
    _sheet(context, [
      _tile(context, Icons.share_rounded, context.t('mShareProfile'), () {
        Navigator.pop(context);
        Share.share(link);
      }),
      _tile(context, Icons.link_rounded, context.t('mCopyLink'), () {
        Clipboard.setData(ClipboardData(text: link));
        Navigator.pop(context);
        _snack(context, context.t('copiedShort'));
      }),
      _tile(context, Icons.flag_outlined, context.t('mReport'), () {
        Navigator.pop(context);
        reportReasons(context, 'user', userId, link: link);
      }, danger: true),
      _tile(
          context,
          isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
          isBlocked ? context.t('mUnblock') : context.t('mBlock'), () async {
        Navigator.pop(context);
        if (isBlocked) {
          await ApiService.unblockUser(userId);
          _snack(context, context.t('unblockedDone'));
        } else {
          await ApiService.blockUser(userId);
          _snack(context, context.t('blockedDone'));
        }
        onChanged?.call();
      }, danger: !isBlocked),
      _tile(context, Icons.visibility_off_outlined, context.t('mHide'),
          () async {
        Navigator.pop(context);
        await ApiService.hideUser(userId);
        _snack(context, context.t('hiddenDone'));
        onChanged?.call();
      }),
    ]);
  }

  // ─── POST menu ─────────────────────────────────────────────────────────────
  static void post(BuildContext context, {
    required String postId,
    required String authorId,
    VoidCallback? onChanged,
  }) {
    final link = '$base/post/$postId';
    _sheet(context, [
      _tile(context, Icons.link_rounded, context.t('mCopyLink'), () {
        Clipboard.setData(ClipboardData(text: link));
        Navigator.pop(context);
        _snack(context, context.t('copiedShort'));
      }),
      _tile(context, Icons.share_rounded, context.t('mShare'), () {
        Navigator.pop(context);
        Share.share(link);
      }),
      _tile(context, Icons.flag_outlined, context.t('mReport'), () {
        Navigator.pop(context);
        reportReasons(context, 'post', postId, link: link);
      }, danger: true),
      _tile(context, Icons.not_interested_rounded,
          context.t('mNotInterested'), () {
        Navigator.pop(context);
        _snack(context, context.t('hiddenDone'));
        onChanged?.call();
      }),
      _tile(context, Icons.visibility_off_outlined,
          context.t('mHideAuthor'), () async {
        Navigator.pop(context);
        await ApiService.hideUser(authorId);
        _snack(context, context.t('hiddenDone'));
        onChanged?.call();
      }),
    ]);
  }

  // ─── COMMENT menu ──────────────────────────────────────────────────────────
  static void comment(BuildContext context, {
    required String text,
    required bool isOwn,
    VoidCallback? onReply,
    VoidCallback? onDelete,
    String commentId = '',
  }) {
    _sheet(context, [
      if (onReply != null)
        _tile(context, Icons.reply_rounded, context.t('mReply'), () {
          Navigator.pop(context);
          onReply();
        }),
      _tile(context, Icons.copy_rounded, context.t('mCopyText'), () {
        Clipboard.setData(ClipboardData(text: text));
        Navigator.pop(context);
        _snack(context, context.t('copiedShort'));
      }),
      _tile(context, Icons.flag_outlined, context.t('mReport'), () {
        Navigator.pop(context);
        if (commentId.isNotEmpty) reportReasons(context, 'comment', commentId);
      }, danger: true),
      if (isOwn && onDelete != null)
        _tile(context, Icons.delete_outline_rounded, context.t('mDelete'), () {
          Navigator.pop(context);
          onDelete();
        }, danger: true),
    ]);
  }

  // ─── REPORT reason picker ──────────────────────────────────────────────────
  static void reportReasons(BuildContext context, String type, String id,
      {String link = ''}) {
    final reasons = [
      ['spam', 'rSpam'],
      ['harassment', 'rHarass'],
      ['violence', 'rViolence'],
      ['sexual', 'rSexual'],
      ['hate', 'rHate'],
      ['other', 'rOther'],
    ];
    final c = context.k;
    _sheet(context, [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(context.t('reportReason'),
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
      ...reasons.map((r) => _tile(context, Icons.outlined_flag_rounded,
              context.t(r[1]), () async {
            Navigator.pop(context);
            await ApiService.report(type, id, reason: r[0], link: link);
            _snack(context, context.t('reportSentShort'));
          })),
    ]);
  }
}
