import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

/// Music picker with live search (Пункт 1). Debounced 300 ms, searches Rhythm
/// (Audius) by track AND artist server-side; empty query shows trending.
/// Returns the picked track Map via Navigator.pop.
class MusicPickerSheet extends StatefulWidget {
  const MusicPickerSheet({Key? key}) : super(key: key);

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    // Audius search matches both track titles and artist names.
    final res = q.isEmpty
        ? await ApiService.musicTrending()
        : await ApiService.musicSearch(q);
    if (!mounted) return;
    setState(() {
      _tracks = res;
      _loading = false;
    });
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q.trim()));
    setState(() {}); // refresh the clear-button visibility
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final h = MediaQuery.of(context).size.height * 0.72;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF121316).withOpacity(0.88),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.10))),
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
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              // ── Search field ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onQuery,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: context.t('musicSearchHint'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: Colors.white54),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onQuery('');
                            },
                          ),
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
              // ── Results ──────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: c.accent))
                    : _tracks.isEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.music_off_rounded,
                                  color: Colors.white24, size: 52),
                              const SizedBox(height: 12),
                              Text(context.t('musicNotFound'),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 14)),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _tracks.length,
                            itemBuilder: (_, i) => _trackTile(_tracks[i]),
                          ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _trackTile(Map t) {
    final art = (t['artwork'] ?? '').toString();
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: art.isEmpty
            ? Container(
                width: 42,
                height: 42,
                color: Colors.white12,
                child: const Icon(Icons.music_note_rounded,
                    color: Colors.white54))
            : CachedNetworkImage(
                imageUrl: art, width: 42, height: 42, fit: BoxFit.cover),
      ),
      title: Text((t['title'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
      subtitle: Text((t['showTitle'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onTap: () => Navigator.pop(context, t),
    );
  }
}
