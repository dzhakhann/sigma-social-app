import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/weather_service.dart';
import '../theme/brutal_theme.dart';
import 'gif_picker_screen.dart';
import 'story_audio_trim_sheet.dart';
import 'story_camera_screen.dart';
import 'story_music_picker_sheet.dart';

/// Instagram-style story editor:
///  · pinch-zoom / drag the photo (in AND out — black canvas around);
///  · draggable, scalable AND rotatable overlays: text, emoji, GIF/stickers,
///    and badges (time, weather, location, link, #tag, @mention);
///  · freehand drawing with a colour palette and undo;
///  · music from "Rhythm" or an audio file from the device;
///  · long-press an overlay to delete it.
/// Photo + overlays + drawing are flattened into ONE image, so it looks
/// identical for every viewer. Returns a [StoryCapture]: photo bytes, or — when
/// music was added — the path of a rendered MP4.
class StoryEditorScreen extends StatefulWidget {
  /// The photo being edited. Null for a video story — [videoPath] is set then
  /// and the clip plays underneath the overlays.
  final Uint8List? imageBytes;

  /// Set for video stories: overlays are burned into the clip on publish.
  final String? videoPath;

  const StoryEditorScreen({Key? key, this.imageBytes, this.videoPath})
      : assert(imageBytes != null || videoPath != null),
        super(key: key);

  bool get isVideo => videoPath != null;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

enum _ItemKind { text, emoji, badge, image, link, music }

/// One draggable overlay. Everything pans, pinch-scales and rotates.
/// [styleIdx] cycles the look of the rich widgets (music, link) on tap.
class _StoryItem {
  String text;
  int colorIdx;
  Offset pos; // relative 0..1
  double scale;
  double rotation; // radians
  final _ItemKind kind;

  /// GIF / sticker source.
  final String? imageUrl;

  /// Badge decoration (time, weather, location, #tag, @user).
  final IconData? badgeIcon;

  /// Music widget extras.
  final String? artist;
  final String? artwork;

  /// Link sticker: [text] is the visible label, this is where it goes.
  final String? linkUrl;

  /// Which visual variant to draw (music: 0-3, link: 0-2).
  int styleIdx;

  // ── Text styling (Instagram-style) ──
  int fontIdx; // index into _fonts
  bool italic;
  int textStyleIdx; // 0 plain · 1 outline · 2 filled background
  TextAlign align;

  _StoryItem({
    this.text = '',
    this.kind = _ItemKind.text,
    this.colorIdx = 0,
    this.pos = const Offset(0.5, 0.45),
    this.scale = 1.0,
    this.rotation = 0,
    this.imageUrl,
    this.badgeIcon,
    this.artist,
    this.artwork,
    this.linkUrl,
    this.styleIdx = 0,
    this.fontIdx = 0,
    this.italic = false,
    this.textStyleIdx = 0,
    this.align = TextAlign.center,
  });

  bool get isEmoji => kind == _ItemKind.emoji;
  bool get isImage => kind == _ItemKind.image;
  bool get isBadge => kind == _ItemKind.badge;
  bool get isRich => kind == _ItemKind.music || kind == _ItemKind.link;
}

class _Stroke {
  final List<Offset> points = [];
  final Color color;
  _Stroke(this.color);
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final _boundaryKey = GlobalKey();
  final _textCtrl = TextEditingController();

  double? _imgAspect;
  final List<_StoryItem> _items = [];
  final List<_Stroke> _strokes = [];
  int _colorIdx = 0;
  bool _editingText = false;
  bool _drawing = false;
  bool _publishing = false;
  _StoryItem? _editTarget; // overlay being re-edited
  double _baseScale = 1.0;
  double _baseRotation = 0;

  /// Music/audio laid over the photo. When set, publishing renders the picture
  /// + this track into a short MP4 (a still image can't carry sound), so it
  /// travels through the same video-story pipeline — no new storage or schema.
  String? _audioUrl;
  String? _audioTitle;
  int _audioSeconds = 15;

  /// Which second of the track the clip starts from.
  int _audioStartSec = 0;

  /// Full track length, when the source reports one (Rhythm does).
  int _audioTotalSec = 0;

  /// True for the split second we snapshot ONLY the overlay layer (video
  /// stories) — the clip itself is hidden so the PNG stays transparent.
  bool _captureOverlaysOnly = false;

  /// Link stickers are excluded from the flattened media — they're rendered as
  /// real, tappable buttons by the viewer instead of being baked into pixels.
  bool _hideLinksForCapture = false;

  static const _colors = [
    Colors.white, Colors.black, Color(0xFFFF5252), Color(0xFFFFD740),
    Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB),
  ];

  /// System font families — no extra assets, so the APK doesn't grow.
  static const _fonts = [
    (label: 'Classic', family: null),
    (label: 'Serif', family: 'serif'),
    (label: 'Mono', family: 'monospace'),
    (label: 'Casual', family: 'casual'),
    (label: 'Cursive', family: 'cursive'),
  ];

