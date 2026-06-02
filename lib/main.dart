import 'package:flutter/material.dart';
import 'constants.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const SigmaSocialApp());
}

class SigmaSocialApp extends StatelessWidget {
  const SigmaSocialApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sigma Social',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDark,
        primaryColor: kGold,
        colorScheme: const ColorScheme.dark(
          primary: kGold,
          surface: kCard,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kGold,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: Colors.black,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 4,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGold, width: 2)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: kBorder, width: 1)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGold, width: 2)),
          filled: true,
          fillColor: kCard,
          labelStyle: const TextStyle(color: kGold),
          hintStyle: const TextStyle(color: Colors.grey),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardTheme(
          color: kCard,
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: kDark,
          selectedItemColor: kGold,
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
