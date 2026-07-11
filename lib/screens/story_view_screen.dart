import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

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
  final _replyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentStories = widget.stories;
    _currentGroupIndex = widget.groupIndex;
    _currentIndex = widget.startIndex;
    _startTimer();
  }

  final Set<String> _viewRecorded = {};

  void _recordView() {
    if (_currentStories.isEmpty) return;
    final story = _currentStories[_currentIndex];
    final id = story['id'].toString();
    if (story['user_id'] == widget.user['id']) return; // own — don't count
    if (_viewRecorded.contains(id)) return;
    _viewRecorded.add(id);
    ApiService.viewStoryStat(id); // fire-and-forget
  }

  void _startTimer() {
    _timer?.cancel();
    if (!mounted) return;
    _recordView();
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

  Future<void> _dmAuthor(Map story, String text,
      {bool withPreview = false}) async {
    if (text.trim().isEmpty) return;
    final authorId = story['user_id'].toString();
    final r = await ApiService.getOrCreateChat(
        widget.user['id'].toString(), authorId);
    if (r['success'] == true && r['data'] != null) {
      // Instagram-style: the DM carries a mini preview of the exact story,
      // so the author instantly sees WHICH story was liked / replied to.
      await ApiService.sendMessage(
        r['data']['id'].toString(),
        widget.user['id'].toString(),
        text,
        messageType: withPreview ? 'image' : 'text',
        mediaUrl: withPreview ? (story['image_url'] ?? '').toString() : null,
      );
    }
  }

  void _sendReply(Map story, String text) {
    if (text.trim().isEmpty) return;
    // Instant UI: clear + toast right away, deliver the DM in the background.
    _dmAuthor(story, '${context.t('storyReplyPrefix')}${text.trim()}',
        withPreview: true);
    ApiService.replyStoryStat(story['id'].toString());
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() => _isPaused = false);
    _startTimer();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('replySent'))));
  }

  // Liked story ids — instant UI feedback, the DM is sent in the background.
  final Set<String> _liked = {};

  void _likeStory(Map story) {
    final id = story['id'].toString();
    if (_liked.contains(id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _liked.add(id)); // heart fills instantly
    // Fire-and-forget: don't block the UI on the network.
    _dmAuthor(story, context.t('storyLiked'), withPreview: true);
    // Count the like in the story stats too.
    ApiService.likeStoryStat(story['id'].toString());
  }

  void _shareStory(Map story) {
    _timer?.cancel();
    setState(() => _isPaused = true);
    final url = (story['image_url'] ?? '').toString();
    Share.share('${context.t('shareStoryText')}\n$url').whenComplete(() {
      if (mounted) {
        setState(() => _isPaused = false);
        _startTimer();
      }
    });
  }

  // Instagram-style stats sheet for the story author: views, likes, replies
  // and the full viewer list with ❤ / 💬 marks.
  Future<void> _showStats(Map story) async {
    final c = context.k;
    _timer?.cancel();
    setState(() => _isPaused = true);
    final stats = await ApiService.storyStats(story['id'].toString());
    if (!mounted) return;
    final viewers = (stats['viewers'] as List?) ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: c.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCol(c, Icons.visibility_rounded,
                      '${stats['views'] ?? 0}', context.t('viewsLbl')),
                  _statCol(c, Icons.favorite_rounded,
                      '${stats['likes'] ?? 0}', context.t('likesLbl')),
                  _statCol(c, Icons.chat_bubble_rounded,
                      '${stats['replies'] ?? 0}', context.t('repliesStat')),
                ],
              ),
            ),
            Divider(height: 20, color: c.ink.withOpacity(0.07)),
            if (viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(context.t('noViewersYet'),
                    style: TextStyle(color: c.inkSoft)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (_, i) {
                    final v = viewers[i] as Map;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: c.surface2,
                        backgroundImage: v['avatar_url'] != null
                            ? CachedNetworkImageProvider(
                                v['avatar_url'].toString())
                            : null,
                        child: v['avatar_url'] == null
                            ? Icon(Icons.person,
                                size: 18, color: c.inkSoft)
                            : null,
                      ),
                      title: Text('@${v['username'] ?? ''}',
                          style: TextStyle(
                              color: c.ink, fontWeight: FontWeight.w600)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (v['liked'] == true)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.favorite,
                                color: Colors.redAccent, size: 18),
                          ),
                        if (v['replied'] == true)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.chat_bubble,
                                color: c.accent, size: 16),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ).whenComplete(() {
      if (mounted && !_isClosing) {
        setState(() => _isPaused = false);
        _startTimer();
      }
    });
  }

  Widget _statCol(BrutalColors c, IconData icon, String n, String label) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: c.accent, size: 22),
        const SizedBox(height: 4),
        Text(n,
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        Text(label, style: TextStyle(color: c.inkSoft, fontSize: 12)),
      ]);

  // Instagram-style "⋯" menu: share / copy link / report / delete (own).
  void _showOptions(Map story, bool isOwn) {
    final c = context.k;
    _timer?.cancel();
    setState(() => _isPaused = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.share_rounded, color: c.ink),
            title: Text(context.t('shareBtn')),
            onTap: () {
              Navigator.pop(context);
              _shareStory(story);
            },
          ),
          ListTile(
            leading: Icon(Icons.link_rounded, color: c.ink),
            title: Text(context.t('copyLink')),
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: (story['image_url'] ?? '').toString()));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t('linkCopied'))));
            },
          ),
          if (!isOwn)
            ListTile(
              leading: Icon(Icons.flag_outlined, color: c.danger),
              title: Text(context.t('reportBtn'),
                  style: TextStyle(color: c.danger)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t('reportSent'))));
              },
            ),
          if (isOwn)
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text(context.t('deleteBtn'),
                  style: TextStyle(color: c.danger)),
              onTap: () {
                Navigator.pop(context);
                _deleteStory(story['id']);
              },
            ),
          ListTile(
            leading: Icon(Icons.close_rounded, color: c.inkSoft),
            title: Text(context.t('cancelBtn')),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    ).whenComplete(() {
      if (mounted && !_isClosing) {
        setState(() => _isPaused = false);
        _startTimer();
      }
    });
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
                    GestureDetector(
                      onTap: () => _showOptions(story, isOwn),
                      child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.more_vert_rounded,
                              color: Colors.white, size: 24)),
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
          // Own story: Instagram-style viewers chip (bottom-left).
          if (isOwn)
            Positioned(
              left: 12, bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _showStats(story),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.visibility_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(context.t('viewersTitle'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (!isOwn)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _replyCtrl,
                        style: const TextStyle(color: Colors.white),
                        onTap: () {
                          _timer?.cancel();
                          setState(() => _isPaused = true);
                        },
                        onSubmitted: (t) => _sendReply(story, t),
                        decoration: InputDecoration(
                          filled: false,
                          isDense: true,
                          hintText: context.t('replyHint'),
                          hintStyle: const TextStyle(color: Colors.white54),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide:
                                  const BorderSide(color: Colors.white54)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(color: Colors.white)),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _likeStory(story),
                      icon: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.elasticOut,
                        scale: _liked.contains(story['id'].toString()) ? 1.2 : 1,
                        child: Icon(
                          _liked.contains(story['id'].toString())
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _liked.contains(story['id'].toString())
                              ? Colors.redAccent
                              : Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    IconButton(
                      // With text → send a reply; empty → open the share menu.
                      onPressed: () => _replyCtrl.text.trim().isEmpty
                          ? _shareStory(story)
                          : _sendReply(story, _replyCtrl.text),
                      icon: const Icon(Icons.send, color: Colors.white, size: 24),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _replyCtrl.dispose();
    super.dispose();
  }
}
