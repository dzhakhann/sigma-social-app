import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'sigma_gallery_screen.dart';

class ReelsScreen extends StatefulWidget {
  final Map user;
  const ReelsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  List _reels = [];
  bool _isLoading = false;
  int _currentIndex = 0;
  final PageController _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getReels(widget.user['id']);
    if (mounted) setState(() { _reels = data; _isLoading = false; });
  }

  Future<void> _upload() async {
    // Sigmacta's own gallery (videos only) instead of the system picker.
    final picked = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => const SigmaGalleryScreen(
            type: RequestType.video, allowCamera: false),
      ),
    );
    if (picked is! List<File> || picked.isEmpty) return;
    final file = picked.first;
    if (!mounted) return;

    final c = context.k;
    final captionCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dc = ctx.k;
        return AlertDialog(
          backgroundColor: dc.surface,
          title: Text(context.t('addCaption')),
          content: TextField(
              controller: captionCtrl,
              decoration: InputDecoration(hintText: context.t('addCaption') + '...')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.t('cancelBtn'), style: TextStyle(color: dc.inkSoft))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.t('upload'), style: TextStyle(color: dc.accent))),
          ],
        );
      },
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(context.t('uploadingReel'))));

    try {
      final bytes = await file.readAsBytes();
      final filename = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final uploadResult = await ApiService.uploadReelVideo(
          widget.user['id'], bytes, filename);
      if (uploadResult['success'] == true) {
        await ApiService.createReel(
            widget.user['id'], uploadResult['url'], captionCtrl.text);
        if (mounted) _load();
        messenger.showSnackBar(
            SnackBar(content: Text(context.t('reelUploaded'))));
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text('Error: ${uploadResult['error']}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        _isLoading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : _reels.isEmpty
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        const Icon(Icons.videocam_off,
                            size: 60, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(context.t('noReels'),
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                            onPressed: _upload,
                            icon: const Icon(Icons.add, color: Colors.black),
                            label: Text(context.t('uploadFirstReel'),
                                style: const TextStyle(color: Colors.black))),
                      ]))
                : PageView.builder(
                    controller: _pageCtrl,
                    scrollDirection: Axis.vertical,
                    itemCount: _reels.length,
                    onPageChanged: (i) =>
                        setState(() => _currentIndex = i),
                    itemBuilder: (_, i) => ReelItem(
                          reel: _reels[i],
                          isActive: i == _currentIndex,
                          currentUser: widget.user,
                          onLike: () async {
                            await ApiService.likeReel(
                                _reels[i]['id'], widget.user['id']);
                            _load();
                          },
                        ),
                  ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Text(context.t('reelsTitle'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: Colors.white, size: 30),
                  onPressed: _upload,
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }
}

class ReelItem extends StatefulWidget {
  final Map reel;
  final bool isActive;
  final Map currentUser;
  final VoidCallback onLike;

  const ReelItem({
    Key? key,
    required this.reel,
    required this.isActive,
    required this.currentUser,
    required this.onLike,
  }) : super(key: key);

  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = widget.reel['video_url'];
    if (url == null) return;
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    await _ctrl!.initialize();
    _ctrl!.setLooping(true);
    if (widget.isActive) _ctrl!.play();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void didUpdateWidget(ReelItem old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _ctrl?.play();
      } else {
        _ctrl?.pause();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final reel = widget.reel;
    final isLiked = reel['is_liked'] == true;

    return Stack(fit: StackFit.expand, children: [
      _initialized && _ctrl != null
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                  width: _ctrl!.value.size.width,
                  height: _ctrl!.value.size.height,
                  child: VideoPlayer(_ctrl!)))
          : Center(
              child: CircularProgressIndicator(color: c.accent)),
      GestureDetector(
        onTap: () {
          if (_ctrl?.value.isPlaying == true) {
            _ctrl?.pause();
          } else {
            _ctrl?.play();
          }
          setState(() {});
        },
        child: Container(color: Colors.transparent),
      ),
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent]),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text('@${reel['username'] ?? 'user'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if ((reel['caption'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(reel['caption'],
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                  ),
              ]),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: widget.onLike,
                child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? c.danger : Colors.white,
                    size: 32),
              ),
              Text('${reel['likes_count'] ?? 0}',
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Icon(
                  _ctrl?.value.isPlaying == true
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 28),
            ]),
          ]),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }
}
