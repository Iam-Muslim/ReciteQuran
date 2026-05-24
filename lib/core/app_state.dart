/// Global application state: Hardcoded colors and RTL logic.
///
/// Freed from settings options and persistence.
library core.app_state;

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Supported UI languages
enum AppLanguage { ar, en }

enum MistakeLevel { none, easy, medium, hard }

class AppState extends ChangeNotifier {
  AppState._() {
    // Initialize default language from Android OS
    final deviceLang = ui.PlatformDispatcher.instance.locale.languageCode;
    _lang = (deviceLang == 'ar') ? AppLanguage.ar : AppLanguage.en;
  }

  static final AppState instance = AppState._();

  late AppLanguage _lang;
  AppLanguage get lang => _lang;
  bool get isArabic => _lang == AppLanguage.ar;

  void toggleLanguage() {
    _lang = _lang == AppLanguage.ar ? AppLanguage.en : AppLanguage.ar;
    notifyListeners();
  }

  bool isBlurMode = false;

  void toggleBlurMode() {
    isBlurMode = !isBlurMode;
    notifyListeners();
  }

  double fontSize = 28.0;

  void increaseFontSize() {
    if (fontSize < 50) {
      fontSize += 2;
      notifyListeners();
    }
  }

  void decreaseFontSize() {
    if (fontSize > 16) {
      fontSize -= 2;
      notifyListeners();
    }
  }

  void setFontSize(double size) {
    fontSize = size;
    notifyListeners();
  }

  FontWeight fontWeight = FontWeight.w400; // Default to Bold

  void setFontWeight(FontWeight weight) {
    fontWeight = weight;
    notifyListeners();
  }

  MistakeLevel mistakeLevel = MistakeLevel.medium;

  void setMistakeLevel(MistakeLevel level) {
    mistakeLevel = level;
    notifyListeners();
  }

  int lookahead = 1;

  void setLookahead(int val) {
    lookahead = val;
    notifyListeners();
  }

  // Dark mode is permanently disabled
  bool get isDarkMode => false;

  ThemeColors get colors => const ThemeColors(
    bg: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    gold: Color(0xFFB48600), // Darker gold for light mode
    green: Color(0xFF059669),
    red: Color(0xFFDC2626),
    muted: Color(0xFF64748B),
  );

  Future<void> load() async {
    // No-op after removing settings persistence
  }
}

class ThemeColors {
  final Color bg;
  final Color surface;
  final Color border;
  final Color gold;
  final Color green;
  final Color red;
  final Color muted;

  const ThemeColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.gold,
    required this.green,
    required this.red,
    required this.muted,
  });

  Color get goldFade => gold.withValues(alpha: 0.25);
  Color get surfaceHigh => Color.lerp(surface, border, 0.5)!;
}
