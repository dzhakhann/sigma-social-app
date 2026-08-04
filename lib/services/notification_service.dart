import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_service.dart';
import 'deep_links.dart';
import 'session.dart';
import '../screens/comments_screen.dart';
import '../screens/profile_screen.dart';
import 'notification_prefs.dart';
import 'pro_state.dart';
import '../l10n/app_strings.dart' show S;

/// Local push for social activity (new post/story from someone you follow,
/// likes, comments, follows...) with a distinctive custom chime — a channel
/// of its own, separate from the podcast/story-upload notification channels.
///
/// This is the ONE place that actually renders a visible notification,
/// whichever transport woke it up: the live socket push (while the app
/// process is alive, see SocketService.onNotification) or a Firebase Cloud
/// Messaging data message (PushService — reaches a killed/backgrounded app
/// too). Both call [showForNotification] with the same shape, so a tap
/// behaves identically either way.
class NotificationService {
  NotificationService._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nextId = 900000;

  /// ONE CHANNEL PER TONE.
  ///
  /// An Android channel's sound is fixed at creation — changing it later is
  /// silently ignored for a channel that already exists, and deleting and
  /// recreating it resets any importance the user themselves changed. So a
  /// selectable tone means a separate channel per option, and the notification
  /// is posted to whichever one matches the current choice.
  static AndroidNotificationChannel _channelFor(String tone) =>
      AndroidNotificationChannel(
        'social_alerts_$tone',
        'Activity · ${tone[0].toUpperCase()}${tone.substring(1)}',
        description: 'Likes, comments, follows, new posts and stories',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notif_$tone'),
      );

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    // No web build of flutter_local_notifications exists at all — every
    // notification on web goes through MainScreen's in-app island instead
    // (see textFor/openFor), so there's nothing here for web to initialize.
    if (kIsWeb) return;
    // Android 13+ shows no notification at all without this permission —
    // don't rely on the story-upload flow having already asked for it.
    try {
      await Permission.notification.request();
    } catch (_) {}
    // Register all of them once. Creating a channel that already exists is a
    // no-op, so this is safe on every launch and means switching tone takes
    // effect immediately instead of on next install.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final tone in NotificationPrefs.sounds) {
      await android?.createNotificationChannel(_channelFor(tone));
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    // Cold start FROM a tap (app was fully killed): onDidReceiveNotification-
    // Response above can miss this launch, since it only starts listening
    // once initialize() has already returned — this catches it separately.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _open(launch!.notificationResponse?.payload);
    }
  }

  static const _replyActionId = 'reply';

  /// Notification tapped, or one of its actions used.
  ///
  /// Split from [_open] because a quick reply must NOT navigate — the user is
  /// still in whatever app they were in, and pulling them into the chat would
  /// defeat the point of replying from the shade.
  static void _onResponse(NotificationResponse resp) {
    final text = resp.input?.trim();
    if (resp.actionId == _replyActionId && text != null && text.isNotEmpty) {
      _sendQuickReply(resp.payload, text);
      return;
    }
    _open(resp.payload);
  }

  /// Sends a shade reply straight through the API.
  static Future<void> _sendQuickReply(String? payload, String text) async {
    if (payload == null) return;
    try {
      final n = jsonDecode(payload) as Map;
      final me = await Session.load();
      if (me == null) return;
      final groupId = n['group_id']?.toString();
      final chatId = n['chat_id']?.toString();
      if (groupId != null && groupId.isNotEmpty) {
        await ApiService.sendGroupMessage(groupId, text);
      } else if (chatId != null && chatId.isNotEmpty) {
        await ApiService.sendMessage(chatId, me['id'], text);
      }
    } catch (_) {}
  }

  /// Maps a `notifications.type` onto one of [NotificationPrefs.categories],
  /// so the user's per-category switches actually gate delivery. An unknown
  /// type maps to null and is always shown — silently swallowing a new
  /// notification type would be worse than showing one the user didn't ask for.
  static String? _categoryOf(String type) {
    switch (type) {
      case 'message':
        return 'messages';
      case 'group_message':
        return 'groups';
      case 'call':
        return 'calls';
      case 'new_story':
        return 'stories';
      case 'comment':
        return 'comments';
      case 'like':
        return 'likes';
      case 'follow':
        return 'followers';
      // Reactions, replies and mentions belong to whichever conversation they
      // happened in, so they honour the same switch the user set for it. A
      // separate "reactions" toggle would let someone mute messages and still
      // be pinged by every emoji.
      case 'reaction':
      case 'reply':
      case 'mention':
        return 'messages';
      case 'channel_post':
      case 'new_post':
        return 'news';
      case 'ai':
        return 'ai';
      case 'nearby':
        return 'nearby';
      default:
        return null;
    }
  }

  /// Shows a notification for a freshly-pushed `notifications` row (same
  /// shape the REST GET /api/notifications and the socket 'notification'
  /// event both use: type, message, from_username, post_id, ...), subject to
  /// the user's per-category and sound/vibration choices.
  static Future<void> showForNotification(Map n) async {
    final prefs = NotificationPrefs.value.value;
    if (!prefs.enabled) return;
    var cat = _categoryOf((n['type'] ?? '').toString());
    // The same event type can arrive from a 1:1 chat or a group, and the user
    // has separate switches for those — so the conversation decides, not the
    // event name.
    if (cat == 'messages' && (n['group_id'] ?? '').toString().isNotEmpty) {
      cat = 'groups';
    }
    if (cat != null && !prefs.allows(cat)) return;

    await init();
    final title = (n['from_username'] ?? 'Sigmacta').toString();
    // "Preview off" hides the text but still announces who it's from —
    // matching how Telegram/iOS treat a hidden preview.
    final body = prefs.preview
        ? (n['message'] ?? '').toString()
        : S.tr('notifHiddenBody');
    // A free account can't keep a Pro tone even if it was selected while
    // subscribed, so fall back rather than honouring a stale choice.
    final tone = NotificationPrefs.isFreeSound(prefs.tone) || ProState.isPro.value
        ? prefs.tone
        : 'classic';
    final channel = _channelFor(tone);
    // Reply straight from the shade, Telegram-style. Only for messages: there
    // is nothing to reply TO on a like or a follow.
    final isMessage = cat == 'messages' || cat == 'groups';
    final actions = isMessage
        ? <AndroidNotificationAction>[
            AndroidNotificationAction(
              _replyActionId,
              S.tr('notifReplyAction'),
              inputs: [
                AndroidNotificationActionInput(
                    label: S.tr('notifReplyHint')),
              ],
              // Stays in the background: sending a reply must not yank the
              // whole app to the foreground.
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ]
        : null;
    await _plugin.show(
      _nextId++,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: prefs.soundOn,
          sound: channel.sound,
          enableVibration: prefs.vibrate,
          enableLights: prefs.led,
          actions: actions,
        ),
      ),
      payload: jsonEncode({
        'type': n['type'],
        'from_user_id': n['from_user_id'],
        'post_id': n['post_id'],
        'notif_id': n['id'],
        // Needed by the quick-reply handler and by tap-to-open-conversation.
        'chat_id': n['chat_id'],
        'group_id': n['group_id'],
      }),
    );
  }

  // Same routing rule as NotificationsScreen._openNotif: a post reference
  // opens the post, otherwise (follow / new_story / anything without one)
  // falls back to the sender's profile. Public because the web foreground
  // banner (MainScreen — see [textFor]) needs the same navigation and has a
  // raw notification Map already, not the JSON-encoded native payload string.
  static Future<void> openFor(Map n) async {
    try {
      final notifId = n['notif_id'] ?? n['id'];
      if (notifId != null) ApiService.markNotificationRead(notifId.toString());

      final me = await Session.load();
      final ctx = DeepLinks.navKey.currentContext;
      if (me == null || ctx == null) return;

      final postId = n['post_id'];
      if (postId != null) {
        final post = await ApiService.getPost(postId.toString(), me['id'].toString());
        if (post != null) CommentsScreen.show(ctx, post: post, user: me);
        return;
      }
      final fromId = n['from_user_id'];
      if (fromId == null) return;
      DeepLinks.navKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: me,
          targetUserId: fromId,
          isOwnProfile: fromId.toString() == me['id'].toString(),
        ),
      ));
    } catch (_) {}
  }

  static Future<void> _open(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    try {
      await openFor(jsonDecode(payload) as Map);
    } catch (_) {}
  }

  /// Same "{u} liked your post" style copy NotificationsScreen renders for
  /// the activity feed — shared here so the web foreground banner can show
  /// identical text for like/follow/comment/etc., which never reach a system
  /// notification on web (flutter_local_notifications has no web build at all).
  static String textFor(Map n) {
    final u = (n['from_username'] ?? '').toString();
    String key;
    switch ((n['type'] ?? '').toString()) {
      case 'like': key = 'nLike'; break;
      case 'comment': key = 'nComment'; break;
      case 'follow': key = 'nFollow'; break;
      case 'repost': key = 'nRepost'; break;
      case 'channel_post': key = 'nChannelPost'; break;
      case 'new_post': key = 'nNewPost'; break;
      case 'new_story': key = 'nNewStory'; break;
      default: key = '';
    }
    if (key.isEmpty || u.isEmpty) return (n['message'] ?? '').toString();
    return S.tr(key).replaceAll('{u}', u);
  }
}
