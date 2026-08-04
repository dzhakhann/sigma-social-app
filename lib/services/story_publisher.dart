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
      List<Map> gifs = const [],
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    // Web has no filesystem to persist a job file to (that mechanism exists
    // only to survive an Android foreground service restart) — upload the
    // bytes already in memory directly instead.
    if (kIsWeb) {
      _startWeb(userId,
          bytes: bytes,
          isVideo: false,
          links: links,
          music: music,
          gifs: gifs,
          doneText: doneText,
          failText: failText);
      return;
    }
    _start(userId,
        photoBytes: bytes,
        links: links,
        music: music,
        gifs: gifs,
        uploadingText: uploadingText,
        doneText: doneText,
        failText: failText);
  }

  /// Video story (path to a local clip). Native only — see [publishVideoBytes]
  /// for web, which has no filesystem path to give this.
  void publishVideo(String userId, String path,
      {List<Map> links = const [],
      Map? music,
      List<Map> gifs = const [],
      String uploadingText = 'Uploading story…',
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _start(userId,
        videoPath: path,
        links: links,
        music: music,
        gifs: gifs,
        uploadingText: uploadingText,
        doneText: doneText,
        failText: failText);
  }

  /// Video story from in-memory bytes — the web entry point. Skips
  /// compression (ffmpeg has no web build) and uploads the clip as captured.
  void publishVideoBytes(String userId, Uint8List bytes,
      {List<Map> links = const [],
      Map? music,
      List<Map> gifs = const [],
      String doneText = 'Story published',
      String failText = 'Upload failed'}) {
    _startWeb(userId,
        bytes: bytes,
        isVideo: true,
        links: links,
        music: music,
        gifs: gifs,
        doneText: doneText,
        failText: failText);
  }

  /// Web publish path: no job file, no foreground service, no ffmpeg — just
  /// the bytes already held in memory, uploaded directly.
  Future<void> _startWeb(
    String userId, {
    required Uint8List bytes,
    required bool isVideo,
    required List<Map> links,
    Map? music,
    List<Map> gifs = const [],
    required String doneText,
    required String failText,
  }) async {
    failed.value = false;
    progress.value = 0;
    try {
      final err = await uploadAndCreateStory(
        bytes: bytes,
        isVideo: isVideo,
        userId: userId,
        token: ApiService.token ?? '',
        apiUrl: kApiUrl,
        links: links,
        music: music,
        gifs: gifs,
        onPercent: (p) => progress.value = (p / 100).clamp(0.0, 1.0),
        notify: (_, __) {},
      );
      progress.value = null;
      if (err == null) {
        failed.value = false;
        onPublished?.call();
      } else {
        failed.value = true;
        debugPrint('web story publish failed: $err');
      }
    } catch (e) {
      progress.value = null;
      failed.value = true;
      debugPrint('web story publish failed: $e');
    }
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
    List<Map> gifs = const [],
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
        if (gifs.isNotEmpty) 'gifs': gifs,
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
    final err = await runStoryUploadJob(
      onPercent: (p) => progress.value = (p / 100).clamp(0.0, 1.0),
      notify: (title, text) {},
    );
    if (err == null) {
      progress.value = null;
      failed.value = false;
      await _showFinalNotification(_doneText ?? 'Story published');
      onPublished?.call();
    } else {
      progress.value = null;
      failed.value = true;
      await _showFinalNotification('${_failText ?? 'Upload failed'} · $err');
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
/// Runs the pending upload job. Returns `null` on success, or a short human
/// reason on failure (shown in the notification so a failing publish is
/// diagnosable instead of a generic "Upload failed").
Future<String?> runStoryUploadJob({
  required void Function(int percent) onPercent,
  required void Function(String title, String text) notify,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final jobFile = File('${dir.path}/story_upload_job.json');
    if (!jobFile.existsSync()) return 'no job';
    final job =
        Map<String, dynamic>.from(jsonDecode(await jobFile.readAsString()));

    final isVideo = job['type'] == 'video';
    var path = (job['path'] ?? '').toString();
    if (path.isEmpty || !File(path).existsSync()) return 'media file missing';

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

    final gifs = ((job['gifs'] as List?) ?? const [])
        .map((e) => Map.from(e))
        .toList();
    final links = ((job['links'] as List?) ?? const [])
        .map((e) => Map.from(e))
        .toList();
    final music = job['music'] is Map ? Map.from(job['music']) : null;

    final err = await uploadAndCreateStory(
      bytes: bytes,
      isVideo: isVideo,
      userId: (job['userId'] ?? '').toString(),
      token: (job['token'] ?? '').toString(),
      apiUrl: (job['apiUrl'] ?? '').toString(),
      links: links,
      music: music,
      gifs: gifs,
      onPercent: onPercent,
      notify: (title, text) => notify(
          title.isEmpty ? (job['uploadingText'] ?? 'Uploading story…').toString() : title,
          text),
    );
    if (err != null) return err;

    // Done — clean the job up.
    try { jobFile.deleteSync(); } catch (_) {}
    try {
      final photo = File('${dir.path}/story_upload_photo.jpg');
      if (photo.existsSync()) photo.deleteSync();
    } catch (_) {}
    return null;
  } catch (e) {
    debugPrint('story upload job failed: $e');
    return _short(e);
  }
}

/// Shared upload + story-creation core: uploads media bytes, then creates the
/// story record with link/music/GIF extras attached. Used by the native
/// job-file pipeline above (bytes read from a temp file, ffmpeg-compressed if
/// large) and by [StoryPublisher._startWeb] (bytes already held in memory —
/// web has neither a temp filesystem nor ffmpeg to compress with).
Future<String?> uploadAndCreateStory({
  required Uint8List bytes,
  required bool isVideo,
  required String userId,
  required String token,
  required String apiUrl,
  required List<Map> links,
  Map? music,
  required List<Map> gifs,
  required void Function(int percent) onPercent,
  required void Function(String title, String text) notify,
}) async {
  try {
    // Generous timeouts: on a cold free-tier server + slow mobile data the very
    // first byte can take a while. No receiveTimeout so a slow reply won't abort.
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(minutes: 3),
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ));

    final body = jsonEncode({
      'file_base64': base64Encode(bytes),
      'folder': 'story',
      'ext': isVideo ? 'mp4' : 'jpg',
      'content_type': isVideo ? 'video/mp4' : 'image/jpeg',
      'user_id': userId,
    });

    // Upload the media (retry once — mobile networks drop the first attempt).
    dynamic data;
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        var lastShown = -1;
        final res = await dio.post(
          '$apiUrl/upload',
          data: body,
          onSendProgress: (sent, total) {
            if (total <= 0) return;
            final p = (sent / total * 100).round().clamp(0, 100);
            onPercent(p);
            if (p - lastShown >= 3) {
              lastShown = p;
              notify('', '$p%');
            }
          },
        );
        data = res.data is String ? jsonDecode(res.data) : res.data;
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) return 'upload: ${_short(lastErr)}';
    if (data == null || data['success'] != true) {
      return 'upload: ${data?['error'] ?? 'server rejected'}';
    }
    final url = (data['url'] ?? '').toString();
    if (url.isEmpty) return 'upload: no url';

    // Attach link/music/GIF extras and create the story record.
    final packed =
        ApiService.packStoryExtras(url, links: links, music: music, gifs: gifs);
    dynamic created;
    lastErr = null;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final createRes = await dio.post(
          '$apiUrl/stories/upload',
          data: jsonEncode({'user_id': userId, 'media_url': packed}),
        );
        created =
            createRes.data is String ? jsonDecode(createRes.data) : createRes.data;
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) return 'create: ${_short(lastErr)}';
    if (created == null || created['success'] != true) {
      return 'create: ${created?['error'] ?? 'server rejected'}';
    }
    return null;
  } catch (e) {
    debugPrint('story upload job failed: $e');
    return _short(e);
  }
}

/// Trims Dio/exception noise to something readable in a notification.
String _short(Object e) {
  var s = e.toString();
  if (e is DioException) {
    s = e.response?.statusCode != null
        ? 'HTTP ${e.response!.statusCode}'
        : e.type.name;
  }
  return s.length > 80 ? s.substring(0, 80) : s;
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

    final err = await runStoryUploadJob(
      onPercent: (p) => FlutterForegroundTask.sendDataToMain({'p': p}),
      notify: (title, text) => FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text),
    );
    final ok = err == null;

    // Final state notification survives the service shutdown.
    try {
      final n = FlutterLocalNotificationsPlugin();
      await n.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await n.show(
        7002,
        ok ? doneText : '$failText · $err',
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
