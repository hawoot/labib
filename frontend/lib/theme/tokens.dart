import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for shape, spacing, and motion.
///
/// Personality: **sharp & modern** (Linear / Revolut energy) with a violet
/// accent. That means tight radii, crisp hairline borders, restrained colour,
/// and deliberate motion — never bouncy or decorative for its own sake.

/// Brand accent: an electric violet. Used sparingly on a mostly-neutral UI.
const Color brandSeed = Color(0xFF6D4AFF);

/// 8pt spacing scale (with a 4pt subdivision). Use these instead of magic
/// numbers so the whole app shares one rhythm.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii — tighter than Material defaults for a sharper, modern look.
abstract final class Radii {
  static const double card = 14;
  static const double control = 12;
  static const double chip = 8;
  static const double sheet = 24;
}

/// Motion timing. <100ms reads as instant; 150–250ms feedback; 250–360ms
/// transitions. We favour ease-out (asymmetric) curves — never linear.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// Semantic status colours that adapt to light/dark, instead of raw
/// `Colors.green`/`Colors.orange` (which look unpolished in dark mode).
class StatusPalette {
  const StatusPalette(this.brightness);
  final Brightness brightness;

  bool get _dark => brightness == Brightness.dark;

  Color get success => _dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  Color get warning => _dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get info => _dark ? const Color(0xFF8B79FF) : brandSeed;
  Color get neutral => _dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
}
