import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../l10n/app_strings.dart';
import '../services/music_preview.dart';
import '../theme/brutal_theme.dart';

/// Device audio browser (spec: «Музыка из устройства»). Lists the phone's
/// audio files via MediaStore (photo_manager), with search, and previews the
/// tapped track through the shared preview player.
///
/// Returns `{path, title, artist, dur}` via Navigator.pop — a LOCAL path,
/// never uploaded; the caller burns it into the media on export.
class DeviceMusicSheet extends StatefulWidget {
  const DeviceMusicSheet({Key? key}) : super(key: key);

  @override
  State<DeviceMusicSheet> createState() => _DeviceMusicSheetState();
}

class _DeviceMusicSheetState extends State<DeviceMusicSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<AssetEntity> _all = [];
  List<AssetEntity> _shown = [];
  bool _loading = true;
  bool _denied = false;
  String? _previewingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    MusicPreview.i.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      if (mounted) setState(() { _denied = true; _loading = false; });
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.audio,
      onlyAll: true,
    );
    final list = <AssetEntity>[];
    if (paths.isNotEmpty) {
      final count = await paths.first.assetCountAsync;
      list.addAll(await paths.first
          .getAssetListRange(start: 0, end: count.clamp(0, 500)));
    }
    if (!mounted) return;
    setState(() {
      _all = list;
      _shown = list;
      _loading = false;
    });
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final t = q.trim().toLowerCase();
      setState(() => _shown = t.isEmpty
          ? _all
          : _all.where((a) => a.title!.toLowerCase().contains(t)).toList());
    });
    setState(() {});
  }

  Future<void> _tap(AssetEntity a) async {
    final f = await a.file;
    if (f == null || !mounted) return;
    // Preview through the shared player.
    setState(() => _previewingId = a.id);
    MusicPreview.i.playUrl(f.path, title: a.title ?? '');
  }

  Future<void> _select(AssetEntity a) async {
    final f = await a.file;
    if (f == null || !mounted) return;
    Navigator.pop(context, {
      'path': f.path,
      'title': (a.title ?? 'Audio').replaceAll(
          RegExp(r'\.(mp3|m4a|aac|wav|flac|ogg)$', caseSensitive: false), ''),
      'artist': '',
      'dur': a.duration,
    });
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final h = MediaQuery.of(context).size.height * 0.75;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF121316).withOpacity(0.9),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SafeArea(
            top: false,
            child: Column(children: [
              const SizedBox(height: 10),
              Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onQuery,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: context.t('musicSearchHint'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.white54),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onQuery('');
                            }),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _body(c)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body(BrutalColors c) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_off_rounded,
                color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(context.t('galleryNoAccess'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: PhotoManager.openSetting,
              child: Text(context.t('openSettings')),
            ),
          ]),
        ),
      );
    }
    if (_shown.isEmpty) {
      return Center(
        child: Text(context.t('musicNotFound'),
            style: const TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: _shown.length,
      itemBuilder: (_, i) {
        final a = _shown[i];
        final active = _previewingId == a.id;
        return ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(active ? Icons.pause_rounded : Icons.audiotrack_rounded,
                color: active ? c.accent : Colors.white54),
          ),
          title: Text(a.title ?? 'Audio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(_fmt(a.duration),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: TextButton(
            onPressed: () => _select(a),
            child: Text(context.t('next'),
                style: TextStyle(color: c.accent2, fontWeight: FontWeight.w700)),
          ),
          onTap: () => _tap(a),
        );
      },
    );
  }
}
