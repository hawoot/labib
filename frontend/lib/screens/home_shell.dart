import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'journeys_screen.dart';
import 'profile_tab.dart';
import 'progress_tab.dart';

/// The signed-in app shell: Home · Progress · Profile, with the bottom nav.
///
/// Studying isn't a tab — it's the big action ("Let's go") that lives on Home.
/// An [IndexedStack] keeps each tab's state and scroll position alive as you
/// switch between them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    JourneysScreen(),
    ProgressTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == _index) return;
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
