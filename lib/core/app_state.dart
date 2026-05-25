/// Global application state singleton.
///
/// Manages all user-configurable settings (language, theme, font size,
/// mistake level, lookahead, blur mode) and exposes the active [ThemeColors]
/// palette. All UI widgets listen to this via [ChangeNotifier].
///
/// Design: Zero-persistence — settings reset on app restart.
/// This keeps the codebase dependency-free and startup instant.
library core.app_state;

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Supported UI languages.
enum AppLanguage { ar, en }

/// How strictly the matching engine penalizes mistakes.
enum MistakeLevel { none, easy, medium, hard }

/// Available color themes.
enum AppTheme { light, dark }

class AppState extends ChangeNotifier {
  AppState._() {
    // Initialize default language from the device's OS setting.
    final deviceLang = ui.PlatformDispatcher.instance.locale.languageCode;
    _lang = (deviceLang == 'ar') ? AppLanguage.ar : AppLanguage.en;
  }

  /// Singleton instance — accessed everywhere as `AppState.instance`.
  static final AppState instance = AppState._();

  // ── Language ───────────────────────────────────────────────────────────────

  late AppLanguage _lang;
  AppLanguage get lang => _lang;
  bool get isArabic => _lang == AppLanguage.ar;

  void toggleLanguage() {
    _lang = _lang == AppLanguage.ar ? AppLanguage.en : AppLanguage.ar;
    notifyListeners();
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  AppTheme _theme = AppTheme.light;
  AppTheme get theme => _theme;
  bool get isDarkMode => _theme == AppTheme.dark;

  void setTheme(AppTheme t) {
    _theme = t;
    notifyListeners();
  }

  // ── Blur Mode ──────────────────────────────────────────────────────────────

  bool isBlurMode = false;

  void toggleBlurMode() {
    isBlurMode = !isBlurMode;
    notifyListeners();
  }

  // ── Font Size ──────────────────────────────────────────────────────────────

  double fontSize = 28.0;

  void setFontSize(double size) {
    fontSize = size;
    notifyListeners();
  }

  // ── Mistake Level ──────────────────────────────────────────────────────────

  MistakeLevel mistakeLevel = MistakeLevel.medium;

  void setMistakeLevel(MistakeLevel level) {
    mistakeLevel = level;
    notifyListeners();
  }

  // ── Lookahead ──────────────────────────────────────────────────────────────

  int lookahead = 1;

  void setLookahead(int val) {
    lookahead = val;
    notifyListeners();
  }

  // ── Colors ─────────────────────────────────────────────────────────────────

  /// Returns the active color palette based on the current theme.
  ThemeColors get colors => isDarkMode ? _darkColors : _lightColors;

  static const ThemeColors _lightColors = ThemeColors(
    bg: Color(0xFFFAF9F6),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    gold: Color(0xFFB48600),
    green: Color(0xFF10B981),
    red: Color(0xFFF43F5E),
    muted: Color(0xFF64748B),
    currentWord: Color(0xFFE8A317),
  );

  static const ThemeColors _darkColors = ThemeColors(
    bg: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    border: Color(0xFF334155),
    gold: Color(0xFFD4A843),
    green: Color(0xFF34D399),
    red: Color(0xFFFB7185),
    muted: Color(0xFF94A3B8),
    currentWord: Color(0xFFFBBF24),
  );

  /// No-op — kept for API compatibility if persistence is added later.
  Future<void> load() async {}
}

/// Immutable color palette used by all UI widgets.
///
/// Each theme (light/dark) provides its own [ThemeColors] instance.
/// Widgets read colors via `AppState.instance.colors`.
class ThemeColors {
  final Color bg;
  final Color surface;
  final Color border;
  final Color gold;
  final Color green;
  final Color red;
  final Color muted;
  final Color currentWord;

  const ThemeColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.gold,
    required this.green,
    required this.red,
    required this.muted,
    required this.currentWord,
  });

  /// A faded version of gold for subtle backgrounds.
  Color get goldFade => gold.withValues(alpha: 0.25);

  /// A slightly elevated surface for badges and chips.
  Color get surfaceHigh => Color.lerp(surface, border, 0.5)!;

  /// Default text color — white on dark, dark slate on light.
  Color get text => bg.computeLuminance() < 0.5
      ? const Color(0xFFE2E8F0)
      : const Color(0xFF1E293B);
}
