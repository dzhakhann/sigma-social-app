import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../widgets/brutal.dart';
import '../services/socket_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'chats_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

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
    SocketService().connect(widget.user['id'].toString());
    _screens = [
      HomeScreen(user: widget.user),
      SearchScreen(user: widget.user),
      ChatsScreen(user: widget.user),
      NotificationsScreen(user: widget.user),
      ProfileScreen(user: widget.user, isOwnProfile: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            // keep every screen clear of the floating right-side nav
            child: Padding(
              padding: const EdgeInsets.only(right: 58),
              child: IndexedStack(index: _tab, children: _screens),
            ),
          ),
          // Floating glass nav pinned to the right edge for one-handed reach.
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _SideNav(
                index: _tab,
                onTap: (i) => setState(() => _tab = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  const _NavItem(this.icon);
}

class _SideNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _SideNav({required this.index, required this.onTap});

  static const _items = <_NavItem>[
    _NavItem(Icons.home_rounded),
    _NavItem(Icons.explore_rounded),
    _NavItem(Icons.chat_bubble_rounded),
    _NavItem(Icons.notifications_rounded),
    _NavItem(Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GlassPanel(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _items.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 8),
                child: _NavButton(
                  icon: _items[i].icon,
                  active: i == index,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NavButton(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: c.accent.withOpacity(0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 23,
          color: active ? c.onAccent : c.inkSoft,
        ),
      ),
    );
  }
}
