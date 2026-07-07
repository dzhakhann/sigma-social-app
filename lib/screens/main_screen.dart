import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'compose_screen.dart';

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
      SearchScreen(user: widget.user),
      ChatsScreen(user: widget.user),
      ProfileScreen(user: widget.user, isOwnProfile: true),
    ];
  }

  Future<void> _openCompose() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComposeScreen(user: widget.user)),
    );
    // Jump to Home so the new post is visible after composing.
    if (mounted) setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: _BottomBar(
        current: _tab,
        onTab: (i) => setState(() => _tab = i),
        onCompose: _openCompose,
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
              _item(c, Icons.home_rounded, 'Главная', current == 0,
                  () => onTab(0)),
              _item(c, Icons.explore_rounded, 'Рекоменд.', current == 1,
                  () => onTab(1)),
              _compose(c),
              _item(c, Icons.chat_bubble_rounded, 'Чат', current == 2,
                  () => onTab(2)),
              _item(c, Icons.person_rounded, 'Профиль', current == 3,
                  () => onTab(3)),
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
