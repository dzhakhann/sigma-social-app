import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// Plays a video podcast episode whose RSS enclosure is a direct video file
/// (mp4/m4v/webm). This is public podcast content — no YouTube ripping.
class VideoPodcastScreen extends StatefulWidget {
  final Map episode;
  const VideoPodcastScreen({Key? key, required this.episode}) : super(key: key);
  @override
  State<VideoPodcastScreen> createState() => _VideoPodcastScreenState();
}

class _VideoPodcastScreenState extends State<VideoPodcastScreen> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(
        Uri.parse(widget.episode['audio'].toString()))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _ready = true);
          _c.play();
        }
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text((widget.episode['title'] ?? context.t('videoFallback')).toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
      body: Center(
        child: _error
            ? Text(context.t('videoLoadError'),
                style: TextStyle(color: c.inkSoft))
            : !_ready
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _c.value.aspectRatio == 0
                            ? 16 / 9
                            : _c.value.aspectRatio,
                        child: VideoPlayer(_c),
                      ),
                      VideoProgressIndicator(_c,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                              playedColor: c.accent,
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white10)),
                      const SizedBox(height: 12),
                      IconButton(
                        iconSize: 56,
                        icon: Icon(
                            _c.value.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                            color: Colors.white),
                        onPressed: () => setState(() =>
                            _c.value.isPlaying ? _c.pause() : _c.play()),
                      ),
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}
