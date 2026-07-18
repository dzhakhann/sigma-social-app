import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants.dart';
import 'api_service.dart';

/// Background story publishing, Telegram-style.
///
/// «Опубликовать» closes the editor INSTANTLY. The upload then runs inside an
/// Android FOREGROUND SERVICE (its own isolate + persistent notification), so
/// it survives not just backgrounding but swiping the app out of recents:
///  · the service notification shows live percent progress;
///  · [progress] drives the ring on the "Me" story avatar while the app is up;
///  · videos over ~8 MB are compressed first (ffmpeg, 720p / crf 26);
///  · on success the feed refreshes via [onPublished]; on failure [failed]
///    turns on and [retry] re-runs the same payload.
///
/// The pending job lives as ONE temp JSON file (+ the photo bytes for photo
/// stories); it is deleted the moment the story is created. If the service
/// can't start (odd OEM builds), the upload falls back to running in-process —
/// worse survivability, but publishing never silently breaks.
class StoryPublisher {
  StoryPublisher._();
  static final StoryPublisher instance = StoryPublisher._();

  /// null = idle · 0..1 = uploading. The home screen listens to this.
  final ValueNotifier<double?> progress = ValueNotifier(null);

  /// True when the last publish failed (shows the retry banner).
  final ValueNotifier<bool> failed = ValueNotifier(false);

  /// Called after a successful publish — home refreshes the stories row.
  VoidCallback? onPublished;

  bool _callbackHooked = false;
  bool _notifPermissionAsked = false;

  // Kept for the in-process fallback retry.
  String? _uploadingText, _doneText, _failText;

  static Future<String> _jobPath() async =>
      '${(await getTemporaryDirectory()).path}/story_upload_job.json';

