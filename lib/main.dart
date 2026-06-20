import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/brutal_theme.dart';
import 'services/session.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore a saved session so the user stays signed in across restarts.
  final savedUser = await Session.load();
  runApp(PulseApp(initialUser: savedUser));
}

/// Root widget. Rebuilds the entire MaterialApp whenever the user switches
/// theme or language from Settings, and exposes the active config to every
/// screen through [AppScope] + the active palette through ThemeData.
class PulseApp extends StatelessWidget {
  final Map? initialUser;
  const PulseApp({super.key, this.initialUser});

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
              title: 'Sigma Social',
              debugShowCheckedModeBanner: false,
              theme: buildBrutalTheme(theme),
              builder: (context, child) => _Responsive(child: child!),
              home: initialUser != null
                  ? MainScreen(user: initialUser!)
                  : const LoginScreen(),
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
