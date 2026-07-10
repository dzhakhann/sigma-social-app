import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'home_screen.dart';
import 'podcasts_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'compose_screen.dart';
import 'goals_screen.dart';
import '../widgets/mini_player.dart';

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
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(user: widget.user),
      PodcastsScreen(user: widget.user),
      ChatsScreen(user: widget.user),
      ProfileScreen(user: widget.user, isOwnProfile: true),
    ];
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
      body: IndexedStack(index: _tab, children: _screens),
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
