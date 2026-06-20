import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small local store for the choices that should NOT be asked every session:
///   • the last-used drill intensity (so "Let's go" is instant), and
///   • a temporary focus (a set of journeys for a limited time, set in Profile),
///     which auto-reverts once it expires so nothing gets orphaned.
class Prefs {
  static const _kIntensity = 'last_intensity';
  static const _kFocusIds = 'focus_journey_ids';
  static const _kFocusUntil = 'focus_until';

  // --- Intensity -----------------------------------------------------------

  /// Last intensity the user drilled with; defaults to 'on_the_go'.
  static Future<String> intensity() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kIntensity) ?? 'on_the_go';
  }

  static Future<void> setIntensity(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kIntensity, value);
  }

  // --- Temporary focus -----------------------------------------------------

  /// The journeys currently in focus, or empty if no (unexpired) focus is set.
  /// Expired focus is cleared as a side effect so it can't linger.
  static Future<List<String>> activeFocus() async {
    final p = await SharedPreferences.getInstance();
    final untilStr = p.getString(_kFocusUntil);
    if (untilStr == null) return const [];
    final until = DateTime.tryParse(untilStr);
    if (until == null || DateTime.now().isAfter(until)) {
      await clearFocus();
      return const [];
    }
    final raw = p.getString(_kFocusIds);
    if (raw == null) return const [];
    final list = (jsonDecode(raw) as List).cast<String>();
    return list;
  }

  /// When the active focus ends, or null if none.
  static Future<DateTime?> focusUntil() async {
    final p = await SharedPreferences.getInstance();
    final untilStr = p.getString(_kFocusUntil);
    if (untilStr == null) return null;
    final until = DateTime.tryParse(untilStr);
    if (until == null || DateTime.now().isAfter(until)) return null;
    return until;
  }

  static Future<void> setFocus(List<String> journeyIds, Duration forHowLong) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFocusIds, jsonEncode(journeyIds));
    await p.setString(
        _kFocusUntil, DateTime.now().add(forHowLong).toIso8601String());
  }

  static Future<void> clearFocus() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFocusIds);
    await p.remove(_kFocusUntil);
  }
}
