import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/music_widgets.dart';
import 'sigma_gallery_screen.dart';
import 'story_music_picker_sheet.dart';
import '../services/api_service.dart';
import '../services/events.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/emoji_picker.dart';
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
  String? _imageB64;
  String? _gifUrl; // remote GIF (Tenor) — used directly, no re-upload

  /// ONE attached track — Rhythm only: {url, title, artist, art}. Stored as a
  /// catalog link, costs the server nothing.
  Map? _music;
  bool _posting = false;

  bool get _canPost =>
      _textCtrl.text.trim().isNotEmpty || _imageB64 != null || _gifUrl != null;

  // Sigmacta's own gallery (MediaStore) instead of the system photo picker.
  Future<void> _pickImage() async {
    final picked = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
          builder: (_) => const SigmaGalleryScreen(type: RequestType.image)),
    );
    Uint8List? bytes;
    if (picked is Uint8List) {
      bytes = picked; // came from the gallery's camera shortcut
    } else if (picked is List<File> && picked.isNotEmpty) {
      bytes = await picked.first.readAsBytes();
    }
    if (bytes == null || !mounted) return;
    setState(() { _imageB64 = base64Encode(bytes!); _gifUrl = null; });
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.camera, maxWidth: 1080, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() { _imageB64 = base64Encode(bytes); _gifUrl = null; });
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
      builder: (_) => const MusicPickerSheet(),
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
      setState(() { _gifUrl = url; _imageB64 = null; });
    }
  }

  Future<void> _post() async {
    if (!_canPost || _posting) return;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      if (_gifUrl != null) {
        imageUrl = _gifUrl; // Tenor hosts the GIF — use its URL directly.
      } else if (_imageB64 != null) {
        imageUrl = await ApiService.uploadMedia(
          base64Decode(_imageB64!),
          folder: 'post',
          ext: 'jpg',
          contentType: 'image/jpeg',
          userId: widget.user['id'].toString(),
        );
      }
      await ApiService.createPost(
        widget.user['id'],
        _textCtrl.text.trim(),
        imageUrl: imageUrl,
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

                        // ── Attached image preview ────────────────────
                        if (_imageB64 != null) ...[
                          const SizedBox(height: 10),
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  base64Decode(_imageB64!),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _imageB64 = null),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
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
                  Text(
                    context.t('publicPost'),
                    style: TextStyle(color: c.inkSoft, fontSize: 13),
                  ),
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
