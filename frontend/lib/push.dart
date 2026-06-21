import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';

/// Background isolate handler. Must be a top-level function. For a plain
/// notification message Android shows it automatically; we just need this
/// registered so data messages don't crash when the app is killed.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Nothing to do yet — the system tray shows notification messages for us.
}

/// Native push wiring: initialise Firebase, ask permission, get this device's
/// FCM token, and hand it to the backend so the engine can reach this phone.
///
/// Everything here is a no-op on web (Firebase isn't initialised there), so the
/// web build is unaffected.
class Push {
  static bool _started = false;

  /// Call once at startup, AFTER the user/account exists (so the token can be
  /// tied to the right user). Safe to call more than once.
  static Future<void> start() async {
    if (kIsWeb || _started) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

      final fm = FirebaseMessaging.instance;
      // Android 13+ shows a runtime permission prompt here; older versions
      // grant automatically.
      await fm.requestPermission();

      final token = await fm.getToken();
      if (token != null) {
        await Api.registerPushToken(token);
      }
      // The token can rotate; keep the backend in sync when it does.
      fm.onTokenRefresh.listen((t) {
        Api.registerPushToken(t);
      });
    } catch (e) {
      // Never let a push hiccup block app startup — it's a background nicety.
      debugPrint('Push.start failed: $e');
    }
  }
}
