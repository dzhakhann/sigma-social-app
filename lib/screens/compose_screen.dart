import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/music_widgets.dart';
import 'sigma_gallery_screen.dart';
import 'media_picker_sheet.dart';
import '../services/api_service.dart';
import '../services/events.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/link_preview.dart';
import 'gif_picker_screen.dart';

/// Threads-style full-screen post composer.
/// Opened from the FAB "+" button on the home screen.
class ComposeScreen extends StatefulWidget {
  final Map user;
  const ComposeScreen({super.key, required this.user});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _textCtrl = TextEditingController();

  /// Instagram-style photo carousel: 1..10 photos in one post. Kept as a list
  /// even for a single photo so the preview/upload code has one path.
  final List<String> _imagesB64 = [];
  String? _gifUrl; // remote GIF (Tenor) — used directly, no re-upload

  /// ONE attached track — Rhythm only: {url, title, artist, art}. Stored as a
  /// catalog link, costs the server nothing.
  Map? _music;
  bool _posting = false;

  // Telegram-style: unfurl a link WHILE typing, not just after publishing.
  String? _liveLinkUrl;
  Timer? _linkDebounce;

  static const _maxPhotos = 10;

  bool get _canPost =>
      _textCtrl.text.trim().isNotEmpty || _imagesB64.isNotEmpty || _gifUrl != null;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final url = firstUrl(_textCtrl.text);
      if (url != _liveLinkUrl) setState(() => _liveLinkUrl = url);
    });
  }

  // Sigmacta's own gallery (MediaStore) instead of the system photo picker.
  // Multi-select (Instagram-style carousel) — long-press a photo to pick more
  // than one, up to _maxPhotos.
  Future<void> _pickImage() async {
    final remaining = _maxPhotos - _imagesB64.length;
    if (remaining <= 0) return;
    final picked = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
          builder: (_) => SigmaGalleryScreen(
              type: RequestType.image, maxSelection: remaining)),
    );
    List<Uint8List> bytesList = [];
    if (picked is Uint8List) {
      bytesList = [picked]; // came from the gallery's camera shortcut
    } else if (picked is List<Uint8List> && picked.isNotEmpty) {
      bytesList = picked; // web: bytes read already, no dart:io File
    } else if (picked is List<File> && picked.isNotEmpty) {
      bytesList = await Future.wait(picked.map((f) => f.readAsBytes()));
    }
    if (bytesList.isEmpty || !mounted) return;
    setState(() {
      _imagesB64.addAll(bytesList.map(base64Encode));
      _gifUrl = null;
    });
  }

  Future<void> _takePhoto() async {
    if (_imagesB64.length >= _maxPhotos) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.camera, maxWidth: 1080, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() { _imagesB64.add(base64Encode(bytes)); _gifUrl = null; });
  }

  /// Attach music — Rhythm ONLY: catalog tracks are stored as a link and
  /// cost the server nothing; device files would need uploading, so they're
  /// not allowed on posts.
  Future<void> _pickMusic() async {
    final picked = await showModalBottomSheet<Map>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      isScrollControlled: true,
      builder: (_) => const MediaPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() => _music = {
          'url': (picked['audio'] ?? '').toString(),
          'title': (picked['title'] ?? '').toString(),
          'artist': (picked['showTitle'] ?? '').toString(),
          'art': (picked['artwork'] ?? '').toString(),
        });
  }

  Future<void> _pickGif() async {
    final url = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const GifPickerScreen()),
    );
    if (url != null && url.isNotEmpty) {
      setState(() { _gifUrl = url; _imagesB64.clear(); });
    }
  }

  Future<void> _post() async {
    if (!_canPost || _posting) return;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      List<String>? mediaUrls;
      if (_gifUrl != null) {
        imageUrl = _gifUrl; // Tenor hosts the GIF — use its URL directly.
      } else if (_imagesB64.isNotEmpty) {
        // Upload every photo in order — the carousel's swipe order matches
        // the order they were picked/added in.
        final urls = await Future.wait(_imagesB64.map((b64) => ApiService.uploadMedia(
              base64Decode(b64),
              folder: 'post',
              ext: 'jpg',
              contentType: 'image/jpeg',
              userId: widget.user['id'].toString(),
            )));
        mediaUrls = urls.whereType<String>().toList();
        imageUrl = mediaUrls.isNotEmpty ? mediaUrls.first : null;
      }
      await ApiService.createPost(
        widget.user['id'],
        _textCtrl.text.trim(),
        imageUrl: imageUrl,
        mediaUrls: mediaUrls,
        music: _music,
      );
      feedRefresh.value++; // tell Home to reload so the post shows instantly
      if (mounted) Navigator.pop(context, true); // true = posted
    } catch (_) {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    _linkDebounce?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final avatar = widget.user['avatar_url'];
    final username = widget.user['username'] ?? 'User';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        leading: IconButton(
          icon: Icon(Icons.close, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('newBranch'),
            style: TextStyle(
                color: c.ink, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar + thread line ─────────────────────────────
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: c.surface2,
                        backgroundImage: avatar != null
                            ? NetworkImage(avatar)
                            : null,
                        child: avatar == null
                            ? Icon(Icons.person, color: c.inkSoft, size: 20)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 2,
                        height: 60,
                        decoration: BoxDecoration(
                          color: c.ink.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // ── Content area ─────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: TextStyle(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _textCtrl,
                          autofocus: true,
                          maxLines: null,
                          minLines: 3,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(color: c.ink, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: context.t('whatsNew'),
                            hintStyle:
                                TextStyle(color: c.inkSoft, fontSize: 16),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),

                        // Live link preview — Telegram-style unfurl while
                        // typing. Skipped once a photo is attached, same
                        // rule the published post itself follows.
                        if (_liveLinkUrl != null && _imagesB64.isEmpty)
                          Stack(children: [
                            LinkPreviewCard(
                                key: ValueKey(_liveLinkUrl),
                                url: _liveLinkUrl!),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  _linkDebounce?.cancel();
                                  setState(() => _liveLinkUrl = null);
                                },
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded,
                                      color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ]),

                        // ── Attached photo(s) preview ─────────────────
                        // A single photo gets a big preview; 2+ show as a
                        // horizontal filmstrip (Instagram-style carousel
                        // compose), each removable, with an "Add more" tile.
                        if (_imagesB64.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          if (_imagesB64.length == 1)
                            Stack(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  base64Decode(_imagesB64.first),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: () => setState(() => _imagesB64.clear()),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ])
                          else
                            SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imagesB64.length + 1,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  if (i == _imagesB64.length) {
                                    return _imagesB64.length >= _maxPhotos
                                        ? const SizedBox.shrink()
                                        : GestureDetector(
                                            onTap: _pickImage,
                                            child: Container(
                                              width: 90,
                                              decoration: BoxDecoration(
                                                color: c.surface2,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Icon(Icons.add_rounded, color: c.accent),
                                            ),
                                          );
                                  }
                                  return Stack(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        base64Decode(_imagesB64[i]),
                                        width: 90,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _imagesB64.removeAt(i)),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: const BoxDecoration(
                                              color: Colors.black54, shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 13),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text('${i + 1}',
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 10)),
                                      ),
                                    ),
                                  ]);
                                },
                              ),
                            ),
                        ],

                        // ── Attached GIF preview ──────────────────────
                        if (_gifUrl != null) ...[
                          const SizedBox(height: 10),
                          Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: _gifUrl!,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 6, right: 6,
                              child: GestureDetector(
                                onTap: () => setState(() => _gifUrl = null),
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ]),
                        ],

                        // ── Attached music preview ────────────────────
                        if (_music != null) ...[
                          const SizedBox(height: 12),
                          Stack(children: [
                            PostMusicBar(track: _music!),
                            Positioned(
                              top: 4, right: -6,
                              child: IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white54, size: 18),
                                onPressed: () =>
                                    setState(() => _music = null),
                              ),
                            ),
                          ]),
                        ],

                        // ── Media buttons row ─────────────────────────
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            // Scrolls sideways so every button stays reachable
                            // on narrow screens (Музыка used to be cut off).
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  _MediaBtn(
                                      icon: Icons.image_rounded,
                                      label: context.t('photoBtn'),
                                      onTap: _pickImage),
                                  const SizedBox(width: 10),
                                  _MediaBtn(
                                      icon: Icons.camera_alt_rounded,
                                      label: context.t('cameraBtn'),
                                      onTap: _takePhoto),
                                  const SizedBox(width: 10),
                                  _MediaBtn(
                                      icon: Icons.gif_box_rounded,
                                      label: 'GIF',
                                      onTap: _pickGif),
                                  const SizedBox(width: 10),
                                  _MediaBtn(
                                      icon: Icons.music_note_rounded,
                                      label: context.t('musicBtn'),
                                      onTap: _pickMusic),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            EmojiPickerButton(controller: _textCtrl),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom bar with post button ────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(
                  top: BorderSide(color: c.ink.withOpacity(0.07), width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: _canPost && !_posting ? _post : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: _canPost
                            ? c.accent
                            : c.ink.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _posting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.onAccent),
                            )
                          : Text(
                              context.t('publishBtn'),
                              style: TextStyle(
                                color: _canPost ? c.onAccent : c.inkSoft,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MediaBtn(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: c.surface2, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c.accent, size: 18),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: c.ink, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
