import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

import 'podcast_audio.dart';

/// ONE shared player for every music preview in the app: the story trimmer,
/// the editor preview, the story viewer, the profile favorite track and the
/// post music bar.
///
/// Built on `audioplayers` (NOT just_audio) very deliberately:
///  · just_audio here is wrapped by just_audio_background (podcast lock-screen
///    controls), so every just_audio preview spawned a SYSTEM MEDIA
///    NOTIFICATION with seek bar and fought the podcast player for the one
///    media session — sounds died randomly and the phone showed a player UI
///    for what should be a silent inline preview;
///  · ClippingAudioSource needs a known stream duration and kept failing into
///    a play-the-whole-track fallback. Here the fragment window is enforced
///    manually (position listener → seek back to start), which works for any
///    URL or local file.
class MusicPreview {
  MusicPreview._() {
    player.onPlayerStateChanged.listen((s) {
      isPlaying.value = s == ap.PlayerState.playing;
    });
    _posSub = player.onPositionChanged.listen((pos) {
      // Manual fragment loop: reaching the window end rewinds to its start.
      if (_clipLen > 0 &&
          pos.inMilliseconds >= (_clipStart + _clipLen) * 1000) {
        player.seek(Duration(seconds: _clipStart));
      }
    });
  }
  static final MusicPreview i = MusicPreview._();

  final ap.AudioPlayer player = ap.AudioPlayer();
  StreamSubscription? _posSub; // ignore: unused_field

  /// URL of whatever is currently loaded (drives play-icons in post bars).
  final ValueNotifier<String?> currentUrl = ValueNotifier(null);

  /// Live playing state (audioplayers has no sync `playing` getter).
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  // Loaded fragment: len <= 0 means "full track".
  int _clipStart = 0;
  int _clipLen = -1;

  void _quietPodcasts() {
    try {
      PodcastAudio.instance.player.pause();
    } catch (_) {}
  }

  ap.Source _source(String url) =>
      url.startsWith('http') ? ap.UrlSource(url) : ap.DeviceFileSource(url);

  /// Plays [startSec]..[startSec]+[lenSec] of the track, looped.
  Future<void> playClip(
    String url, {
    String title = '',
    int startSec = 0,
    int lenSec = 15,
    double volume = 1.0,
  }) async {
    if (url.isEmpty) return;
    // Same fragment already playing → don't re-prepare the stream (that costs
    // seconds on mobile data and is what made starts feel slow).
    if (currentUrl.value == url &&
        isPlaying.value &&
        _clipStart == startSec &&
        _clipLen == lenSec) {
      await player.setVolume(volume);
      return;
    }
    _quietPodcasts();
    try {
      currentUrl.value = url;
      _clipStart = startSec;
      _clipLen = lenSec;
      await player.stop();
      await player.setReleaseMode(ap.ReleaseMode.loop);
      await player.play(
        _source(url),
        volume: volume,
        position: Duration(seconds: startSec),
      );
    } catch (e) {
      debugPrint('music preview clip failed: $e');
      currentUrl.value = null;
      rethrow;
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
    if (currentUrl.value == url && _clipLen <= 0 && isPlaying.value) return;
    _quietPodcasts();
    try {
      currentUrl.value = url;
      _clipStart = 0;
      _clipLen = -1;
      await player.stop();
      await player
          .setReleaseMode(loop ? ap.ReleaseMode.loop : ap.ReleaseMode.stop);
      await player.play(_source(url), volume: 1.0);
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
      await player.resume();
    } catch (_) {}
  }

  /// Play/pause flip for player-style UIs.
  Future<void> toggle() async {
    if (isPlaying.value) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Stops and clears — call when the owning screen/sheet goes away.
  Future<void> stop() async {
    currentUrl.value = null;
    _clipStart = 0;
    _clipLen = -1;
    try {
      await player.stop();
    } catch (_) {}
  }
}