  /// Receives events from the service isolate.
  void _hookCallback() {
    if (_callbackHooked) return;
    _callbackHooked = true;
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is! Map) return;
      if (data['p'] is num) {
        progress.value = ((data['p'] as num) / 100).clamp(0.0, 1.0);
      } else if (data['done'] == 1) {
        progress.value = null;
        failed.value = false;
        onPublished?.call();
      } else if (data['err'] == 1) {
        progress.value = null;
        failed.value = true;
      }
    });
  }

  /// Photo story. Returns immediately; work happens in the service.
  void publishPhoto(String userId, Uint8List bytes,
      {List<Map> links = const [],
      Map? music,
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _start(userId,
        photoBytes: bytes,
        links: links,
        music: music,
        uploadingText: uploadingText,
        doneText: doneText,
        failText: failText);
  }

  /// Video story (path to a local clip). Returns immediately.
  void publishVideo(String userId, String path,
      {List<Map> links = const [],
      Map? music,
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _start(userId,
        videoPath: path,
        links: links,
        music: music,
        uploadingText: uploadingText,
        doneText: doneText,
        failText: failText);
  }

  /// Re-runs the last failed publish (the job file survives failures).
  Future<void> retry(
      {String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) async {
    final job = File(await _jobPath());
    if (!job.existsSync()) return;
    failed.value = false;
    progress.value = 0;
    _hookCallback();
    await _launchService(uploadingText, doneText, failText);
  }

  Future<void> _start(
    String userId, {
    Uint8List? photoBytes,
    String? videoPath,
    required List<Map> links,
    Map? music,
    required String uploadingText,
    required String doneText,
    required String failText,
  }) async {
    failed.value = false;
    progress.value = 0;
    _hookCallback();
    _uploadingText = uploadingText;
    _doneText = doneText;
    _failText = failText;

    try {
      // Persist the job so the service isolate (and retry) can pick it up.
      final dir = await getTemporaryDirectory();
      String? photoPath;
      if (photoBytes != null) {
        photoPath = '${dir.path}/story_upload_photo.jpg';
        await File(photoPath).writeAsBytes(photoBytes);
      }
      final job = {
        'type': videoPath != null ? 'video' : 'photo',
        'path': videoPath ?? photoPath,
        'userId': userId,
        'links': links,
        if (music != null) 'music': music,
        'token': ApiService.token,
        'apiUrl': kApiUrl,
        'uploadingText': uploadingText,
        'doneText': doneText,
        'failText': failText,
      };
      await File(await _jobPath()).writeAsString(jsonEncode(job));

      await _launchService(uploadingText, doneText, failText);
    } catch (e) {
      debugPrint('story publish start failed: $e');
      progress.value = null;
      failed.value = true;
    }
  }

  Future<void> _launchService(
      String uploadingText, String doneText, String failText) async {
    // Android 13+ shows no notification without this permission.
    if (!_notifPermissionAsked) {
      _notifPermissionAsked = true;
      try {
        await Permission.notification.request();
      } catch (_) {}
    }

    if (kIsWeb || !Platform.isAndroid) {
      await _runInProcess();
      return;
    }

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'story_upload_service',
          channelName: 'Story upload',
          channelDescription: 'Publishing stories',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions:
            const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      await FlutterForegroundTask.startService(
        serviceId: 301,
        notificationTitle: uploadingText,
        notificationText: '0%',
        callback: storyUploadTaskCallback,
      );
    } catch (e) {
      // Some OEM builds refuse the service — publish in-process instead so the
      // story still goes out (just without swipe-away survival).
      debugPrint('foreground service unavailable, in-process fallback: $e');
      await _runInProcess();
    }
  }

  /// Fallback: same pipeline, executed in the app process.
  Future<void> _runInProcess() async {
    final ok = await runStoryUploadJob(
      onPercent: (p) => progress.value = (p / 100).clamp(0.0, 1.0),
      notify: (title, text) {},
    );
    if (ok) {
      progress.value = null;
      failed.value = false;
      await _showFinalNotification(_doneText ?? 'Story published');
      onPublished?.call();
    } else {
      progress.value = null;
      failed.value = true;
      await _showFinalNotification(_failText ?? 'Upload failed');
    }
  }

  Future<void> _showFinalNotification(String text) async {
    try {
      final n = FlutterLocalNotificationsPlugin();
      await n.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await n.show(
        7002,
        text,
        null,
        const NotificationDetails(
          android: AndroidNotificationDetails('story_upload', 'Story upload',
              channelDescription: 'Publishing stories'),
        ),
      );
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  The actual upload pipeline. Pure top-level function so BOTH the foreground
//  service isolate and the in-process fallback share one implementation.
//  Reads the job file; returns true on success (job file deleted then).
// ═══════════════════════════════════════════════════════════════════════════
Future<bool> runStoryUploadJob({
  required void Function(int percent) onPercent,
  required void Function(String title, String text) notify,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final jobFile = File('${dir.path}/story_upload_job.json');
    if (!jobFile.existsSync()) return false;
    final job =
        Map<String, dynamic>.from(jsonDecode(await jobFile.readAsString()));

    final isVideo = job['type'] == 'video';
    var path = (job['path'] ?? '').toString();
    if (path.isEmpty || !File(path).existsSync()) return false;

    // Compress big clips before shipping (720p, crf 26).
    if (isVideo) {
      final size = await File(path).length();
      if (size > 8 * 1024 * 1024) {
        final out = '${dir.path}/pub_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final r = await FFmpegKit.execute(
            '-y -i "$path" -vf "scale=-2:min(1280\\,ih)" '
            '-c:v libx264 -preset veryfast -crf 26 -c:a aac -b:a 128k "$out"');
        if (ReturnCode.isSuccess(await r.getReturnCode()) &&
            File(out).existsSync()) {
          path = out;
        }
      }
    }
    final bytes = await File(path).readAsBytes();

    // Upload with real byte progress.
    final token = (job['token'] ?? '').toString();
    final apiUrl = (job['apiUrl'] ?? '').toString();
    final dio = Dio();
    final body = jsonEncode({
      'file_base64': base64Encode(bytes),
      'folder': 'story',
      'ext': isVideo ? 'mp4' : 'jpg',
      'content_type': isVideo ? 'video/mp4' : 'image/jpeg',
      'user_id': job['userId'],
    });
    var lastShown = -1;
    final res = await dio.post(
      '$apiUrl/upload',
      data: body,
      options: Options(headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      }),
      onSendProgress: (sent, total) {
        if (total <= 0) return;
        final p = (sent / total * 100).round().clamp(0, 100);
        onPercent(p);
        if (p - lastShown >= 3) {
          lastShown = p;
          notify((job['uploadingText'] ?? 'Uploading story…').toString(), '$p%');
        }
      },
    );
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    if (data['success'] != true) return false;
    final url = (data['url'] ?? '').toString();
    if (url.isEmpty) return false;

    // Attach link/music extras and create the story record.
    final links = ((job['links'] as List?) ?? const [])
        .map((e) => Map.from(e))
        .toList();
    final music = job['music'] is Map ? Map.from(job['music']) : null;
    final packed = ApiService.packStoryExtras(url, links: links, music: music);
    final createRes = await dio.post(
      '$apiUrl/stories/upload',
      data: jsonEncode({'user_id': job['userId'], 'media_url': packed}),
      options: Options(headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      }),
    );
    final created =
        createRes.data is String ? jsonDecode(createRes.data) : createRes.data;
    if (created['success'] != true) return false;

    // Done — clean the job up.
    try { jobFile.deleteSync(); } catch (_) {}
    try {
      final photo = File('${dir.path}/story_upload_photo.jpg');
      if (photo.existsSync()) photo.deleteSync();
    } catch (_) {}
    return true;
  } catch (e) {
    debugPrint('story upload job failed: $e');
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Foreground service side.
// ═══════════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void storyUploadTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_StoryUploadHandler());
}

class _StoryUploadHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    String doneText = 'Story published';
    String failText = 'Upload failed';
    try {
      final dir = await getTemporaryDirectory();
      final jobFile = File('${dir.path}/story_upload_job.json');
      if (jobFile.existsSync()) {
        final job = jsonDecode(await jobFile.readAsString());
        doneText = (job['doneText'] ?? doneText).toString();
        failText = (job['failText'] ?? failText).toString();
      }
    } catch (_) {}

    final ok = await runStoryUploadJob(
      onPercent: (p) => FlutterForegroundTask.sendDataToMain({'p': p}),
      notify: (title, text) => FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text),
    );

    // Final state notification survives the service shutdown.
    try {
      final n = FlutterLocalNotificationsPlugin();
      await n.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await n.show(
        7002,
        ok ? doneText : failText,
        null,
        const NotificationDetails(
          android: AndroidNotificationDetails('story_upload', 'Story upload',
              channelDescription: 'Publishing stories'),
        ),
      );
    } catch (_) {}

    FlutterForegroundTask.sendDataToMain({ok ? 'done' : 'err': 1});
    await FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}
}
