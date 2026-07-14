import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'session.dart';
import '../screens/profile_screen.dart';
import '../screens/comments_screen.dart';

/// Handles incoming https://sigmacta.app/@username and /post/xxxx links,
/// opening the right screen inside the app (Telegram/Instagram deep links).
class DeepLinks {
  static final _appLinks = AppLinks();
  static final navKey = GlobalKey<NavigatorState>();

  static void init() {
    // Cold start + while-running links.
    _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static Future<void> _handle(Uri uri) async {
    final segs = uri.pathSegments;
    if (segs.isEmpty) return;
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    final me = await Session.load();
    if (me == null) return; // must be logged in to route

    // /@username  → profile
    var first = segs[0];
    if (first.startsWith('@')) first = first.substring(1);
    if (uri.path.contains('@') || (segs.length == 1 && first.isNotEmpty && segs[0].startsWith('@'))) {
      final u = await ApiService.userByUsername(first);
      final id = u['id'];
      if (id == null) return;
      navKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: me,
          targetUserId: id,
          isOwnProfile: id.toString() == me['id'].toString(),
        ),
      ));
      return;
    }

    // /post/xxxx  → open the post's thread
    if (segs[0] == 'post' && segs.length >= 2) {
      final post =
          await ApiService.getPost(segs[1], me['id'].toString());
      if (post == null) return;
      final c = navKey.currentContext;
      if (c != null) CommentsScreen.show(c, post: post, user: me);
    }
  }
}
