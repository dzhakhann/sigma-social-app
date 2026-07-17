import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants.dart';
import 'api_service.dart';

/// Background story publishing (Пункт 5, Telegram-style).
///
/// «Опубликовать» closes the editor INSTANTLY; the upload continues here:
///  · an Android notification shows live percent progress;
///  · [progress] drives the in-app ring on the "Me" story avatar;
///  · videos over ~8 MB are compressed first (ffmpeg, 720p / crf 26);
///  · on success the feed refreshes via [onPublished]; on failure [failed]
///    turns on and [retry] re-runs the same payload.
///
/// Nothing extra is stored: temp files are deleted after upload, the payload
/// lives only in memory for retry.
class StoryPublisher {
  StoryPublisher._();
  static final StoryPublisher instance = StoryPublisher._();

  /// null = idle · 0..1 = uploading. The home screen listens to this.
  final ValueNotifier<double?> progress = ValueNotifier(null);

  /// True when the last publish failed (shows the retry banner).
  final ValueNotifier<bool> failed = ValueNotifier(false);

  /// Called after a successful publish — home refreshes the stories row.
  VoidCallback? onPublished;

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _notifReady = false;
  static const _notifId = 7001;

  // Retry payload (memory only).
  String? _userId;
  Uint8List? _photoBytes;
  String? _videoPath;
  List<Map> _links = const [];

  Future<void> _initNotifications() async {
    if (_notifReady) return;
    try {
      await _notifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      // Android 13+ shows nothing without this permission.
      await Permission.notification.request();
      _notifReady = true;
    } catch (_) {}
  }

  Future<void> _notifyProgress(int percent, String title) async {
    if (!_notifReady) return;
    try {
      await _notifications.show(
        _notifId,
        title,
        '$percent%',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'story_upload',
            'Story upload',
            channelDescription: 'Publishing stories',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
            ongoing: true,
            autoCancel: false,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _notifyDone(String text, {bool ok = true}) async {
    if (!_notifReady) return;
    try {
      await _notifications.cancel(_notifId);
      await _notifications.show(
        _notifId + 1,
        text,
        null,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'story_upload',
            'Story upload',
            channelDescription: 'Publishing stories',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Photo story. Returns immediately; work happens in the background.
  void publishPhoto(String userId, Uint8List bytes,
      {List<Map> links = const [],
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _userId = userId;
    _photoBytes = bytes;
    _videoPath = null;
    _links = links;
    _run(uploadingText, doneText, failText);
  }

  /// Video story (path to a local clip). Returns immediately.
  void publishVideo(String userId, String path,
      {List<Map> links = const [],
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _userId = userId;
    _photoBytes = null;
    _videoPath = path;
    _links = links;
    _run(uploadingText, doneText, failText);
  }

  /// Re-runs the last failed publish.
  void retry(
      {String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    if (_userId == null) return;
    _run(uploadingText, doneText, failText);
  }

  Future<void> _run(String uploadingText, String doneText, String failText) async {
    failed.value = false;
    progress.value = 0;
    await _initNotifications();
    await _notifyProgress(0, uploadingText);
    try {
      final isVideo = _videoPath != null;
      List<int> bytes;
      if (isVideo) {
        final path = await _maybeCompress(_videoPath!);
        bytes = await File(path).readAsBytes();
      } else {
        bytes = _photoBytes!;
      }

      // Upload with real byte progress (dio reports the request body bytes).
      final url = await _uploadWithProgress(
        bytes,
        ext: isVideo ? 'mp4' : 'jpg',
        contentType: isVideo ? 'video/mp4' : 'image/jpeg',
        onPercent: (p) {
          progress.value = p / 100;
          if (p % 3 == 0) _notifyProgress(p, uploadingText);
        },
      );
      if (url == null) throw Exception('upload failed');

      final withLinks = ApiService.packStoryLinks(url, _links);
      final r = await ApiService.createStoryFromUrl(_userId!, withLinks);
      if (r['success'] != true) throw Exception('story create failed');

      progress.value = null;
      await _notifyDone(doneText);
      onPublished?.call();
    } catch (_) {
      progress.value = null;
      failed.value = true;
      await _notifyDone(failText, ok: false);
    }
  }

  /// Compress a big clip before upload: 720p, crf 26. Small files skip this.
  Future<String> _maybeCompress(String path) async {
    try {
      final size = await File(path).length();
      if (size < 8 * 1024 * 1024) return path;
      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/pub_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final r = await FFmpegKit.execute(
          '-y -i "$path" -vf "scale=-2:min(1280\\,ih)" '
          '-c:v libx264 -preset veryfast -crf 26 -c:a aac -b:a 128k "$out"');
      if (ReturnCode.isSuccess(await r.getReturnCode()) &&
          File(out).existsSync()) {
        return out;
      }
    } catch (_) {}
    return path;
  }

  /// POST /api/upload (base64 JSON — the server's format) via dio so we get
  /// onSendProgress percent for the notification.
  Future<String?> _uploadWithProgress(
    List<int> bytes, {
    required String ext,
    required String contentType,
    required void Function(int percent) onPercent,
  }) async {
    try {
      final dio = Dio();
      final body = jsonEncode({
        'file_base64': base64Encode(bytes),
        'folder': 'story',
        'ext': ext,
        'content_type': contentType,
        'user_id': _userId,
      });
      final res = await dio.post(
        '$kApiUrl/upload',
        data: body,
        options: Options(headers: {
          'Content-Type': 'application/json',
          if (ApiService.token != null)
            'Authorization': 'Bearer ${ApiService.token}',
        }),
        onSendProgress: (sent, total) {
          if (total > 0) onPercent((sent / total * 100).round().clamp(0, 100));
        },
      );
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      if (data['success'] == true) return (data['url'] ?? '').toString();
    } catch (_) {}
    return null;
  }
}
