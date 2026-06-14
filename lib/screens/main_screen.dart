import 'dart:async';
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
  bool _navVisible = true;
  Timer? _hideTimer;
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
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  // Auto-hide the nav a few seconds after it appears, so content gets the
  // whole screen.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _navVisible = false);
    });
  }

  void _showNav() {
    _hideTimer?.cancel();
    if (!_navVisible) setState(() => _navVisible = true);
    _scheduleHide();
  }

  void _hideNav() {
    _hideTimer?.cancel();
    if (_navVisible) setState(() => _navVisible = false);
  }

  void _onTab(int i) {
    setState(() => _tab = i);
    _showNav();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final isRight = AppScope.of(context).config.navSide != 'left';

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Content uses the full screen; the nav floats over it on demand.
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification &&
                    (n.scrollDelta?.abs() ?? 0) > 1.5) {
                  _hideNav();
                }
                return false;
              },
              child: IndexedStack(index: _tab, children: _screens),
            ),
          ),

          // Either edge reveals the nav when touched (left OR right).
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _showNav(),
              onHorizontalDragStart: (_) => _showNav(),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _showNav(),
              onHorizontalDragStart: (_) => _showNav(),
            ),
          ),

          // The floating nav itself — slides off the edge when hidden.
          Positioned(
            top: 0,
            bottom: 0,
            left: isRight ? null : 8,
            right: isRight ? 8 : null,
            child: Center(
              child: IgnorePointer(
                ignoring: !_navVisible,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  offset: _navVisible
                      ? Offset.zero
                      : Offset(isRight ? 1.6 : -1.6, 0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _navVisible ? 1 : 0,
                    child: _SideNav(index: _tab, onTap: _onTab),
                  ),
                ),
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
                padding:
                    EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 8),
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
