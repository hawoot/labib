import 'package:flutter/material.dart';

import '../theme.dart';

/// A shared push transition for the whole app: the incoming screen slides up a
/// touch and fades in, the outgoing one fades back. Calmer and more "native"
/// than the default platform swap, and consistent across pushes.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, RouteSettings? settings})
      : super(
          settings: settings,
          transitionDuration: Motion.medium,
          reverseTransitionDuration: Motion.fast,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Motion.emphasized,
              reverseCurve: Motion.curve,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
