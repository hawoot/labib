import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_shell.dart';
import 'screens/landing_screen.dart';
import 'theme.dart';

void main() => runApp(const LabibApp());

class LabibApp extends StatelessWidget {
  const LabibApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'labib',
      debugShowCheckedModeBanner: false,
      theme: labibTheme(Brightness.light),
      darkTheme: labibTheme(Brightness.dark),
      // Dark is the primary look (matches the design direction). A light/dark
      // toggle can come later via settings.
      themeMode: ThemeMode.dark,
      home: const _Launcher(),
    );
  }
}

/// Decides the first screen: a returning device goes straight to its journeys;
/// a first-time visitor gets the landing screen.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Api.hasAccount(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0B0F),
            body: SizedBox.shrink(),
          );
        }
        return snap.data! ? const HomeShell() : const LandingScreen();
      },
    );
  }
}
