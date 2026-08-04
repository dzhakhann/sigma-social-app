import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/deep_links.dart';
import '../services/notification_prefs.dart';
import '../services/active_chat.dart';
import '../widgets/island_banner.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'home_screen.dart';
import 'podcasts_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'compose_screen.dart';
import 'goals_screen.dart';
import '../widgets/mini_player.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';

/// Threads-style bottom menu bar with 5 slots:
/// Главная · Рекомендации · Публикация(+) · Чат · Профиль.
/// The center (+) opens the composer as a pushed screen, not a tab.
class MainScreen extends StatefulWidget {
  final Map user;
  const MainScreen({super.key, required this.user});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;
  // Built lazily, one at a time, on first visit — not all four in initState.
  // Each tab's own initState fires real network calls (goals/weather/news/
  // stories for Home, the whole Rhythm catalog for Podcasts, chats+groups
  // for Chats, profile+posts+stories for Profile); building every tab at
  // launch meant all of that fired at once on a cold start, competing for
  // bandwidth and CPU before the user had even looked at three of them.
  // Cached once built so switching back still preserves scroll position and
  // doesn't refetch — same as before, just not paid for up front.
  final List<Widget?> _built = List.filled(4, null);
  StreamSubscription? _notifSub;

  Widget _tabScreen(int i) {
    return _built[i] ??= switch (i) {
      0 => HomeScreen(user: widget.user),
      1 => PodcastsScreen(user: widget.user),
      2 => ChatsScreen(user: widget.user),
      _ => ProfileScreen(user: widget.user, isOwnProfile: true),
    };
  }

  @override
  void initState() {
    super.initState();
    // App-wide: live push (over the socket, not polling) for activity on
    // people you follow — lives here rather than inside a tab so it keeps
    // firing no matter which tab is currently visible.
    NotificationService.init();
    SocketService().connect(widget.user['id'].toString());
    _notifSub = SocketService().onNotification.listen(_onNotification);
    // Same notifications, but able to reach a killed/backgrounded app too —
    // no-ops until a real Firebase project is wired in (see PushService).
    PushService.init();
    // A link that arrived while signed out was parked; replay it now that a
    // session exists AND the navigator is mounted. Post-frame because pushing a
    // route during initState has nothing to push onto yet.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => DeepLinks.consumePending());
  }

  /// Banner currently shown in-app, if any.
  Map? _banner;
  Timer? _bannerTimer;

  /// While the app is in the FOREGROUND a system notification is the wrong
  /// affordance — Android may not even show it, and it pulls focus out of the
  /// app. So a message shows the in-app island instead, and everything else
  /// (likes, follows) still goes through the system channel.
  static const _inChatTypes = {
    'message', 'group_message', 'reaction', 'reply', 'mention'
  };

  void _onNotification(Map data) {
    final type = (data['type'] ?? '').toString();
    // Everything that happens INSIDE a conversation gets the in-app island
    // rather than a system notification while the app is in the foreground.
    final isMessage = _inChatTypes.contains(type);
    if (!isMessage) {
      // flutter_local_notifications has no web build at all — a like/follow/
      // comment would otherwise just vanish silently while the tab is open,
      // since there's no OS notification tray to fall back to.
      if (kIsWeb) {
        _showBanner(data);
      } else {
        NotificationService.showForNotification(data);
      }
      return;
    }
    // Never announce a conversation the user is already looking at.
    if (ActiveChat.matches(data)) return;
    if (!NotificationPrefs.value.value
        .allows(type == 'group_message' ? 'groups' : 'messages')) {
      return;
    }
    _showBanner(data);
  }

  void _showBanner(Map data) {
    setState(() => _banner = data);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  /// Copy for the island banner — chat types show the message text itself;
  /// everything else (only ever reaches the banner on web) gets the same
  /// "{u} liked your post" style line the activity feed uses.
  String _bannerSubtitle() {
    final b = _banner;
    if (b == null) return '';
    if (_inChatTypes.contains((b['type'] ?? '').toString())) {
      return (b['message'] ?? '').toString();
    }
    return NotificationService.textFor(b);
  }

  void _onBannerAction() {
    final b = _banner;
    setState(() => _banner = null);
    if (b == null) return;
    if (_inChatTypes.contains((b['type'] ?? '').toString())) {
      // Jump to the Chat tab; opening the exact thread from here would need
      // the full chat row, which the notification payload doesn't carry.
      setState(() => _tab = 3);
      return;
    }
    // Like/follow/comment/etc: same post-or-profile routing a tapped system
    // notification uses natively.
    NotificationService.openFor(b);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  // Center "+" now asks what to create: a post (goes to your profile) or a goal.
  void _openCompose() {
    final c = context.k;
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) {
      return ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: c.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: c.accent),
        ),
        title: Text(title,
            style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: TextStyle(color: c.inkSoft, fontSize: 12)),
        onTap: onTap,
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          tile(Icons.edit_outlined, context.t('newPost'),
              context.t('newPostSub'), () async {
            Navigator.pop(context);
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ComposeScreen(user: widget.user)),
            );
            if (mounted) setState(() => _tab = 3); // go to profile
          }),
          tile(Icons.flag_outlined, context.t('newGoal'),
              context.t('newGoalSub'), () async {
            Navigator.pop(context);
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => GoalsScreen(user: widget.user)),
            );
            if (mounted) setState(() => _tab = 0); // go to home dashboard
          }),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(children: [
        IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < 4; i++)
              i == _tab || _built[i] != null
                  ? _tabScreen(i)
                  : const SizedBox.shrink(),
          ],
        ),
        IslandBanner(
          visible: _banner != null,
          accent: c.accent,
          leading: _banner?['from_avatar'] == null
              ? null
              : CircleAvatar(
                  radius: 23,
                  backgroundImage: CachedNetworkImageProvider(
                      _banner!['from_avatar'].toString()),
                ),
          title: (_banner?['from_username'] ?? '').toString(),
          subtitle: _bannerSubtitle(),
          actionLabel: context.t('openChat'),
          onAction: _onBannerAction,
          onDismiss: () => setState(() => _banner = null),
        ),
      ]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _BottomBar(
            current: _tab,
            onTab: (i) => setState(() => _tab = i),
            onCompose: _openCompose,
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int current; // maps to _screens index (0 home,1 explore,2 chat,3 profile)
  final ValueChanged<int> onTab;
  final VoidCallback onCompose;
  const _BottomBar(
      {required this.current, required this.onTab, required this.onCompose});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.ink.withOpacity(0.06))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _item(c, Icons.home_rounded, context.t('navHome'), current == 0,
                  () => onTab(0)),
              _item(c, Icons.podcasts_rounded, context.t('navPodcasts'),
                  current == 1, () => onTab(1)),
              _compose(c),
              _item(c, Icons.chat_bubble_rounded, context.t('navChat'),
                  current == 2, () => onTab(2)),
              _item(c, Icons.person_rounded, context.t('navProfile'),
                  current == 3, () => onTab(3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BrutalColors c, IconData icon, String label, bool active,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: active ? c.accent : c.inkSoft),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: active ? c.accent : c.inkSoft,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _compose(BrutalColors c) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCompose,
        child: Center(
          child: Container(
            width: 46,
            height: 34,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: c.accent.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
