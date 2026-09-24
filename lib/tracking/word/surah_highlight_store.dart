// lib/tracking/word/surah_highlight_store.dart
//
// Per-surah, per-ayah word highlight bookkeeping used by
// [HighlightingController].
//
// Kept separate from the controller — and from its ASR engine / background
// isolate wiring — so the part that actually decides what gets kept or
// erased when the tracked surah changes is a plain, synchronous, unit
// -testable class. `HighlightingController.setTargetSurah` loads exactly one
// surah's phonemes into the matching engine at a time, but a caller tracking
// a session that spans a surah boundary (a verse group, a continuous reading
// view, …) still wants the surah it just finished to keep its highlights on
// screen — that's what [preserveOtherSurahs] on [clearForRetarget] is for.

import '../tajweed/error_explainer.dart';

/// A single word's recitation status within [SurahHighlightStore].
enum WordHighlightStatus {
  unspoken,
  green,
  red,
  yellow,
  neutral,
}

class SurahHighlightStore {
  final Map<int, Map<int, Set<int>>> _green = {};
  final Map<int, Map<int, Set<int>>> _red = {};
  final Map<int, Map<int, Set<int>>> _yellow = {};
  final Map<int, Map<int, Set<int>>> _neutral = {};
  final Map<int, Map<int, Map<int, List<ReciterError>>>> _errors = {};
  final Map<int, Set<int>> _completedAyahs = {};

  // ── Writes ──

  void markGreen(int surah, int ayah, int wordIndex) {
    _red[surah]?[ayah]?.remove(wordIndex);
    _yellow[surah]?[ayah]?.remove(wordIndex);
    _neutral[surah]?[ayah]?.remove(wordIndex);
    ((_green[surah] ??= {})[ayah] ??= {}).add(wordIndex);
  }

  void markRed(int surah, int ayah, int wordIndex) {
    _green[surah]?[ayah]?.remove(wordIndex);
    _yellow[surah]?[ayah]?.remove(wordIndex);
    _neutral[surah]?[ayah]?.remove(wordIndex);
    ((_red[surah] ??= {})[ayah] ??= {}).add(wordIndex);
  }

  void markNeutral(int surah, int ayah, int wordIndex) {
    _green[surah]?[ayah]?.remove(wordIndex);
    _red[surah]?[ayah]?.remove(wordIndex);
    _yellow[surah]?[ayah]?.remove(wordIndex);
    ((_neutral[surah] ??= {})[ayah] ??= {}).add(wordIndex);
  }

  /// Downgrades an already-green word to yellow with Tajweed errors attached
  /// (a word is never marked yellow directly — only green-then-corrected).
  void markGreenWordAsYellow(
    int surah,
    int ayah,
    int wordIndex,
    List<ReciterError> errors,
  ) {
    if (!(_green[surah]?[ayah]?.contains(wordIndex) ?? false)) return;
    _green[surah]?[ayah]?.remove(wordIndex);
    ((_yellow[surah] ??= {})[ayah] ??= {}).add(wordIndex);
    ((_errors[surah] ??= {})[ayah] ??= {})[wordIndex] = errors;
  }

  void markAyahCompleted(int surah, int ayah) {
    (_completedAyahs[surah] ??= {}).add(ayah);
  }

  // ── Reads ──

  bool isGreen(int surah, int ayah, int wordIndex) =>
      _green[surah]?[ayah]?.contains(wordIndex) ?? false;

  bool isRed(int surah, int ayah, int wordIndex) =>
      _red[surah]?[ayah]?.contains(wordIndex) ?? false;

  bool isYellow(int surah, int ayah, int wordIndex) =>
      _yellow[surah]?[ayah]?.contains(wordIndex) ?? false;

  bool isNeutral(int surah, int ayah, int wordIndex) =>
      _neutral[surah]?[ayah]?.contains(wordIndex) ?? false;

  bool isUnspoken(int surah, int ayah, int wordIndex) =>
      !isGreen(surah, ayah, wordIndex) &&
      !isRed(surah, ayah, wordIndex) &&
      !isYellow(surah, ayah, wordIndex) &&
      !isNeutral(surah, ayah, wordIndex);

  List<ReciterError>? errorsFor(int surah, int ayah, int wordIndex) =>
      _errors[surah]?[ayah]?[wordIndex];

  Set<int> completedAyahsFor(int surah) =>
      _completedAyahs[surah] ?? const <int>{};

  // ── Clearing ──

  /// Wipes every tracked surah's state.
  void clearAll() {
    _green.clear();
    _red.clear();
    _yellow.clear();
    _neutral.clear();
    _errors.clear();
    _completedAyahs.clear();
  }

  /// Wipes only [surah]'s state, leaving every other surah untouched.
  void clearSurah(int surah) {
    _green.remove(surah);
    _red.remove(surah);
    _yellow.remove(surah);
    _neutral.remove(surah);
    _errors.remove(surah);
    _completedAyahs.remove(surah);
  }

  /// Wipes [surah]'s entries at or after [startAyah], leaving earlier ayahs
  /// of that surah (and every other surah) untouched.
  void clearSurahFromAyah(int surah, int startAyah) {
    _completedAyahs[surah]?.removeWhere((ayah) => ayah >= startAyah);
    _green[surah]?.removeWhere((ayah, _) => ayah >= startAyah);
    _red[surah]?.removeWhere((ayah, _) => ayah >= startAyah);
    _yellow[surah]?.removeWhere((ayah, _) => ayah >= startAyah);
    _neutral[surah]?.removeWhere((ayah, _) => ayah >= startAyah);
    _errors[surah]?.removeWhere((ayah, _) => ayah >= startAyah);
  }

  /// Prepares the store for tracking [surah] next.
  ///
  /// With [preserveOtherSurahs] (the default is `false`, matching the
  /// pre-existing full-reset behavior), every other surah's state is wiped
  /// too — appropriate when [surah] is an unrelated, brand-new session. Pass
  /// `true` when retargeting mid-session across a surah boundary so the
  /// surah being left keeps its already-committed highlights.
  void clearForRetarget(int surah, {bool preserveOtherSurahs = false}) {
    if (preserveOtherSurahs) {
      clearSurah(surah);
    } else {
      clearAll();
    }
  }
}
