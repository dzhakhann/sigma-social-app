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
