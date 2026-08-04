import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../constants.dart';

/// WebView player: loads OUR hosted embed page (real https origin). YouTube
/// requires a valid Referer for embeds ("Error 153"), so the page must come
/// from a real server — the backend serves /yt (public/yt-embed.html), which
/// hosts the official YouTube iframe player. State events arrive through the
/// SigmaYT JavaScript channel: ready / playing / ended / error:N / timeout.
///
/// Shared by the Газета feed (looping inline preview) and any fullscreen
/// player (Обзор, etc.) — don't duplicate this, extend it.
class YtWebPlayer extends StatefulWidget {
  final String videoId;
  final bool muted;
  final bool controls;
  final bool loop;
  final void Function(String event)? onEvent;
  const YtWebPlayer({
    super.key,
    required this.videoId,
    this.muted = false,
    this.controls = true,
    this.loop = false,
    this.onEvent,
  });

  @override
  State<YtWebPlayer> createState() => YtWebPlayerState();
}

class YtWebPlayerState extends State<YtWebPlayer> with WidgetsBindingObserver {
  late final WebViewController _c;
  bool _visible = true;
  bool _playing = true;

  static final String _base = kApiUrl.replaceFirst('/api', '');

  String get _url => '$_base/yt?v=${widget.videoId}'
      '&mute=${widget.muted ? 1 : 0}'
      '&controls=${widget.controls ? 1 : 0}'
      '&loop=${widget.loop ? 1 : 0}';

  /// Toggle sound live, without reloading the video.
  Future<void> setMuted(bool muted) async {
    try {
      await _c.runJavaScript(
          'window.sigmaSetMuted && sigmaSetMuted(${muted ? 'true' : 'false'})');
    } catch (_) {}
  }

  // Pause when scrolled off-screen / tab switched / app backgrounded; resume
  // from the same spot when visible again. Only for the inline preview (looping
  // clip); the fullscreen player passes controls and shouldn't auto-pause.
  bool _foreground = true;

  void _apply() {
    if (!widget.loop) return; // fullscreen player opts out of auto-pause
    final shouldPlay = _visible && _foreground;
    if (shouldPlay == _playing) return;
    _playing = shouldPlay;
    _c.runJavaScript(shouldPlay ? 'window.sigmaPlay&&sigmaPlay()' : 'window.sigmaPause&&sigmaPause()');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    _c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('SigmaYT', onMessageReceived: (m) => widget.onEvent?.call(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // Keep the main frame on our player page (block taps on YouTube logo
        // etc. from hijacking the WebView).
        onNavigationRequest: (r) => r.url.startsWith('$_base/yt') || r.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..loadRequest(Uri.parse(_url));
    final platform = _c.platform;
    if (platform is AndroidWebViewController) {
      // Allow autoplay (with sound in fullscreen) without a tap inside the view.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  @override
  void didUpdateWidget(covariant YtWebPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same widget instance survives across cards (stable GlobalKey) — load the
    // new clip when the video changes. Mute changes go through setMuted().
    if (oldWidget.videoId != widget.videoId) {
      _playing = true; // fresh page autoplays
      _c.loadRequest(Uri.parse(_url));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = WebViewWidget(controller: _c);
    if (!widget.loop) return view; // fullscreen: no auto-pause
    return VisibilityDetector(
      key: const Key('gazette_inline_video'),
      onVisibilityChanged: (info) {
        final vis = info.visibleFraction > 0.55;
        if (vis == _visible) return;
        _visible = vis;
        _apply();
      },
      child: view,
    );
  }
}

/// Fullscreen YouTube player (official, ToS-compliant, reliable). Opened on
/// tap. Autoplays with sound (a user gesture opened it, so the WebView
/// autoplay policy is satisfied). YouTube's own controls handle play/pause —
/// we never overlay a tap-catcher across the player, so those controls stay
/// live. ✕ = close, ↗ = open in the YouTube app. If the clip refuses to embed
/// we show a graceful "Watch on YouTube" fallback instead of a dead black screen.
class YtFullscreenVideo extends StatefulWidget {
  final String videoId;
  final String title;
  final String link;
  const YtFullscreenVideo({super.key, required this.videoId, required this.title, required this.link});

  @override
  State<YtFullscreenVideo> createState() => _YtFullscreenVideoState();
}

class _YtFullscreenVideoState extends State<YtFullscreenVideo> {
  bool _ready = false;
  bool _failed = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // Safety net: if the player never reports anything (network, blocked clip),
    // fall back to "Watch on YouTube" instead of spinning forever. The hosted
    // page also sends its own 'timeout' event after 8s.
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted && !_ready && !_failed) setState(() => _failed = true);
    });
  }

  void _onPlayerEvent(String e) {
    if (!mounted) return;
    if (e == 'ready' || e == 'playing') {
      _timeout?.cancel();
      if (!_ready) setState(() => _ready = true);
    } else if (e.startsWith('error') || e == 'timeout') {
      _timeout?.cancel();
      if (!_failed) setState(() => _failed = true);
    }
  }

  Future<void> _openInYouTube() async {
    final url = widget.link.isNotEmpty ? widget.link : 'https://www.youtube.com/watch?v=${widget.videoId}';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: _failed
              ? Center(child: _fallback())
              : YtWebPlayer(
                  key: ValueKey('fs_${widget.videoId}'),
                  videoId: widget.videoId,
                  muted: false,
                  controls: true,
                  loop: false,
                  onEvent: _onPlayerEvent,
                ),
        ),
        if (!_ready && !_failed)
          const Positioned.fill(child: Center(child: CircularProgressIndicator(color: Colors.white))),
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          left: 6,
          right: 6,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'YouTube',
              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 24),
              onPressed: _openInYouTube,
            ),
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 66,
          child: IgnorePointer(
            child: Text(widget.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
          ),
        ),
      ]),
    );
  }

  Widget _fallback() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_display_outlined, color: Colors.white54, size: 56),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(widget.title,
                textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: _openInYouTube,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Watch on YouTube'),
          ),
        ],
      );

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }
}
