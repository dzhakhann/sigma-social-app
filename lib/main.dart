import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/billing.dart';
import 'services/notification_prefs.dart';
import 'theme/brutal_theme.dart';
import 'theme/theme_effects.dart';
import 'screens/splash_screen.dart';
import 'services/deep_links.dart';
import 'services/install_referrer.dart';
import 'services/catalog_cache.dart';
import 'services/download_store.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Channel between the UI and the story-upload foreground service. Uses
  // dart:isolate under the hood, which doesn't exist on web — calling it
  // there throws before runApp(), killing the entire web app on every load.
  if (!kIsWeb) FlutterForegroundTask.initCommunicationPort();
  // Load saved language (default = English) before the first frame.
  await loadAppConfig();
  // Notification switches must be in memory before any push/socket event can
  // arrive, otherwise the first notification ignores the user's choices.
  await NotificationPrefs.load();
  // Russian relative dates ("5 минут назад") for timeago everywhere.
  timeago.setLocaleMessages('ru', timeago.RuMessages());
  // Enables background audio + lock-screen / notification controls for podcasts.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sigmacta.audio',
      androidNotificationChannelName: 'Sigmacta',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  // Firebase Cloud Messaging: no-ops safely until the app is actually wired
  // to a Firebase project (google-services.json + Gradle plugin) — see
  // PushService. Must be registered here, before runApp, because Android can
  // invoke pushBackgroundHandler in a separate isolate that never reaches
  // the widget tree at all.
  try {
    if (kIsWeb) {
      // Unlike native (which reads google-services.json / GoogleService-
      // Info.plist automatically), web has no config file to discover — it
      // has to be given explicitly, or this throws and every push feature
      // below silently stays off.
      //
      // Get these from Firebase Console → Project settings → General →
      // scroll to "Your apps" → Web app (add one if there isn't one yet) →
      // SDK setup and configuration → Config:
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'REPLACE_ME',
          appId: 'REPLACE_ME',
          messagingSenderId: 'REPLACE_ME',
          projectId: 'sigmacta-67de6',
          authDomain: 'sigmacta-67de6.firebaseapp.com',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
  } catch (_) {}
  DeepLinks.init();
  // Recovers the link followed BEFORE the app was installed. Must run before
  // any routing so the parked link is in place by the time a session exists.
  InstallReferrer.check();
  // Started before the UI: Play can deliver a purchase LATER (payment pending,
  // or an interrupted checkout completing on the next launch), and a purchase
  // arriving with nothing listening is money taken without entitlement given.
  Billing.init();
  // Wake the (free-tier) backend early so podcast/audiobook catalogs are warm
  // by the time the user opens "Ритм".
  ApiService.warmUp();
  // Load the offline-downloads index so playback can use local files.
  await DownloadStore.init();
  // Catalog disk cache — Rhythm tabs open instantly from the last good copy.
  await CatalogCache.init();
  runApp(const PulseApp());
}

/// Root widget. Rebuilds the entire MaterialApp whenever the user switches
/// theme or language from Settings, and exposes the active config to every
/// screen through [AppScope] + the active palette through ThemeData.
class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppConfig>(
      valueListenable: appConfig,
      builder: (context, config, _) {
        final theme = config.theme;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                theme.c.isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                theme.c.isDark ? Brightness.dark : Brightness.light,
          ),
          child: AppScope(
            config: config,
            child: MaterialApp(
              title: 'Sigmacta',
              navigatorKey: DeepLinks.navKey,
              debugShowCheckedModeBanner: false,
              theme: buildBrutalTheme(theme),
              // Per-theme ambience sits above every screen but below no
              // dialogs — wrapping here rather than per-screen means a new
              // screen gets it for free and can never forget to.
              builder: (context, child) => ThemeEffectsOverlay(
                style: effectStyleFor(theme.id),
                colors: theme.c,
                child: _Responsive(child: child!),
              ),
              home: const SplashScreen(),
            ),
          ),
        );
      },
    );
  }
}

/// On phones the app fills the screen. On wide screens (PC/tablet) it is
/// centred in a phone-width column on a dark backdrop — so links open looking
/// like a polished app, not a stretched page. MediaQuery is overridden inside
/// the frame so every screen lays itself out as a phone.
class _Responsive extends StatelessWidget {
  final Widget child;
  const _Responsive({required this.child});

  static const double _frameWidth = 460;
  static const double _breakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    if (size.width < _breakpoint) return child;

    final bg = Theme.of(context).extension<BrutalColors>()?.bg ??
        const Color(0xFF0F1015);

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: SizedBox(
          width: _frameWidth,
          height: size.height,
          child: DecoratedBox(
            decoration: BoxDecoration(color: bg, boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 40,
                  spreadRadius: 4),
            ]),
            child: MediaQuery(
              data: media.copyWith(size: Size(_frameWidth, size.height)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
