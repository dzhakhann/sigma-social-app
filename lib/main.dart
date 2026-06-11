import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/brutal_theme.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
              title: 'Pulse',
              debugShowCheckedModeBanner: false,
              theme: buildBrutalTheme(theme),
              home: const LoginScreen(),
            ),
          ),
        );
      },
    );
  }
}
