import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline downloads for Rhythm (music · podcasts · audiobooks).
///
/// The audio file is saved **only on the device** — under the app's private
/// documents folder — and an index of what's downloaded lives in
/// shared_preferences. Nothing is ever uploaded: our server and database stay
/// untouched, so this feature adds zero backend cost.
///
/// A "track" here is the same Map used everywhere else (music track / podcast
/// episode / audiobook chapter): it has at least `audio`, and usually `title`,
/// `showTitle`, `artwork`, `duration`, `kind`.
class DownloadStore {
  DownloadStore._();

  static const _kIndex = 'offline_downloads';
  static const _dirName = 'offline_audio';

  // audioUrl -> stored record (kept in memory for synchronous playback lookups).
  static final Map<String, Map> _index = {};
  static bool _loaded = false;
  static final Dio _dio = Dio();

  /// Bumped whenever the download set changes, so widgets can rebuild.
  static final ValueNotifier<int> version = ValueNotifier(0);

  // Tracks in-flight downloads (audioUrl -> 0..1 progress) for live UI.
  static final ValueNotifier<Map<String, double>> progress =
      ValueNotifier(<String, double>{});

  /// Loads the on-disk index into memory. Call once at app start.
  static Future<void> init() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kIndex);
      if (s != null) {
        for (final e in (jsonDecode(s) as List)) {
          final m = Map.from(e);
          final audio = (m['audio'] ?? '').toString();
          // Drop records whose file vanished (e.g. app data cleared).
          final path = (m['localPath'] ?? '').toString();
          if (audio.isNotEmpty && path.isNotEmpty && File(path).existsSync()) {
            _index[audio] = m;
          }
        }
      }
    } catch (_) {}
    _loaded = true;
    version.value++;
  }

  static Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kIndex, jsonEncode(_index.values.toList()));
  }

  // ─── Queries (synchronous — safe once init() has run) ──────────────────────
  static bool isDownloaded(String? audio) =>
      audio != null && _index.containsKey(audio);

  static String? localPath(String? audio) =>
      audio == null ? null : (_index[audio]?['localPath'] as String?);

  static bool isDownloading(String? audio) =>
      audio != null && progress.value.containsKey(audio);

  static double progressOf(String? audio) =>
      audio == null ? 0 : (progress.value[audio] ?? 0);

  /// All downloads, newest first, optionally limited to one media kind.
  static List<Map> all({String? kind}) {
    final list = _index.values.toList().reversed.toList();
    if (kind == null) return list;
    return list.where((e) => e['kind'] == kind).toList();
  }

  static int count({String? kind}) => all(kind: kind).length;

  // ─── Download / remove ─────────────────────────────────────────────────────
  static String _extFor(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && dot >= path.length - 5) {
      final ext = path.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext)) return ext;
    }
    return 'mp3'; // Audius streams + most feeds are mp3
  }

  static String _fileNameFor(String url) {
    // Stable, collision-resistant name; the real URL is the index key, so a
    // filename clash would at worst reuse a file, never mis-route a lookup.
    final h = url.hashCode.toUnsigned(32).toRadixString(16);
    return 'dl_${url.length}_$h.${_extFor(url)}';
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Downloads [track] for offline playback. Returns true on success.
  static Future<bool> download(Map track) async {
    final audio = (track['audio'] ?? '').toString();
    if (audio.isEmpty || isDownloaded(audio) || isDownloading(audio)) {
      return isDownloaded(audio);
    }
    _setProgress(audio, 0);
    try {
      final dir = await _dir();
      final path = '${dir.path}/${_fileNameFor(audio)}';
      await _dio.download(
        audio,
        path,
        onReceiveProgress: (recv, total) {
          if (total > 0) _setProgress(audio, recv / total);
        },
      );
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        _clearProgress(audio);
        return false;
      }
      // Persist a slim record — enough to render & play the row offline.
      _index[audio] = {
        'audio': audio,
        'title': track['title'] ?? '',
        'showTitle': track['showTitle'] ?? '',
        'artist': track['artist'] ?? '',
        'artwork': track['artwork'] ?? '',
        'duration': track['duration'] ?? '',
        'feedUrl': track['feedUrl'] ?? '',
        'kind': track['kind'] ?? '',
        'localPath': path,
      };
      await _persist();
      _clearProgress(audio);
      version.value++;
      return true;
    } catch (_) {
      _clearProgress(audio);
      return false;
    }
  }

  /// Deletes the offline copy (file + index entry).
  static Future<void> remove(String? audio) async {
    if (audio == null) return;
    final rec = _index.remove(audio);
    final path = (rec?['localPath'] ?? '').toString();
    if (path.isNotEmpty) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    await _persist();
    version.value++;
  }

  static void _setProgress(String audio, double v) {
    final m = Map<String, double>.from(progress.value);
    m[audio] = v.clamp(0, 1);
    progress.value = m;
  }

  static void _clearProgress(String audio) {
    final m = Map<String, double>.from(progress.value);
    m.remove(audio);
    progress.value = m;
  }
}