  // Style being composed in the text editor (applied on commit).
  int _fontIdx = 0;
  bool _italic = false;
  int _textStyleIdx = 0;
  TextAlign _align = TextAlign.center;

  static const _emojis = [
    '😀','😂','😍','🥳','😎','🔥','❤️','💯','👍','🙌','✨','⭐',
    '🎉','💪','🚀','🌈','☀️','🌙','🍕','⚽','🎵','😜','🥰','😇',
  ];

  /// Plays the clip behind the overlays for a video story.
  VideoPlayerController? _vid;

  /// Live music preview (Пункт 2): the chosen start..end fragment plays looped
  /// right in the editor — you hear the story before publishing it.
  final AudioPlayer _preview = AudioPlayer();

  Future<void> _startPreview() async {
    final url = _audioUrl;
    if (url == null || url.isEmpty) return;
    try {
      final start = Duration(seconds: _audioStartSec);
      final end = Duration(seconds: _audioStartSec + _audioSeconds);
      // setClip plays ONLY the fragment; LoopMode.one keeps it cycling.
      await _preview.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.uri(
              url.startsWith('http') ? Uri.parse(url) : Uri.file(url)),
          start: start,
          end: end,
        ),
      );
      await _preview.setLoopMode(LoopMode.one);
      // A video story has its own sound — keep the preview quiet-ish under it.
      await _preview.setVolume(widget.isVideo ? 0.6 : 1.0);
      await _preview.play();
    } catch (_) {}
  }

  Future<void> _stopPreview() async {
    try {
      await _preview.stop();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    } else {
      decodeImageFromList(widget.imageBytes!).then((img) {
        if (mounted) setState(() => _imgAspect = img.width / img.height);
        img.dispose();
      });
    }
  }

  Future<void> _initVideo() async {
    final v = VideoPlayerController.file(File(widget.videoPath!));
    try {
      await v.initialize();
      await v.setLooping(true);
      await v.play();
      if (mounted) {
        setState(() {
          _vid = v;
          _imgAspect = v.value.aspectRatio;
        });
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() {
      _publishing = true;
      _editingText = false;
      _drawing = false;
    });
    _stopPreview(); // no editor sound while rendering/publishing
    // Link stickers must stay TAPPABLE, so they're never flattened into the
    // media — they travel as data and the viewer draws a real button.
    setState(() => _hideLinksForCapture = true);
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      // ── Video story: burn overlays (and music) into the clip ────────────
      if (widget.isVideo) {
        final out = await _renderVideoWithOverlays();
        if (!mounted) return;
        // Fall back to the untouched clip rather than losing the story.
        Navigator.pop(context,
            StoryCapture.video(out ?? widget.videoPath!, links: _linkData()));
        return;
      }

      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      final bytes = data.buffer.asUint8List();

      // No music → a plain photo story.
      if (_audioUrl == null) {
        Navigator.pop(context, StoryCapture.photo(bytes, links: _linkData()));
        return;
      }

      // Music/audio added → burn the picture + track into a short MP4, so it
      // rides the existing video-story pipeline (a JPEG can't carry sound).
      final path = await _renderPhotoWithAudio(bytes);
      if (!mounted) return;
      if (path != null) {
        Navigator.pop(context, StoryCapture.video(path, links: _linkData()));
      } else {
        // Audio failed — still publish the picture rather than losing the work.
        Navigator.pop(context, StoryCapture.photo(bytes, links: _linkData()));
      }
      return;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _publishing = false;
        _hideLinksForCapture = false;
      });
    }
  }

  /// Link stickers serialised for the viewer (position is relative, so it lands
  /// in the same spot on any screen size).
  List<Map> _linkData() => [
        for (final it in _items)
          if (it.kind == _ItemKind.link && (it.linkUrl ?? '').isNotEmpty)
            {
              'label': it.text,
              'url': it.linkUrl,
              'x': it.pos.dx,
              'y': it.pos.dy,
              'scale': it.scale,
              'style': it.styleIdx,
            },
      ];

  /// Video story: draw the overlay layer (text, stickers, GIF frame, drawing)
  /// to a transparent PNG the size of the clip, composite it over every frame,
  /// and mix in the chosen track. Returns null if nothing had to change.
  Future<String?> _renderVideoWithOverlays() async {
    final hasOverlays = _items.isNotEmpty || _strokes.isNotEmpty;
    if (!hasOverlays && _audioUrl == null) return null; // untouched clip
    try {
      // Hide the video itself so only the overlays land on the PNG.
      setState(() => _captureOverlaysOnly = true);
      await Future.delayed(const Duration(milliseconds: 80));
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (mounted) setState(() => _captureOverlaysOnly = false);
      if (data == null) return null;

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ovl = '${dir.path}/ovl_$stamp.png';
      await File(ovl).writeAsBytes(data.buffer.asUint8List());
      final out = '${dir.path}/story_$stamp.mp4';

      final cmd = StringBuffer('-y -i "${widget.videoPath}" ');
      if (_audioUrl != null) cmd.write('-i "$_audioUrl" ');
      if (hasOverlays) {
        cmd.write('-i "$ovl" ');
        // Scale the overlay to the video, then composite it over each frame.
        final ovlIdx = _audioUrl != null ? 2 : 1;
        cmd.write('-filter_complex '
            '"[$ovlIdx:v]scale=iw:ih[o];[0:v][o]overlay=(W-w)/2:(H-h)/2" ');
      }
      if (_audioUrl != null) {
        // Chosen track replaces the original sound.
        cmd.write('-map ${hasOverlays ? '0:v' : '0:v'} -map 1:a -shortest ');
      }
      cmd.write('-c:v libx264 -preset veryfast -pix_fmt yuv420p '
          '-c:a aac -b:a 128k "$out"');

      final session = await FFmpegKit.execute(cmd.toString());
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      try { await File(ovl).delete(); } catch (_) {}
      return out;
    } catch (_) {
      if (mounted) setState(() => _captureOverlaysOnly = false);
      return null;
    }
  }

  /// still image + audio → MP4. `-shortest` stops at the audio/limit, and the
  /// output lives in the temp dir (the OS reclaims it) — no extra copies kept.
  Future<String?> _renderPhotoWithAudio(Uint8List png) async {
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final imgPath = '${dir.path}/story_$stamp.png';
      await File(imgPath).writeAsBytes(png);
      final out = '${dir.path}/story_$stamp.mp4';
      // -ss before the audio input picks WHICH part of the track plays.
      final cmd = '-y -loop 1 -i "$imgPath" '
          '-ss $_audioStartSec -i "$_audioUrl" '
          '-t $_audioSeconds -c:v libx264 -preset veryfast -tune stillimage '
          '-pix_fmt yuv420p -c:a aac -b:a 128k -shortest "$out"';
      final session = await FFmpegKit.execute(cmd);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      // The temp PNG has done its job.
      try { await File(imgPath).delete(); } catch (_) {}
      return out;
    } catch (_) {
      return null;
    }
  }

  void _openTextInput({_StoryItem? edit}) {
    _editTarget = edit;
    _textCtrl.text = edit?.text ?? '';
    if (edit != null) {
      _colorIdx = edit.colorIdx;
      _fontIdx = edit.fontIdx;
      _italic = edit.italic;
      _textStyleIdx = edit.textStyleIdx;
      _align = edit.align;
    }
    setState(() {
      _editingText = true;
      _drawing = false;
    });
  }

  void _commitText() {
    final t = _textCtrl.text.trim();
    setState(() {
      if (_editTarget != null) {
        if (t.isEmpty) {
          _items.remove(_editTarget);
        } else {
          _editTarget!
            ..text = t
            ..colorIdx = _colorIdx
            ..fontIdx = _fontIdx
            ..italic = _italic
            ..textStyleIdx = _textStyleIdx
            ..align = _align;
        }
      } else if (t.isNotEmpty) {
        _items.add(_StoryItem(
          text: t,
          kind: _ItemKind.text,
          colorIdx: _colorIdx,
          fontIdx: _fontIdx,
          italic: _italic,
          textStyleIdx: _textStyleIdx,
          align: _align,
        ));
      }
      _editTarget = null;
      _editingText = false;
    });
  }

  // ── GIF / stickers (Tenor) ────────────────────────────────────────────────
  Future<void> _addGif() async {
    final url = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const GifPickerScreen()),
    );
    if (url == null || !mounted) return;
    setState(() => _items.add(
        _StoryItem(imageUrl: url, kind: _ItemKind.image, scale: 1.0)));
  }

  void _addBadge(String text, IconData icon) {
    setState(() => _items.add(_StoryItem(
          text: text,
          kind: _ItemKind.badge,
          badgeIcon: icon,
          pos: const Offset(0.5, 0.3),
        )));
  }

  // ── "Add element" — a frosted-glass sheet of cards, not an Android list ───
  Future<void> _openElements() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      isScrollControlled: true,
      builder: (_) => _ElementsSheet(
        onPick: (a) => _runElement(a),
      ),
    );
  }

  void _runElement(_ElementAction a) {
    switch (a) {
      case _ElementAction.location: _addLocation(); break;
      case _ElementAction.link: _askLink(); break;
      case _ElementAction.weather: _addWeather(); break;
      case _ElementAction.time: _addTime(); break;
      case _ElementAction.emoji: _showEmojiStrip(); break;
      case _ElementAction.text: _openTextInput(); break;
      case _ElementAction.music: _pickMusic(); break;
      case _ElementAction.audio: _pickDeviceAudio(); break;
      case _ElementAction.gif: _addGif(); break;
      case _ElementAction.hashtag:
        _askText(context.t('elHashtag'), Icons.tag_rounded, prefix: '#');
        break;
      case _ElementAction.mention:
        _askText(context.t('elMention'), Icons.alternate_email_rounded,
            prefix: '@');
        break;
    }
  }

  /// Instagram-style link sticker: a NAME to show + the URL it opens.
  Future<void> _askLink() async {
    final res = await _promptLink();
    if (res == null || !mounted) return;
    setState(() => _items.add(_StoryItem(
          text: res.$1, // visible label, e.g. "TG"
          linkUrl: res.$2, // e.g. t.me/akadzh
          kind: _ItemKind.link,
          pos: const Offset(0.5, 0.35),
        )));
  }

  /// Two fields: label + URL.
  Future<(String, String)?> _promptLink() async {
    final c = context.k;
    final label = TextEditingController();
    final url = TextEditingController();
    return showDialog<(String, String)>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.t('elLink'),
            style: TextStyle(
                color: c.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: label,
            autofocus: true,
            style: TextStyle(color: c.ink),
            decoration: InputDecoration(
                labelText: context.t('linkName'), hintText: 'TG'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: url,
            style: TextStyle(color: c.ink),
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'URL', hintText: 't.me/akadzh'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('cancel'))),
          TextButton(
            onPressed: () {
              final u = url.text.trim();
              if (u.isEmpty) return;
              // Label is optional — fall back to showing the URL itself.
              final l = label.text.trim().isEmpty ? u : label.text.trim();
              Navigator.pop(context, (l, u));
            },
            child: Text(context.t('done')),
          ),
        ],
      ),
    );
  }

  void _addTime() {
    final now = TimeOfDay.now();
    _addBadge(
        '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        Icons.access_time_rounded);
  }

  Future<void> _addWeather() async {
    final w = await WeatherService.get();
    if (w == null || !mounted) return;
    final cur = WeatherService.describe(w['code'] as int);
    _addBadge('${cur.emoji} ${w['temp']}°', Icons.wb_sunny_rounded);
  }

  Future<void> _addLocation() async {
    // Reuses the weather lookup's city — no extra permission or service.
    final w = await WeatherService.get();
    if (!mounted) return;
    final city = (w?['city'] ?? '').toString();
    if (city.isEmpty) {
      _askText(context.t('elLocation'), Icons.location_on_rounded);
    } else {
      _addBadge(city, Icons.location_on_rounded);
    }
  }

  /// Shared one-field prompt used by link / #tag / @mention.
  Future<String?> _promptText(String title,
      {String prefix = '', String hint = ''}) async {
    final c = context.k;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: TextStyle(
                color: c.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.ink),
          decoration: InputDecoration(prefixText: prefix, hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(context.t('done'))),
        ],
      ),
    );
  }

  Future<void> _askText(String title, IconData icon, {String prefix = ''}) async {
    final v = await _promptText(title, prefix: prefix);
    if (v == null || v.isEmpty || !mounted) return;
    _addBadge('$prefix$v', icon);
  }

  // ── Music from "Rhythm" — searchable picker (Пункт 1) ─────────────────────
  Future<void> _pickMusic() async {
    final picked = await showModalBottomSheet<Map>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      isScrollControlled: true,
      builder: (_) => const MusicPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _audioUrl = (picked['audio'] ?? '').toString();
      _audioTitle = (picked['title'] ?? '').toString();
      // Rhythm reports track length in seconds — lets the trim sheet show the
      // real timeline instead of guessing.
      _audioTotalSec = int.tryParse((picked['duration'] ?? '').toString()) ?? 0;
    });
    setState(() => _items.add(_StoryItem(
          text: _audioTitle ?? '',
          kind: _ItemKind.music,
          artist: (picked['showTitle'] ?? '').toString(),
          artwork: (picked['artwork'] ?? '').toString(),
          pos: const Offset(0.5, 0.22),
          styleIdx: 1, // white Instagram-style card by default
        )));
    if (!widget.isVideo) await _askAudioLength();
    _startPreview();
  }

  /// Audio editor: pick WHICH part of the track plays and for how long.
  /// (Only for photo stories — a video keeps its own length.)
  Future<void> _askAudioLength() async {
    final res = await showModalBottomSheet<(int start, int len)>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      isScrollControlled: true,
      builder: (_) => AudioTrimSheet(
        title: _audioTitle ?? '',
        totalSec: _audioTotalSec,
        startSec: _audioStartSec,
        lenSec: _audioSeconds,
      ),
    );
    if (res != null && mounted) {
      setState(() {
        _audioStartSec = res.$1;
        _audioSeconds = res.$2;
      });
      _startPreview();
    }
  }

  // ── Audio file from the device ────────────────────────────────────────────
  Future<void> _pickDeviceAudio() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.audio, allowMultiple: false);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _audioUrl = path; // local path — ffmpeg reads it directly
      _audioTitle = path.split(Platform.pathSeparator).last;
    });
    setState(() => _items.add(_StoryItem(
          text: _audioTitle ?? '',
          kind: _ItemKind.music,
          pos: const Offset(0.5, 0.22),
        )));
    if (!widget.isVideo) await _askAudioLength();
    _startPreview();
  }

  void _addEmoji(String e) {
    setState(() {
      _items.add(_StoryItem(
          text: e,
          kind: _ItemKind.emoji,
          pos: const Offset(0.5, 0.45),
          scale: 1.4));
    });
  }

  void _showEmojiStrip() {
    setState(() => _drawing = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      barrierColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 200,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(10),
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _addEmoji(e);
                      },
                      child: Center(
                          child:
                              Text(e, style: const TextStyle(fontSize: 34))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _zoomablePhoto(Size size) {
    // While capturing the overlay layer for a video, the media must not be in
    // the frame — we need a transparent PNG of just the overlays.
    if (_captureOverlaysOnly) return const SizedBox.shrink();

    // Video story: the clip plays under the overlays.
    if (widget.isVideo) {
      final v = _vid;
      if (v == null || !v.value.isInitialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: v.value.size.width,
          height: v.value.size.height,
          child: VideoPlayer(v),
        ),
      );
    }

    final aspect = _imgAspect;
    if (aspect == null) {
      return Image.memory(widget.imageBytes!, fit: BoxFit.cover);
    }
    final screenAspect = size.width / size.height;
    double childW, childH;
    if (aspect >= screenAspect) {
      childH = size.height;
      childW = size.height * aspect;
    } else {
      childW = size.width;
      childH = size.width / aspect;
    }
    return InteractiveViewer(
      constrained: false,
      minScale: 0.4,
      maxScale: 5,
      boundaryMargin: EdgeInsets.symmetric(
          horizontal: size.width, vertical: size.height),
      child: SizedBox(
        width: childW,
        height: childH,
        child: Image.memory(widget.imageBytes!, fit: BoxFit.fill),
      ),
    );
  }

  Widget _overlay(_StoryItem it, Size size) {
    // Links are never flattened — the viewer renders them as real buttons.
    if (_hideLinksForCapture && it.kind == _ItemKind.link) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: it.pos.dx * size.width - 150,
      top: it.pos.dy * size.height - 40,
      child: GestureDetector(
        onScaleStart: (_) {
          _baseScale = it.scale;
          _baseRotation = it.rotation;
        },
        onScaleUpdate: (d) => setState(() {
          it.scale = (_baseScale * d.scale).clamp(0.3, 5.0);
          // Two-finger twist rotates the object.
          it.rotation = _baseRotation + d.rotation;
          it.pos = Offset(
            (it.pos.dx + d.focalPointDelta.dx / size.width)
                .clamp(0.02, 0.98),
            (it.pos.dy + d.focalPointDelta.dy / size.height)
                .clamp(0.02, 0.98),
          );
        }),
        // Tap a rich widget (music / link) to cycle its style, Instagram-style.
        onTap: it.isRich
            ? () {
                HapticFeedback.selectionClick();
                setState(() => it.styleIdx =
                    (it.styleIdx + 1) % (it.kind == _ItemKind.music ? 4 : 3));
              }
            : (it.isEmoji || it.isImage || it.isBadge)
                ? null
                : () => _openTextInput(edit: it),
        onLongPress: () => setState(() => _items.remove(it)),
        child: SizedBox(
          width: 300,
          child: Center(
            child: Transform.rotate(
              angle: it.rotation,
              child: _overlayContent(it),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayContent(_StoryItem it) {
    if (it.isImage) {
      // GIF / sticker — animated in the editor, flattened on publish.
      return SizedBox(
        width: 120 * it.scale,
        child: CachedNetworkImage(
          imageUrl: it.imageUrl!,
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox(
              width: 40, height: 40, child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    if (it.kind == _ItemKind.music) return _musicWidget(it);
    if (it.kind == _ItemKind.link) return _linkWidget(it);
    if (it.isBadge) return _glassCapsule(it);
    if (it.isEmoji) {
      return Text(it.text, style: TextStyle(fontSize: 44 * it.scale));
    }
    return _styledText(it);
  }

  /// Text with font, italic, outline / filled-background, alignment.
  Widget _styledText(_StoryItem it) {
    final color = _colors[it.colorIdx];
    final size = 26 * it.scale;
    final base = TextStyle(
      fontFamily: _fonts[it.fontIdx].family,
      fontSize: size,
      fontWeight: FontWeight.w800,
      fontStyle: it.italic ? FontStyle.italic : FontStyle.normal,
      height: 1.2,
    );

    // Outline: a stroked copy painted under a filled one.
    if (it.textStyleIdx == 1) {
      return Stack(children: [
        Text(it.text,
            textAlign: it.align,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.2
                ..color = color,
            )),
        Text(it.text,
            textAlign: it.align,
            style: base.copyWith(
                color: color == Colors.white ? Colors.black : Colors.white)),
      ]);
    }

    // Filled: text sits on a solid rounded slab (Instagram's "background" mode).
    if (it.textStyleIdx == 2) {
      final onLight = color == Colors.white || color == const Color(0xFFFFD740);
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: 10 * it.scale, vertical: 5 * it.scale),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8 * it.scale),
        ),
        child: Text(it.text,
            textAlign: it.align,
            style: base.copyWith(
                color: onLight ? Colors.black : Colors.white)),
      );
    }

    return Text(it.text,
        textAlign: it.align,
        style: base.copyWith(
          color: color,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
        ));
  }

  /// Italic · outline/background · alignment — the Instagram text row.
  Widget _textStyleBar() {
    final c = context.k;
    Widget btn(IconData icon, bool on, VoidCallback tap) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: on ? c.accent.withOpacity(0.28) : Colors.white12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: on ? c.accent : Colors.white24, width: 0.9),
            ),
            child: Icon(icon,
                size: 18, color: on ? c.accent : Colors.white),
          ),
        );
    const alignIcons = [
      Icons.format_align_left_rounded,
      Icons.format_align_center_rounded,
      Icons.format_align_right_rounded,
    ];
    const aligns = [TextAlign.left, TextAlign.center, TextAlign.right];
    final ai = aligns.indexOf(_align);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      btn(Icons.format_italic_rounded, _italic,
          () => setState(() => _italic = !_italic)),
      btn(Icons.border_color_rounded, _textStyleIdx == 1,
          () => setState(() => _textStyleIdx = _textStyleIdx == 1 ? 0 : 1)),
      btn(Icons.format_color_fill_rounded, _textStyleIdx == 2,
          () => setState(() => _textStyleIdx = _textStyleIdx == 2 ? 0 : 2)),
      btn(alignIcons[ai < 0 ? 1 : ai], false,
          () => setState(() => _align = aligns[((ai < 0 ? 1 : ai) + 1) % 3])),
    ]);
  }

  /// Font picker — system families, so nothing is bundled into the APK.
  Widget _fontBar() => SizedBox(
        height: 34,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          itemCount: _fonts.length,
          itemBuilder: (_, i) {
            final on = i == _fontIdx;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _fontIdx = i);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.white12,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white24, width: 0.9),
                ),
                child: Text(_fonts[i].label,
                    style: TextStyle(
                        color: on ? Colors.black : Colors.white,
                        fontFamily: _fonts[i].family,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            );
          },
        ),
      );

  /// Frosted capsule for weather / time / location / #tag / @user.
  Widget _glassCapsule(_StoryItem it) => ClipRRect(
        borderRadius: BorderRadius.circular(40 * it.scale),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: 15 * it.scale, vertical: 9 * it.scale),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(40 * it.scale),
              border: Border.all(
                  color: Colors.white.withOpacity(0.30), width: 0.9),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (it.badgeIcon != null) ...[
                Icon(it.badgeIcon,
                    size: 16 * it.scale, color: _colors[it.colorIdx]),
                SizedBox(width: 6 * it.scale),
              ],
              Text(it.text,
                  style: TextStyle(
                      color: _colors[it.colorIdx],
                      fontSize: 16 * it.scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2)),
            ]),
          ),
        ),
      );

  /// Music widget — tap cycles: title pill → cover card → mini player → wave.
  Widget _musicWidget(_StoryItem it) {
    final s = it.scale;
    final title = it.text;
    final artist = it.artist ?? '';
    switch (it.styleIdx) {
      case 1: // Instagram-style white card: artwork + equalizer, title, artist
        return Container(
          padding: EdgeInsets.all(9 * s),
          constraints: BoxConstraints(maxWidth: 240 * s),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18 * s),
            boxShadow: [
              BoxShadow(blurRadius: 16 * s, color: Colors.black26),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Artwork with the pulsing equalizer bars ON it, like Instagram.
            ClipRRect(
              borderRadius: BorderRadius.circular(12 * s),
              child: SizedBox(
                width: 52 * s,
                height: 52 * s,
                child: Stack(fit: StackFit.expand, children: [
                  it.artwork != null && it.artwork!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: it.artwork!, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFF222327),
                          child: Icon(Icons.music_note_rounded,
                              size: 22 * s, color: Colors.white70)),
                  Container(color: Colors.black26),
                  Center(child: _EqualizerBars(scale: s)),
                ]),
              ),
            ),
            SizedBox(width: 10 * s),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: const Color(0xFF101012),
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w800)),
                  if (artist.isNotEmpty) ...[
                    SizedBox(height: 2 * s),
                    Text(artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: const Color(0xFF7A7C85),
                            fontSize: 12.5 * s,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
          ]),
        );
      case 2: // mini player
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 9 * s),
          constraints: BoxConstraints(maxWidth: 240 * s),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(30 * s),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20 * s),
            SizedBox(width: 8 * s),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w700)),
                  if (artist.isNotEmpty)
                    Text(artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white54, fontSize: 10.5 * s)),
                ],
              ),
            ),
          ]),
        );
      case 3: // animated waveform, Telegram-style
        return ClipRRect(
          borderRadius: BorderRadius.circular(30 * s),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 14 * s, vertical: 9 * s),
              constraints: BoxConstraints(maxWidth: 250 * s),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(30 * s),
                border: Border.all(color: Colors.white30, width: 0.9),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.music_note_rounded,
                    color: Colors.white, size: 15 * s),
                SizedBox(width: 7 * s),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(width: 8 * s),
                _Waveform(scale: s),
              ]),
            ),
          ),
        );
      default: // 0 — plain glass title pill
        return ClipRRect(
          borderRadius: BorderRadius.circular(40 * s),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 15 * s, vertical: 9 * s),
              constraints: BoxConstraints(maxWidth: 250 * s),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(40 * s),
                border: Border.all(color: Colors.white30, width: 0.9),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.music_note_rounded,
                    color: Colors.white, size: 15 * s),
                SizedBox(width: 7 * s),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        );
    }
  }

  /// Link card — tap cycles white → black → glass.
  Widget _linkWidget(_StoryItem it) {
    final s = it.scale;
    final white = it.styleIdx == 0;
    final glass = it.styleIdx == 2;
    final fg = white ? const Color(0xFF0A0A0A) : Colors.white;
    final card = Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 11 * s),
      constraints: BoxConstraints(maxWidth: 250 * s),
      decoration: BoxDecoration(
        color: glass
            ? Colors.white.withOpacity(0.18)
            : (white ? Colors.white : const Color(0xFF101012)),
        borderRadius: BorderRadius.circular(16 * s),
        border: glass
            ? Border.all(color: Colors.white30, width: 0.9)
            : null,
        boxShadow: glass
            ? null
            : [BoxShadow(blurRadius: 14 * s, color: Colors.black38)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.link_rounded, size: 19 * s, color: fg),
        SizedBox(width: 9 * s),
        Flexible(
          child: Text(it.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: white ? const Color(0xFF0A66FF) : Colors.lightBlueAccent,
                  fontSize: 15 * s,
                  fontWeight: FontWeight.w800)),
        ),
      ]),
    );
    return glass
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16 * s),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: card,
            ),
          )
        : card;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Canvas captured on publish ─────────────────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: Colors.black),
              _zoomablePhoto(size),
              // Drawing layer (on top of the photo, below stickers).
              IgnorePointer(
                ignoring: !_drawing,
                child: GestureDetector(
                  onPanStart: _drawing
                      ? (d) => setState(() => _strokes
                          .add(_Stroke(_colors[_colorIdx])
                            ..points.add(d.localPosition)))
                      : null,
                  onPanUpdate: _drawing
                      ? (d) => setState(
                          () => _strokes.last.points.add(d.localPosition))
                      : null,
                  child: CustomPaint(
                    painter: _DrawPainter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (!_editingText)
                ..._items.map((it) => _overlay(it, size)),
            ]),
          ),
        ),

        // ── Top bar ────────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            if (_strokes.isNotEmpty && _drawing)
              IconButton(
                icon: const Icon(Icons.undo_rounded,
                    color: Colors.white, size: 26),
                onPressed: () =>
                    setState(() => _strokes.removeLast()),
              ),
            IconButton(
              icon: Icon(Icons.brush_rounded,
                  color: _drawing ? Colors.amberAccent : Colors.white,
                  size: 26),
              onPressed: () => setState(() {
                _drawing = !_drawing;
                _editingText = false;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.emoji_emotions_rounded,
                  color: Colors.white, size: 26),
              onPressed: _showEmojiStrip,
            ),
            // GIF / stickers
            IconButton(
              icon: const Icon(Icons.gif_box_rounded,
                  color: Colors.white, size: 26),
              onPressed: _addGif,
            ),
            // Time / weather / location / link / #tag / @mention / music
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: Colors.white, size: 26),
              onPressed: _openElements,
            ),
            IconButton(
              icon: const Icon(Icons.text_fields_rounded,
                  color: Colors.white, size: 26),
              onPressed: () => _openTextInput(),
            ),
          ]),
        ),

        // ── Colour palette (visible while drawing) ─────────────────────
        if (_drawing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
            child: _palette(),
          ),

        // ── Text input overlay ─────────────────────────────────────────
        if (_editingText)
          Positioned.fill(
            child: GestureDetector(
              onTap: _commitText,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: _textCtrl,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      textAlign: _align,
                      style: TextStyle(
                        color: _colors[_colorIdx],
                        fontFamily: _fonts[_fontIdx].family,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontStyle:
                            _italic ? FontStyle.italic : FontStyle.normal,
                      ),
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                      onSubmitted: (_) => _commitText(),
                    ),
                    const SizedBox(height: 18),
                    _textStyleBar(),
                    const SizedBox(height: 14),
                    _fontBar(),
                    const SizedBox(height: 16),
                    _palette(),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _commitText,
                      child: Text(context.t('done'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Publish button ─────────────────────────────────────────────
        if (!_editingText)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            right: 16,
            child: GestureDetector(
              onTap: _publish,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.t('publishBtn'),
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  const SizedBox(width: 6),
                  _publishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.arrow_forward_rounded,
                          color: Colors.black, size: 18),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _palette() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_colors.length, (i) {
        final sel = i == _colorIdx;
        return GestureDetector(
          onTap: () => setState(() => _colorIdx = i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: sel ? 32 : 26,
            height: sel ? 32 : 26,
            decoration: BoxDecoration(
              color: _colors[i],
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: sel ? 3 : 1.5),
            ),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _preview.dispose(); // stop sound the moment the editor closes
    _vid?.dispose();
    _textCtrl.dispose();
    super.dispose();
  }
}

class _DrawPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _DrawPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  "Add element" sheet — frosted glass, card grid, spring press feedback.
// ═══════════════════════════════════════════════════════════════════════════
enum _ElementAction {
  location, link, weather, time, emoji, text, music, audio, gif, hashtag, mention,
}

class _ElementsSheet extends StatelessWidget {
  final void Function(_ElementAction) onPick;
  const _ElementsSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final items = <(_ElementAction, IconData, String)>[
      (_ElementAction.location, Icons.location_on_rounded, context.t('elLocation')),
      (_ElementAction.link, Icons.link_rounded, context.t('elLink')),
      (_ElementAction.weather, Icons.wb_sunny_rounded, context.t('elWeather')),
      (_ElementAction.time, Icons.schedule_rounded, context.t('elTime')),
      (_ElementAction.emoji, Icons.emoji_emotions_rounded, context.t('elEmoji')),
      (_ElementAction.text, Icons.text_fields_rounded, context.t('elText')),
      (_ElementAction.music, Icons.music_note_rounded, context.t('elMusic')),
      (_ElementAction.audio, Icons.audiotrack_rounded, context.t('elAudio')),
      (_ElementAction.gif, Icons.gif_box_rounded, context.t('elGif')),
      (_ElementAction.hashtag, Icons.tag_rounded, context.t('elHashtag')),
      (_ElementAction.mention, Icons.alternate_email_rounded, context.t('elMention')),
    ];
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121316).withOpacity(0.82),
            border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.10))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // grabber
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.t('addElement'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.02,
                  children: [
                    for (final (a, icon, label) in items)
                      _ElementCard(
                        icon: icon,
                        label: label,
                        onTap: () {
                          Navigator.pop(context);
                          onPick(a);
                        },
                      ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One card: shrinks slightly under the finger, then springs back.
class _ElementCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ElementCard(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_ElementCard> createState() => _ElementCardState();
}

class _ElementCardState extends State<_ElementCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            splashColor: c.accent.withOpacity(0.22),
            highlightColor: Colors.white10,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.09)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 26),
                  const SizedBox(height: 9),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(widget.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated bars, like Telegram's music widget. Purely decorative — it keeps
/// one cheap controller and repaints only the bars.
class _Waveform extends StatefulWidget {
  final double scale;
  const _Waveform({required this.scale});
  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  static const _base = [0.35, 0.75, 0.5, 0.95, 0.6, 0.85, 0.4];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _base.length; i++) ...[
            Container(
              width: 2.5 * s,
              height: (7 + 11 * _base[i] * (0.45 + 0.55 * _c.value)) * s,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2 * s),
              ),
            ),
            if (i != _base.length - 1) SizedBox(width: 2.2 * s),
          ],
        ],
      ),
    );
  }
}


/// Pulsing equalizer bars drawn over the artwork (Instagram-style).
class _EqualizerBars extends StatefulWidget {
  final double scale;
  const _EqualizerBars({required this.scale});
  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  static const _phases = [0.9, 0.45, 0.75];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _phases.length; i++) ...[
            Container(
              width: 5 * s,
              height: (8 + 16 * _phases[i] * (0.35 + 0.65 * _c.value)) * s,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3 * s),
              ),
            ),
            if (i != _phases.length - 1) SizedBox(width: 3.5 * s),
          ],
        ],
      ),
    );
  }
}
