import 'package:flutter/material.dart';

import 'screens/journeys_screen.dart';
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
      themeMode: ThemeMode.system,
      home: const JourneysScreen(),
    );
  }
}
