import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart' show S;
import 'api_service.dart';
import 'session.dart';
import 'sigma_link.dart';
import '../screens/comments_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/story_view_screen.dart';
import '../screens/video_podcast_screen.dart';

/// Opens shared Sigmacta links inside the app instead of in a browser.
///
/// Every shape it understands is defined once in [SigmaLink], which is also what
/// builds the links we hand out — so a link the app can produce is always a link
/// the app can open.
///
/// **A link is never dropped.** Arriving while signed out used to `return` and
/// forget it, which is exactly what makes install-then-open lose the content the
/// user came for. Now it's persisted and replayed once a session exists.
class DeepLinks {
  static final _appLinks = AppLinks();
  static final navKey = GlobalKey<NavigatorState>();

  static const _kPending = 'pending_deep_link';

  static void init() {
    // Links arriving while the app is already running. Meaningless on web —
    // a "new" link there is just a page navigation, always picked up by
    // getInitialLink() below — and the plugin has no web listener anyway
    // (calling it throws MissingPluginException into the console on every load).
    if (!kIsWeb) _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    // …and the link the app was STARTED from, read explicitly.
    //
    // The stream is not guaranteed to replay it: on web the initial URL is just
    // window.location and never arrives as an event at all, which is why
    // sigmacta.pages.dev/post/<id> loaded the app but showed the home screen
    // instead of the post.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri);
    }).catchError((_) {});
  }

  static Future<void> _handle(Uri uri) async {
    final link = SigmaLink.parse(uri);
    if (link == null) return;

    final me = await Session.load();
    if (me == null) {
      // Park it. [consumePending] replays it after login/registration.
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPending, link.url);
      return;
    }
    await open(link, me);
  }

  /// Replays a link parked while the user was signed out.
  ///
  /// Call right after a successful login/register and after the first frame of
  /// the main screen — the navigator has to exist before anything can be pushed.
  static Future<void> consumePending() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kPending);
    if (saved == null) return;
    // Cleared BEFORE routing: a link that fails to open (deleted post, expired
    // story) must not retry forever on every launch.
    await p.remove(_kPending);
    final me = await Session.load();
    final link = SigmaLink.parse(Uri.parse(saved));
    if (me == null || link == null) return;
    await open(link, me);
  }

  /// Routes a parsed link. Public so a notification tap can reuse it.
  static Future<void> open(SigmaLink link, Map me) async {
    switch (link.kind) {
      case SigmaLinkKind.profile:
        await _openProfile(link.id, me);
        break;
      case SigmaLinkKind.post:
      case SigmaLinkKind.reel:
        // Reels are posts with video; both open the same thread view.
        await _openPost(link.id, me);
        break;
      case SigmaLinkKind.story:
        await _openStory(link.id, me);
        break;
      case SigmaLinkKind.group:
        await _openGroup(link.id, me);
        break;
      case SigmaLinkKind.music:
        await _openMusic(link.id);
        break;
      case SigmaLinkKind.podcast:
        await _openPodcast(link.id);
        break;
    }
  }

  static Future<void> _openProfile(String username, Map me) async {
    final u = await ApiService.userByUsername(username);
    final id = u['id'];
    if (id == null) return _toast('linkUserNotFound');
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => ProfileScreen(
        user: me,
        targetUserId: id.toString(),
        isOwnProfile: id.toString() == me['id'].toString(),
      ),
    ));
  }

  static Future<void> _openPost(String id, Map me) async {
    final post = await ApiService.getPost(id, me['id'].toString());
    final ctx = navKey.currentContext;
    if (post == null || ctx == null) return _toast('linkPostNotFound');
    CommentsScreen.show(ctx, post: post, user: me);
  }

  static Future<void> _openStory(String id, Map me) async {
    final r = await ApiService.storyById(id);
    final stories = (r['stories'] as List?) ?? [];
    if (stories.isEmpty) return _toast('linkStoryExpired');
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => StoryViewScreen(
        stories: stories,
        allGroups: [stories],
        groupIndex: 0,
        startIndex: (r['index'] as int?) ?? 0,
        user: me,
      ),
    ));
  }

  static Future<void> _openMusic(String id) async {
    final track = await ApiService.musicTrackById(id);
    if (track == null) return _toast('linkNotFound');
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => VideoPodcastScreen(episode: track),
    ));
  }

  static Future<void> _openPodcast(String id) async {
    final ep = await ApiService.podcastEpisodeById(id);
    if (ep == null) return _toast('linkNotFound');
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => VideoPodcastScreen(episode: ep),
    ));
  }

  static Future<void> _openGroup(String id, Map me) async {
    final g = await ApiService.getGroup(id);
    // Non-members get a refusal from the server, so this doubles as the
    // "you're not in this group" case.
    if (g == null) return _toast('linkGroupNoAccess');
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => GroupChatScreen(user: me, group: g),
    ));
  }

  /// Tells the user WHY nothing opened. A shared link that silently does
  /// nothing is indistinguishable from a broken app.
  static void _toast(String key) {
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    // S.tr, not context.t: this runs from a link handler with no widget of its
    // own, and the message still has to follow the app language.
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(S.tr(key))));
  }
}
