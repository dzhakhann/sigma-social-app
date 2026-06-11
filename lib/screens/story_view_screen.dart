import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

class StoryViewScreen extends StatefulWidget {
  final List stories;
  final List allGroups;
  final int groupIndex;
  final int startIndex;
  final Map user;
  final VoidCallback? onStoryDeleted;

  const StoryViewScreen({
    Key? key,
    required this.stories,
    required this.allGroups,
    required this.groupIndex,
    required this.startIndex,
    required this.user,
    this.onStoryDeleted,
  }) : super(key: key);

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen> {
  late List _currentStories;
  late int _currentGroupIndex;
  late int _currentIndex;
  double _progress = 0;
  Timer? _timer;
  bool _isPaused = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _currentStories = widget.stories;
    _currentGroupIndex = widget.groupIndex;
    _currentIndex = widget.startIndex;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _progress = 0);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _isPaused) return;
      setState(() => _progress += 0.01);
      if (_progress >= 1.0) {
        timer.cancel();
        _nextStory();
      }
    });
  }

  void _nextStory() {
    if (!mounted || _isClosing) return;
    if (_currentIndex < _currentStories.length - 1) {
      setState(() => _currentIndex++);
      _startTimer();
    } else if (_currentGroupIndex < widget.allGroups.length - 1) {
      setState(() {
        _currentGroupIndex++;
        _currentStories = widget.allGroups[_currentGroupIndex];
        _currentIndex = 0;
      });
      _startTimer();
    } else {
      _closeScreen();
    }
  }

  void _prevStory() {
    if (!mounted || _isClosing) return;
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startTimer();
    } else if (_currentGroupIndex > 0) {
      setState(() {
        _currentGroupIndex--;
        _currentStories = widget.allGroups[_currentGroupIndex];
        _currentIndex = _currentStories.length - 1;
      });
      _startTimer();
    }
  }

  void _closeScreen() {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _deleteStory(String storyId) async {
    _timer?.cancel();
    try {
      await ApiService.deleteStory(storyId);
      widget.onStoryDeleted?.call();
      _closeScreen();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;

    if (_currentStories.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeScreen());
      return const Scaffold(backgroundColor: Colors.black);
    }

    final story = _currentStories[_currentIndex];
    final isOwn = story['user_id'] == widget.user['id'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) {
          _timer?.cancel();
          setState(() => _isPaused = true);
        },
        onLongPressEnd: (_) {
          setState(() => _isPaused = false);
          _startTimer();
        },
        child: Stack(children: [
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: story['image_url'],
              fit: BoxFit.cover,
              key: ValueKey(story['id']),
              placeholder: (_, __) => Center(
                  child: CircularProgressIndicator(color: c.accent)),
              errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image,
                      color: Colors.white, size: 60)),
            ),
          ),
          Positioned.fill(
            child: Row(children: [
              Expanded(
                  flex: 1,
                  child: GestureDetector(
                      onTap: _prevStory,
                      child: Container(color: Colors.transparent))),
              Expanded(
                  flex: 2,
                  child: GestureDetector(
                      onTap: _nextStory,
                      child: Container(color: Colors.transparent))),
            ]),
          ),
          Positioned(
            top: 0, left: 0, right: 0, height: 120,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                      children: List.generate(_currentStories.length, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: i < _currentIndex
                                ? 1.0
                                : i == _currentIndex
                                    ? _progress
                                    : 0.0,
                            backgroundColor: Colors.white30,
                            valueColor:
                                const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                    );
                  })),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    story['user_avatar'] != null
                        ? CircleAvatar(
                            radius: 18,
                            backgroundImage: CachedNetworkImageProvider(
                                story['user_avatar']))
                        : CircleAvatar(
                            radius: 18,
                            backgroundColor: c.accent,
                            child: Icon(Icons.person,
                                color: Colors.black, size: 16)),
                    const SizedBox(width: 8),
                    Text(story['username'] ?? 'User',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const Spacer(),
                    if (isOwn)
                      GestureDetector(
                        onTap: () {
                          _timer?.cancel();
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: c.surface,
                              title: const Text('Delete story?'),
                              actions: [
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _startTimer();
                                    },
                                    child: Text('Cancel',
                                        style: TextStyle(color: c.inkSoft))),
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _deleteStory(story['id']);
                                    },
                                    child: Text('Delete',
                                        style: TextStyle(color: c.danger))),
                              ],
                            ),
                          );
                        },
                        child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.delete_outline,
                                color: Colors.white, size: 22)),
                      ),
                    GestureDetector(
                      onTap: _closeScreen,
                      child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close,
                              color: Colors.white, size: 22)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
