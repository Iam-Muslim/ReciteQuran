// Global application state singleton.
//
// Manages all user-configurable settings (language, theme, font size,
// mistake level, lookahead, blur mode) and exposes the active [ThemeColors]
// palette. All UI widgets listen to this via [ChangeNotifier].
//
// Design: Zero-persistence — settings reset on app restart.
// This keeps the codebase dependency-free and startup instant.

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';

// Supported UI languages.
enum AppLanguage { ar, en }

// Application Mode: Word Checker (Sherpa) vs Tajweed (Muaalem)
enum AppMode { wordChecker, tajweed }

// Available color themes.
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

  void toggleLanguage() async {
    _lang = _lang == AppLanguage.ar ? AppLanguage.en : AppLanguage.ar;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', _lang.name);
  }

  // ── Mode ───────────────────────────────────────────────────────────────────

  AppMode currentMode = AppMode.wordChecker;

  void setMode(AppMode mode) {
    if (currentMode != mode) {
      currentMode = mode;
      notifyListeners();
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  AppTheme _theme = AppTheme.light;
  AppTheme get theme => _theme;
  bool get isDarkMode => _theme == AppTheme.dark;

  void setTheme(AppTheme t) async {
    _theme = t;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', _theme.name);
  }

  // ── Blur Mode ──────────────────────────────────────────────────────────────

  bool isBlurMode = false;

  void toggleBlurMode() async {
    isBlurMode = !isBlurMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('blurMode', isBlurMode);
  }

  // ── Lookahead Mode ─────────────────────────────────────────────────────────

  bool isLookaheadEnabled = true;

  void toggleLookahead() async {
    isLookaheadEnabled = !isLookaheadEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lookahead', isLookaheadEnabled);
  }

  int autoScrollSpeed = 1; // 1 = 1x, 2 = 2x

  void setAutoScrollSpeed(int speed) async {
    autoScrollSpeed = speed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoScrollSpeed', autoScrollSpeed);
  }

  // ── Font Size ──────────────────────────────────────────────────────────────

  double fontSize = 28.0;

  void setFontSize(double size) async {
    fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', fontSize);
  }

  // ── Colors ─────────────────────────────────────────────────────────────────

  /// Returns the active color palette based on the current theme.
  ThemeColors get colors => isDarkMode ? _darkColors : _lightColors;

  static const ThemeColors _lightColors = ThemeColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    gold: Color(0xFFD97706),
    green: Color(0xFF10B981),
    red: Color(0xFFEF4444),
    muted: Color(0xFF64748B),
    currentWord: Color(0xFFF59E0B),
    text: Color(0xFF1E293B),
    // 50% lerp of surface(0xFFFFFFFF) and border(0xFFE2E8F0)
    surfaceHigh: Color(0xFFF1F4F8),
  );

  static const ThemeColors _darkColors = ThemeColors(
    bg: Color(0xFF000000), // Pure AMOLED Black
    surface: Color(0xFF000000), // Match bg
    border: Color(0xFF2A2A2A), // Subtle borders
    gold: Color(0xFFD97706), // Kept orange from white mode
    green: Color(0xFF10B981), // Rich Emerald
    red: Color(0xFFEF4444), // Bright Red
    muted: Color(0xFFA1A1AA), // Light muted grey
    currentWord: Color(0xFFF59E0B), // Kept orange highlight from white mode
    text: Color(0xFFE2E8F0),
    // 50% lerp of surface(0xFF000000) and border(0xFF2A2A2A)
    surfaceHigh: Color(0xFF151515),
  );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.containsKey('lang')) {
        _lang = prefs.getString('lang') == 'en'
            ? AppLanguage.en
            : AppLanguage.ar;
      }
      if (prefs.containsKey('theme')) {
        _theme = prefs.getString('theme') == 'dark'
            ? AppTheme.dark
            : AppTheme.light;
      }
      isBlurMode = prefs.getBool('blurMode') ?? false;
      isLookaheadEnabled = prefs.getBool('lookahead') ?? true;
      autoScrollSpeed = prefs.getInt('autoScrollSpeed') ?? 1;
      fontSize = prefs.getDouble('fontSize') ?? 28.0;

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }
}

// Immutable color palette used by all UI widgets.
//
// Each theme (light/dark) provides its own [ThemeColors] instance.
// Widgets read colors via `AppState.instance.colors`.
class ThemeColors {
  final Color bg;
  final Color surface;
  final Color border;
  final Color gold;
  final Color green;
  final Color red;
  final Color muted;
  final Color currentWord;
  final Color text;

  /// Pre-computed elevated surface color — avoids Color.lerp() allocation on every build.
  final Color surfaceHigh;

  const ThemeColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.gold,
    required this.green,
    required this.red,
    required this.muted,
    required this.currentWord,
    required this.text,
    required this.surfaceHigh,
  });

  /// A faded version of gold for subtle backgrounds.
  Color get goldFade => gold.withValues(alpha: 0.25);
}
