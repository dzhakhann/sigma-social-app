import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'podcast_store.dart';
import '../theme/brutal_theme.dart' show appConfig;

/// A single app-wide audio player. The whole queue is loaded as one playlist,
/// so the Android media notification / lock screen gets the full modern
/// controls: ⏮ previous, ⏯ play-pause, ⏭ next and a seek bar with artwork —
/// like Spotify/Telegram, instead of the bare stop+pause pair.
class PodcastAudio {
  PodcastAudio._() {
    // Keep `current` in sync with the playlist index (notification skips too).
    player.currentIndexStream.listen((i) {
      if (i == null || i < 0 || i >= _queue.length) return;
      _index = i;
      final ep = _queue[i];
      if (current.value != ep) {
        current.value = ep;
        PodcastStore.addHistory(ep);
      }
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

  MediaItem _mediaItem(Map ep, int i) {
    final art = (ep['artwork'] ?? '').toString();
    return MediaItem(
      id: '${ep['audio']}#$i',
      title: (ep['title'] ??
              (appConfig.value.lang == 'ru' ? 'Эпизод' : 'Episode'))
          .toString(),
      album: (ep['showTitle'] ??
              (appConfig.value.lang == 'ru' ? 'Подкаст' : 'Podcast'))
          .toString(),
      artist: (ep['showTitle'] ?? 'Sigmacta').toString(),
      artUri: art.isNotEmpty ? Uri.tryParse(art) : null,
    );
  }

  Future<void> playList(List<Map> eps, int index) async {
    // Only audio items can go into the audio playlist.
    final audioEps = eps.where((e) => !isVideo(e)).toList();
    if (audioEps.isEmpty) return;
    var startIdx = audioEps.indexOf(eps[index.clamp(0, eps.length - 1)]);
    if (startIdx < 0) startIdx = 0;
    _queue = audioEps;
    _index = startIdx;
    current.value = _queue[_index];
    await PodcastStore.addHistory(_queue[_index]);
    try {
      final playlist = ConcatenatingAudioSource(
        children: [
          for (int i = 0; i < _queue.length; i++)
            AudioSource.uri(
              Uri.parse(_queue[i]['audio'].toString()),
              tag: _mediaItem(_queue[i], i),
            ),
        ],
      );
      await player.setAudioSource(playlist, initialIndex: _index);
      player.play();
    } catch (_) {}
  }

  Future<void> next() async {
    if (hasNext) await player.seekToNext();
  }

  Future<void> prev() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else if (hasPrev) {
      await player.seekToPrevious();
    }
  }

  void toggle() => player.playing ? player.pause() : player.play();

  Future<void> stop() async {
    await player.stop();
    current.value = null;
  }
}
