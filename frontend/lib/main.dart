import 'package:flutter/material.dart';

import 'screens/journeys_screen.dart';

void main() => runApp(const LabibApp());

class LabibApp extends StatelessWidget {
  const LabibApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'labib',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B6CFF),
        useMaterial3: true,
      ),
      home: const JourneysScreen(),
    );
  }
}
