import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'podcast_audio.dart';

/// ONE shared player for every music preview in the app: the story trimmer,
/// the editor preview, the story viewer, the profile favorite track and the
/// post music bar.
///
/// Why a singleton: `just_audio_background` is initialized app-wide (podcast
/// lock-screen controls) and behaves badly with several simultaneously loaded
/// players — whichever loads last steals the platform session and the others
/// go silent. That's exactly the "picked a track but hear nothing" bug. One
/// player for all previews (+ pausing the podcast player before starting)
/// removes the whole class of conflicts.
class MusicPreview {
  MusicPreview._();
  static final MusicPreview i = MusicPreview._();

  final AudioPlayer player = AudioPlayer();

  /// URL of whatever is currently loaded (drives play-icons in post bars).
  final ValueNotifier<String?> currentUrl = ValueNotifier(null);

  void _quietPodcasts() {
    try {
      PodcastAudio.instance.player.pause();
    } catch (_) {}
  }

  /// Plays [start]..[start]+[len] of the track, looped. Used by the trimmer,
  /// the editor preview and the story viewer.
  Future<void> playClip(
    String url, {
    String title = '',
    int startSec = 0,
    int lenSec = 15,
    double volume = 1.0,
  }) async {
    if (url.isEmpty) return;
    _quietPodcasts();
    try {
      currentUrl.value = url;
      await player.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.uri(
            url.startsWith('http') ? Uri.parse(url) : Uri.file(url),
            // just_audio_background rejects sources without a MediaItem tag.
            tag: MediaItem(id: 'preview_$url', title: title),
          ),
          start: Duration(seconds: startSec),
          end: Duration(seconds: startSec + lenSec),
        ),
      );
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(volume);
      await player.play();
    } catch (e) {
      // Clipping needs a source with a KNOWN duration; some streams don't
      // report one and the clip load throws. Fall back to the plain track
      // seeked to the fragment start — looping is lost, but sound is there.
      debugPrint('music preview clip failed, falling back: $e');
      try {
        await player.setAudioSource(AudioSource.uri(
          url.startsWith('http') ? Uri.parse(url) : Uri.file(url),
          tag: MediaItem(id: 'preview_$url', title: title),
        ));
        await player.setLoopMode(LoopMode.one);
        await player.setVolume(volume);
        await player.seek(Duration(seconds: startSec));
        await player.play();
      } catch (e2) {
        debugPrint('music preview fallback failed too: $e2');
        currentUrl.value = null;
        rethrow;
      }
    }
  }

  /// Plays the whole track from the top (favorite track, post bar).
  Future<void> playUrl(
    String url, {
    String title = '',
    String artist = '',
    bool loop = true,
  }) async {
    if (url.isEmpty) return;
    _quietPodcasts();
    try {
      currentUrl.value = url;
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(id: 'play_$url', title: title, artist: artist),
      ));
      await player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await player.setVolume(1.0);
      await player.play();
    } catch (e) {
      debugPrint('music preview url failed: $e');
      currentUrl.value = null;
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      await player.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await player.play();
    } catch (_) {}
  }

  /// Stops and clears — call when the owning screen/sheet goes away.
  Future<void> stop() async {
    currentUrl.value = null;
    try {
      await player.stop();
    } catch (_) {}
  }
}
