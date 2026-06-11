import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
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
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: _BrutalNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _BrutalNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BrutalNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final items = <_NavItem>[
      _NavItem(Icons.bolt_rounded, context.t('home')),
      _NavItem(Icons.travel_explore_rounded, context.t('discover')),
      _NavItem(Icons.forum_rounded, context.t('chats')),
      _NavItem(Icons.notifications_active_rounded, context.t('alerts')),
      _NavItem(Icons.face_rounded, context.t('me')),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.ink, width: 3)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    active: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;
  const _NavButton(
      {required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? c.ink : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: active
              ? [BoxShadow(color: c.shadow, offset: const Offset(3, 3), blurRadius: 0)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 22,
              color: active ? c.onAccent : c.inkSoft,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: active ? c.onAccent : c.inkSoft,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
