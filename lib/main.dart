import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'theme/brutal_theme.dart';
import 'screens/splash_screen.dart';
import 'services/deep_links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Channel between the UI and the story-upload foreground service.
  FlutterForegroundTask.initCommunicationPort();
  // Load saved language (default = English) before the first frame.
  await loadAppConfig();
  // Enables background audio + lock-screen / notification controls for podcasts.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sigmacta.audio',
      androidNotificationChannelName: 'Sigmacta',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  DeepLinks.init();
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
              builder: (context, child) => _Responsive(child: child!),
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
