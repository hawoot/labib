import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The daily streak with a rolling catch-up / bank-ahead window.
///
/// Model (all in units of "questions answered"):
///   • A daily goal `G` (default 5).
///   • A balance that tracks how far ahead (+) or behind (−) you are. Each day
///     that passes subtracts `G`; every answer adds 1. So doing exactly the
///     goal keeps the balance flat.
///   • A window `W` days (default 7). The balance is allowed to swing within
///     ±(W·G): you can **bank ahead** up to W days by doing extra now, and fall
///     **behind** up to W days and still catch up. Drop past −(W·G) — i.e. more
///     than a window behind — and the streak hard-resets.
///
/// With the defaults that's a two-week cushion (a week banked + a week to catch
/// up). Only the window length and goal are user-set (in Profile); everything
/// else is derived so Home can show a clear ahead/behind box.
class Streak {
  static const _kGoal = 'streak_goal';
  static const _kWindow = 'streak_window';
  static const _kBalance = 'streak_balance';
  static const _kAnchor = 'streak_anchor'; // yyyy-mm-dd of the current day
  static const _kToday = 'streak_today'; // answers counted on the anchor day
  static const _kDays = 'streak_days'; // closed-out streak length

  static const defaultGoal = 5;
  static const defaultWindow = 7;

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _dayGap(String fromYmd, DateTime to) {
    final parts = fromYmd.split('-').map(int.parse).toList();
    final from = DateTime(parts[0], parts[1], parts[2]);
    final today = DateTime(to.year, to.month, to.day);
    return today.difference(from).inDays;
  }

  // --- Settings ------------------------------------------------------------

  static Future<int> goal() async =>
      (await SharedPreferences.getInstance()).getInt(_kGoal) ?? defaultGoal;

  static Future<int> window() async =>
      (await SharedPreferences.getInstance()).getInt(_kWindow) ?? defaultWindow;

  static Future<void> setGoal(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kGoal, v.clamp(1, 100));

  static Future<void> setWindow(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kWindow, v.clamp(1, 60));

  // --- Core ----------------------------------------------------------------

  /// Roll the balance forward for any whole days that have elapsed since we last
  /// looked, applying the daily debit and resetting if we've fallen out of the
  /// window. Safe to call as often as we like.
  static Future<void> _rollover(SharedPreferences p) async {
    final goalV = p.getInt(_kGoal) ?? defaultGoal;
    final windowV = p.getInt(_kWindow) ?? defaultWindow;
    final cap = (windowV * goalV).toDouble();
    final now = DateTime.now();
    final anchor = p.getString(_kAnchor);

    if (anchor == null) {
      await p.setString(_kAnchor, _ymd(now));
      await p.setDouble(_kBalance, 0);
      await p.setInt(_kToday, 0);
      await p.setInt(_kDays, 0);
      return;
    }

    final gap = _dayGap(anchor, now);
    if (gap <= 0) return; // same day — nothing to close out

    var balance = p.getDouble(_kBalance) ?? 0;
    var days = p.getInt(_kDays) ?? 0;
    var todayCount = p.getInt(_kToday) ?? 0;

    // Away far longer than two windows? Definitely reset.
    if (gap > 2 * windowV) {
      balance = 0;
      days = 0;
    } else {
      for (var i = 0; i < gap; i++) {
        final dayCount = i == 0 ? todayCount : 0; // the anchor day, then idle days
        balance += dayCount - goalV;
        if (balance > cap) balance = cap; // can't bank past the window
        days += 1;
        if (balance < -cap) {
          // Fell more than a window behind — streak breaks, start fresh.
          balance = 0;
          days = 0;
        }
      }
    }

    await p.setString(_kAnchor, _ymd(now));
    await p.setDouble(_kBalance, balance);
    await p.setInt(_kDays, days);
    await p.setInt(_kToday, 0);
  }

  /// Count `n` answered questions toward today's goal / the running balance.
  static Future<void> recordAnswered(int n) async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    await p.setInt(_kToday, (p.getInt(_kToday) ?? 0) + n);
  }

  /// Current status for display.
  static Future<StreakStatus> status() async {
    final p = await SharedPreferences.getInstance();
    await _rollover(p);
    return StreakStatus(
      goal: p.getInt(_kGoal) ?? defaultGoal,
      window: p.getInt(_kWindow) ?? defaultWindow,
      streakDays: p.getInt(_kDays) ?? 0,
      todayCount: p.getInt(_kToday) ?? 0,
      startBalance: p.getDouble(_kBalance) ?? 0,
    );
  }
}

/// A snapshot of the streak, with everything Home needs to render the
/// on-track / banked (green) / behind (red) states.
class StreakStatus {
  StreakStatus({
    required this.goal,
    required this.window,
    required this.streakDays,
    required this.todayCount,
    required this.startBalance,
  });

  final int goal;
  final int window;
  final int streakDays;
  final int todayCount;

  /// Balance at the start of today (before today's answers).
  final double startBalance;

  /// Balance right now, including today's answers.
  double get liveBalance => startBalance + todayCount;

  bool get metToday => todayCount >= goal;

  /// Streak shown to the user — closed days plus today once the goal is met.
  int get displayStreak => streakDays + (metToday ? 1 : 0);

  /// Whole days you've banked ahead (green state) when > 0.
  int get bankedDays => liveBalance > 0 ? (liveBalance / goal).floor() : 0;

  /// Questions you're behind by right now (red state) when > 0.
  int get behindBy => liveBalance < 0 ? liveBalance.abs().ceil() : 0;

  bool get isAhead => bankedDays >= 1;
  bool get isBehind => behindBy >= 1;

  /// The day by which the behind-by questions must be answered before the
  /// streak resets (the balance hits −window·goal if you keep doing nothing).
  DateTime get catchUpBy {
    final cap = (window * goal).toDouble();
    final daysLeft = ((cap + liveBalance) / goal).floor();
    return DateTime.now().add(Duration(days: max(1, daysLeft)));
  }
}
