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

// Tracking Strictness: Easy (relaxed), Normal (default), Strict (anchor both ends)
enum TrackingStrictness { easy, normal, strict }

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




  int autoScrollSpeed = 2; // 2 = 1.0x (index in new array)

  void setAutoScrollSpeed(int speed) async {
    autoScrollSpeed = speed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoScrollSpeed', autoScrollSpeed);
  }

  // ── Tracking Strictness ───────────────────────────────────────────────────

  TrackingStrictness trackingStrictness = TrackingStrictness.normal;

  void setTrackingStrictness(TrackingStrictness strictness) async {
    if (trackingStrictness != strictness) {
      trackingStrictness = strictness;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trackingStrictness', trackingStrictness.name);
    }
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

  // ──────────────────────────────────────────────────────────────────────────
  // LIGHT THEME — Warm Ivory / Cream
  // Inspired by classic Mushaf paper tones. Eye-comfortable for long reading.
  // ──────────────────────────────────────────────────────────────────────────
  static const ThemeColors _lightColors = ThemeColors(
    bg: Color(0xFFFAF6F0),          // Warm ivory/cream — like Mushaf paper
    surface: Color(0xFFFFFDF8),      // Slightly brighter cream for cards
    border: Color(0xFFE8DFD3),       // Warm tan border
    gold: Color(0xFFB8860B),         // Deep warm gold — Islamic heritage
    green: Color(0xFF2E8B57),        // Sea green — softer than emerald
    red: Color(0xFFCD5C5C),          // Indian red — softer, less alarming
    muted: Color(0xFF8B7D6B),        // Warm grey-brown
    currentWord: Color(0xFFDAA520),   // Goldenrod — warm amber highlight
    text: Color(0xFF2C1810),          // Deep warm brown — easier on eyes than black
    surfaceHigh: Color(0xFFF2EDE5),  // Elevated cream
  );

  // ──────────────────────────────────────────────────────────────────────────
  // DARK THEME — Deep Warm Black
  // AMOLED-friendly but never harsh. Warm undertones reduce eye strain.
  // ──────────────────────────────────────────────────────────────────────────
  static const ThemeColors _darkColors = ThemeColors(
    bg: Color(0xFF0A0806),          // Very deep warm black (not pure #000)
    surface: Color(0xFF141210),      // Slightly elevated warm surface
    border: Color(0xFF2A2520),       // Warm dark border
    gold: Color(0xFFDAA520),         // Goldenrod — warm & visible on dark
    green: Color(0xFF3CB371),        // Medium sea green — readable on dark
    red: Color(0xFFE07070),          // Soft red — not harsh on dark bg
    muted: Color(0xFF9A8F82),        // Warm muted
    currentWord: Color(0xFFF0C050),  // Bright goldenrod
    text: Color(0xFFF0E6D6),         // Warm off-white — never pure white
    surfaceHigh: Color(0xFF1E1A16),  // Elevated warm dark
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



      autoScrollSpeed = prefs.getInt('autoScrollSpeed') ?? 2;
      fontSize = prefs.getDouble('fontSize') ?? 28.0;

      if (prefs.containsKey('trackingStrictness')) {
        final s = prefs.getString('trackingStrictness');
        if (s == 'easy') trackingStrictness = TrackingStrictness.easy;
        else if (s == 'strict') trackingStrictness = TrackingStrictness.strict;
        else trackingStrictness = TrackingStrictness.normal;
      }

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
