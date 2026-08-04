import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';
import 'notification_service.dart';

/// Runs in a separate, minimal background isolate — Android may invoke this
/// for a push that arrives while the app is fully killed, without ever
/// reaching MainScreen/PushService.init(), so it must be a standalone
/// top-level function (FlutterFire requirement) and re-initialize Firebase
/// itself. It just hands the data off to the same renderer the foreground
/// path uses, so a killed-app push and a live socket push look identical.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await NotificationService.showForNotification(message.data);
}

/// Registers this device for Firebase Cloud Messaging, so social-activity
/// notifications can wake the app even when it's killed — on top of the
/// live socket push (SocketService.onNotification) which only reaches an
/// app process that's still alive. See the notifications-architecture memory
/// for the full delivery-path design.
///
/// Entirely opt-in: until the Android app is actually wired to a real
/// Firebase project (google-services.json + the Gradle plugin applied),
/// `Firebase.apps` stays empty and this silently does nothing — no crash,
/// the socket-based path keeps working exactly as before.
class PushService {
  PushService._();

  // Web push needs its own key pair — Firebase Console → Project settings →
  // Cloud Messaging → Web configuration → "Generate key pair" under Web
  // Push certificates. This is separate from the app config in main.dart;
  // both are required before web push does anything.
  static const _webVapidKey = 'REPLACE_ME_VAPID_KEY';

  static Future<void> init() async {
    if (Firebase.apps.isEmpty) return;

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance
        .getToken(vapidKey: kIsWeb ? _webVapidKey : null);
    if (token != null) ApiService.saveFcmToken(token);
    FirebaseMessaging.instance.onTokenRefresh.listen(ApiService.saveFcmToken);

    // Background delivery on web is handled entirely by the service worker
    // (web/firebase-messaging-sw.js) — nothing else to wire up here. And
    // foreground pushes already arrive via the live socket
    // (SocketService.onNotification → MainScreen's in-app island), so
    // listening again here would just be a redundant second copy — one
    // that, on web, would throw anyway: NotificationService.showForNotification
    // renders through flutter_local_notifications, which has no web build.
    if (kIsWeb) return;

    // Foreground (native): render it ourselves, same path the socket push uses.
    FirebaseMessaging.onMessage
        .listen((msg) => NotificationService.showForNotification(msg.data));
  }
}
