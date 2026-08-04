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
    // Default Android audio focus is exclusive (AUDIOFOCUS_GAIN) — starting
    // this preview was silently pausing whatever video was playing behind it
    // (story editor video + music sticker: picture froze, only the track
    // played) because the video player lost focus and auto-paused. This
    // preview never needs exclusive focus — it's meant to layer under video.
    player.setAudioContext(ap.AudioContext(
      android:
          const ap.AudioContextAndroid(audioFocus: ap.AndroidAudioFocus.none),
    ));
    player.onPlayerStateChanged.listen((s) {
      isPlaying.value = s == ap.PlayerState.playing;
    });
    _posSub = player.onPositionChanged.listen((pos) {
      if (_clipLen <= 0) return;
      final startMs = _clipStart * 1000;
      final endMs = (_clipStart + _clipLen) * 1000;
      // Manual fragment loop. Two cases:
      //  • reached the window end   → rewind to the window start;
      //  • playing BEFORE the window → the initial seek was dropped by a
      //    not-yet-buffered stream, so snap forward. This is what fixes the
      //    "whole track plays once, then loops" bug on the trimmed clip.
      if (pos.inMilliseconds >= endMs || pos.inMilliseconds < startMs - 400) {
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
    // Same URL already loading/playing (e.g. the music picker's tap-to-preview
    // just called playUrl on it, or the trim sheet is being dragged) but with
    // a different window — just retarget the loop, don't stop()+setSource()
    // again. That full reload re-buffers the stream from zero and is what
    // made picking a track feel slow (it was happening on EVERY trim drag).
    if (currentUrl.value == url) {
      _clipStart = startSec;
      _clipLen = lenSec;
      await player.setVolume(volume);
      try {
        await player.seek(Duration(seconds: startSec));
      } catch (_) {}
      if (!isPlaying.value) await player.resume();
      return;
    }
    _quietPodcasts();
    try {
      currentUrl.value = url;
      _clipStart = startSec;
      _clipLen = lenSec;
      await player.stop();
      await player.setReleaseMode(ap.ReleaseMode.loop);
      await player.setVolume(volume);
      // Prepare the stream FIRST, then seek, then play. Passing `position:`
      // straight to play() seeks before the stream is ready and silently
      // failed on some tracks (the "no sound in trim" bug). The position
      // listener also self-corrects if this seek is dropped.
      await player.setSource(_source(url));
      if (startSec > 0) {
        try {
          await player.seek(Duration(seconds: startSec));
        } catch (_) {}
      }
      await player.resume();
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
