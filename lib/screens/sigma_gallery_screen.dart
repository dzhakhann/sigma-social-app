import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'story_camera_screen.dart';

/// Sigmacta's own media picker — replaces the system Android photo picker.
/// Telegram-style: album dropdown, 3-column grid of photos AND videos, numbered
/// multi-select, in-app camera shortcut.
///
/// Reads the device MediaStore through photo_manager and returns the ORIGINAL
/// files — nothing is copied, cached in a DB, or uploaded here. The caller gets
/// `List<File>` back via Navigator.pop and decides what to do with them.
class SigmaGalleryScreen extends StatefulWidget {
  /// 1 = single tap-to-pick (no checkmarks). >1 enables multi-select.
  final int maxSelection;

  /// Restrict the grid: images only, videos only, or both.
  final RequestType type;

  /// Show the in-app camera button in the top bar.
  final bool allowCamera;

  const SigmaGalleryScreen({
    Key? key,
    this.maxSelection = 1,
    this.type = RequestType.common, // images + videos
    this.allowCamera = true,
  }) : super(key: key);

  @override
  State<SigmaGalleryScreen> createState() => _SigmaGalleryScreenState();
}

class _SigmaGalleryScreenState extends State<SigmaGalleryScreen> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  final List<AssetEntity> _picked = [];

  bool _loading = true;
  bool _denied = false;
  bool _loadingPage = false;
  bool _end = false;
  int _page = 0;
  static const _pageSize = 90;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) setState(() { _denied = true; _loading = false; });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: widget.type,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() { _loading = false; });
      return;
    }
    _albums = albums;
    _album = albums.first; // "Recent" / "All"
    setState(() => _loading = false);
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingPage || (_end && !reset) || _album == null) return;
    _loadingPage = true;
    if (reset) {
      _page = 0;
      _end = false;
      _assets.clear();
    }
    final batch = await _album!.getAssetListPaged(page: _page, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets.addAll(batch);
      _page++;
      if (batch.length < _pageSize) _end = true;
    });
    _loadingPage = false;
  }

  Future<void> _switchAlbum(AssetPathEntity a) async {
    setState(() => _album = a);
    await _loadMore(reset: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _toggle(AssetEntity a) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_picked.contains(a)) {
        _picked.remove(a);
      } else if (_picked.length < widget.maxSelection) {
        _picked.add(a);
      }
    });
  }

  Future<void> _tap(AssetEntity a) async {
    if (widget.maxSelection > 1) {
      _toggle(a);
      return;
    }
    // Single-pick: return immediately.
    final f = await a.originFile ?? await a.file;
    if (f != null && mounted) Navigator.pop(context, <File>[f]);
  }

  Future<void> _done() async {
    if (_picked.isEmpty) return;
    final files = <File>[];
    for (final a in _picked) {
      final f = await a.originFile ?? await a.file;
      if (f != null) files.add(f);
    }
    if (mounted) Navigator.pop(context, files);
  }

  Future<void> _openCamera() async {
    final cap = await Navigator.push<StoryCapture>(
      context,
      MaterialPageRoute(
        // Only offer hold-to-record where this picker actually accepts video.
        builder: (_) =>
            StoryCameraScreen(allowVideo: widget.type != RequestType.image),
      ),
    );
    if (cap == null || !mounted) return;
    // Unwrap to the shapes callers already handle: photo → bytes, video → file.
    if (cap.photo != null) {
      Navigator.pop(context, cap.photo);
    } else if (cap.videoPath != null) {
      Navigator.pop(context, <File>[File(cap.videoPath!)]);
    }
  }

  Future<void> _pickAlbum() async {
    final c = context.k;
    final chosen = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _albums.length,
          itemBuilder: (_, i) {
            final a = _albums[i];
            final sel = a.id == _album?.id;
            return ListTile(
              leading: Icon(
                  sel ? Icons.folder_rounded : Icons.folder_outlined,
                  color: sel ? c.accent : c.inkSoft),
              title: Text(a.name,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 15,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              trailing: sel ? Icon(Icons.check_rounded, color: c.accent) : null,
              onTap: () => Navigator.pop(context, a),
            );
          },
        ),
      ),
    );
    if (chosen != null) _switchAlbum(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final multi = widget.maxSelection > 1;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(c),
          Expanded(child: _body(c)),
          if (multi) _bottomBar(c),
        ]),
      ),
    );
  }

  Widget _topBar(BrutalColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: c.ink),
            onPressed: () => Navigator.pop(context),
          ),
          Text(context.t('galleryTitle'),
              style: TextStyle(
                  color: c.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          // Album dropdown — "Недавние ▼"
          if (_albums.isNotEmpty)
            Flexible(
              child: GestureDetector(
                onTap: _pickAlbum,
                behavior: HitTestBehavior.opaque,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(_album?.name ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.inkSoft,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: c.inkSoft, size: 18),
                ]),
              ),
            ),
          const Spacer(),
          if (widget.allowCamera)
            IconButton(
              icon: Icon(Icons.photo_camera_rounded, color: c.ink, size: 22),
              onPressed: _openCamera,
            ),
        ]),
      );

  Widget _body(BrutalColors c) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_denied) return _permissionDenied(c);
    if (_assets.isEmpty) {
      return Center(
        child: Text(context.t('galleryEmpty'),
            style: TextStyle(color: c.inkSoft)),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) => _tile(c, _assets[i]),
    );
  }

  Widget _tile(BrutalColors c, AssetEntity a) {
    final idx = _picked.indexOf(a);
    final sel = idx >= 0;
    final isVideo = a.type == AssetType.video;
    return GestureDetector(
      onTap: () => _tap(a),
      onLongPress: widget.maxSelection > 1 ? () => _toggle(a) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          // Thumbnail straight from MediaStore — no copies, no disk cache.
          AssetEntityImage(
            a,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(320),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: c.surface2),
          ),
          if (sel) Container(color: c.accent.withOpacity(0.35)),
          if (isVideo)
            const IgnorePointer(
              child: Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 34,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black54)]),
              ),
            ),
          if (isVideo)
            Positioned(
              right: 6,
              bottom: 5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(_dur(a.duration),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          // Numbered checkmark (Telegram-style), multi-select only.
          if (widget.maxSelection > 1)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: sel ? c.accent : Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.6),
                ),
                alignment: Alignment.center,
                child: sel
                    ? Text('${idx + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800))
                    : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _bottomBar(BrutalColors c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.ink.withOpacity(0.07))),
        ),
        child: Row(children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('cancel'),
                style: TextStyle(color: c.inkSoft, fontSize: 15)),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _picked.isEmpty ? null : _done,
            style: FilledButton.styleFrom(backgroundColor: c.accent),
            child: Text(
              _picked.isEmpty
                  ? context.t('next')
                  : '${context.t('next')} (${_picked.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );

  Widget _permissionDenied(BrutalColors c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.photo_library_outlined, size: 48, color: c.inkSoft),
            const SizedBox(height: 14),
            Text(context.t('galleryNoAccess'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: PhotoManager.openSetting,
              style: FilledButton.styleFrom(backgroundColor: c.accent),
              child: Text(context.t('openSettings')),
            ),
          ]),
        ),
      );

  String _dur(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
