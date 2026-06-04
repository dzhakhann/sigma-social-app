import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/socket_service.dart';
import 'feed_screen.dart';
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
      FeedScreen(user: widget.user),
      SearchScreen(user: widget.user),
      ChatsScreen(user: widget.user),
      NotificationsScreen(user: widget.user),
      ProfileScreen(user: widget.user, isOwnProfile: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kSurface2, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded, size: 26),
              activeIcon: Icon(Icons.home_rounded, size: 26),
              label: 'Feed',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded, size: 26),
              activeIcon: Icon(Icons.search_rounded, size: 26),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 24),
              activeIcon: Icon(Icons.chat_bubble_rounded, size: 24),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined, size: 26),
              activeIcon: Icon(Icons.notifications_rounded, size: 26),
              label: 'Notifications',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 26),
              activeIcon: Icon(Icons.person_rounded, size: 26),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
