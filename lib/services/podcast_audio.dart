import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'podcast_store.dart';
import '../theme/brutal_theme.dart' show appConfig;

/// A single app-wide audio player for podcasts. Because it lives above the
/// navigation, playback keeps going when you collapse the player (Spotify-style
/// mini-bar) and continues in the background / on the lock screen.
class PodcastAudio {
  PodcastAudio._() {
    // Auto-advance to the next episode in the queue when one finishes.
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next();
    });
  }
  static final PodcastAudio instance = PodcastAudio._();

  final AudioPlayer player = AudioPlayer();

  /// The currently loaded episode (null = nothing playing → hide mini-player).
  final ValueNotifier<Map?> current = ValueNotifier<Map?>(null);

  List<Map> _queue = [];
  int _index = 0;

  bool get hasNext => _index < _queue.length - 1;
  bool get hasPrev => _index > 0;

  /// True if this episode is a video (played in a separate video screen).
  static bool isVideo(Map ep) {
    final u = (ep['audio'] ?? '').toString().toLowerCase().split('?').first;
    return u.endsWith('.mp4') ||
        u.endsWith('.m4v') ||
        u.endsWith('.mov') ||
        u.endsWith('.webm');
  }

  Future<void> playList(List<Map> eps, int index) async {
    _queue = List<Map>.from(eps);
    _index = index.clamp(0, eps.length - 1);
    await _load();
  }

  Future<void> _load() async {
    final ep = _queue[_index];
    current.value = ep;
    await PodcastStore.addHistory(ep);
    final art = (ep['artwork'] ?? '').toString();
    try {
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(ep['audio'].toString()),
        tag: MediaItem(
          id: ep['audio'].toString(),
          title: (ep['title'] ??
                  (appConfig.value.lang == 'ru' ? 'Эпизод' : 'Episode'))
              .toString(),
          album: (ep['showTitle'] ??
                  (appConfig.value.lang == 'ru' ? 'Подкаст' : 'Podcast'))
              .toString(),
          artUri: art.isNotEmpty ? Uri.tryParse(art) : null,
        ),
      ));
      player.play();
    } catch (_) {}
  }

  Future<void> next() async {
    if (hasNext) {
      _index++;
      await _load();
    }
  }

  Future<void> prev() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else if (hasPrev) {
      _index--;
      await _load();
    }
  }

  void toggle() => player.playing ? player.pause() : player.play();

  Future<void> stop() async {
    await player.stop();
    current.value = null;
  }
}
