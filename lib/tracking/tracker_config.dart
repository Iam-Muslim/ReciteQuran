import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 1. RECITATION SPEED (مراتب التلاوة للتجويد والمدود)
// ═══════════════════════════════════════════════════════════════════════════════

/// Pacing and speed of recitation (مراتب التلاوة).
/// Controls target Harakat counts for variable Madds.
enum RecitationSpeed {
  /// Fast recitation (الحدر) — Minimum valid Harakat (Qasr = 2 beats).
  fast,

  /// Normal recitation (التدوير) — Standard medium Harakat (Tawassut = 4 beats) (Default).
  normal,

  /// Slow recitation (التحقيق) — Maximum Harakat (Tool / Ishba' = 5-6 beats).
  slow;

  /// Target Harakat for Al-Madd Al-Aared Lissukun at Waqf (المد العارض للسكون).
  int get aaredMaddHarakat => switch (this) {
        RecitationSpeed.fast => 2,
        RecitationSpeed.normal => 4,
        RecitationSpeed.slow => 6,
      };

  /// Target Harakat for Al-Madd Al-Leen at Waqf (مد اللين).
  int get leenMaddHarakat => switch (this) {
        RecitationSpeed.fast => 2,
        RecitationSpeed.normal => 4,
        RecitationSpeed.slow => 6,
      };

  /// Target Harakat for Al-Madd Al-Monfasel (المد المنفصل).
  int get monfaselMaddHarakat => switch (this) {
        RecitationSpeed.fast => 2,
        RecitationSpeed.normal => 4,
        RecitationSpeed.slow => 5,
      };

  /// Target Harakat for Al-Madd Al-Mottasel (المد المتصل).
  int get mottaselMaddHarakat => switch (this) {
        RecitationSpeed.fast => 4,
        RecitationSpeed.normal => 4,
        RecitationSpeed.slow => 5,
      };

  /// Target Harakat for Al-Madd Al-Mottasel at Pause (المد المتصل وقفا).
  int get mottaselMaddPauseHarakat => switch (this) {
        RecitationSpeed.fast => 4,
        RecitationSpeed.normal => 4,
        RecitationSpeed.slow => 6,
      };

  /// Canonical duration of a single Harakah beat unit in seconds for this speed tier:
  ///   - Fast (Hadr / حدر)       = 0.12s (120ms per Harakah)
  ///   - Normal (Tadweer / تدوير) = 0.15s (150ms per Harakah)
  ///   - Slow (Tahqiq / تحقيق)    = 0.18s (180ms per Harakah)
  double get harakahBaseSeconds => switch (this) {
        RecitationSpeed.fast => 0.12,
        RecitationSpeed.normal => 0.15,
        RecitationSpeed.slow => 0.18,
      };

  /// Parses a recitation speed from a string identifier (with fallback to [normal]).
  static RecitationSpeed fromName(String? name) {
    if (name == null) return RecitationSpeed.normal;
    return switch (name.toLowerCase().trim()) {
      'fast' || 'hadr' || 'حدر' => RecitationSpeed.fast,
      'slow' || 'tahqiq' || 'تحقيق' => RecitationSpeed.slow,
      _ => RecitationSpeed.normal,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. MATCHING STRICTNESS (مستوى دقة وحساسية المطابقة)
// ═══════════════════════════════════════════════════════════════════════════════

/// Controls ASR speech matching acceptance sensitivity and edit penalties.
enum MatchingStrictness {
  /// Lenient mode: for children, beginners, noisy environments, or built-in mics.
  easy,

  /// Balanced mode: for standard everyday practice (Default).
  normal,

  /// Strict mode: for advanced reciters, memorization tests, and certifications.
  hard;

  /// Base acceptance error threshold.
  double get defaultMaxPathCost => switch (this) {
        MatchingStrictness.easy => 0.40,
        MatchingStrictness.normal => 0.30,
        MatchingStrictness.hard => 0.25,
      };

  /// Strict threshold for short words (<= 3 chars).
  double get shortWordPathCost => switch (this) {
        MatchingStrictness.easy => 0.30,
        MatchingStrictness.normal => 0.25,
        MatchingStrictness.hard => 0.20,
      };

  /// Strict threshold for medium words (<= 7 chars).
  double get mediumWordPathCost => switch (this) {
        MatchingStrictness.easy => 0.35,
        MatchingStrictness.normal => 0.28,
        MatchingStrictness.hard => 0.23,
      };

  /// Maximum lookahead word skips for detecting omissions.
  int get maxSkipWords => switch (this) {
        MatchingStrictness.easy => 1,
        MatchingStrictness.normal => 2,
        MatchingStrictness.hard => 3,
      };

  /// Cost for acoustic confusion pairs (e.g. ص vs س).
  double get acousticConfusionCost => switch (this) {
        MatchingStrictness.easy => 0.15,
        MatchingStrictness.normal => 0.25,
        MatchingStrictness.hard => 0.35,
      };

  /// Penalty for extra inserted ASR phonemes.
  double get standardInsertionCost => switch (this) {
        MatchingStrictness.easy => 0.50,
        MatchingStrictness.normal => 0.75,
        MatchingStrictness.hard => 1.00,
      };

  /// Penalty for missing reference phonemes.
  double get standardDeletionCost => switch (this) {
        MatchingStrictness.easy => 0.80,
        MatchingStrictness.normal => 1.00,
        MatchingStrictness.hard => 1.00,
      };

  /// Maximum acoustic ceiling for a single token in seconds.
  double get maxTokenDurationAllowed => switch (this) {
        MatchingStrictness.easy => 3.0,
        MatchingStrictness.normal => 2.5,
        MatchingStrictness.hard => 2.0,
      };

  /// Whether to filter out minor acoustic slips from the explanation dialog.
  bool get hideExpectedAsrNoise => switch (this) {
        MatchingStrictness.easy => true,
        MatchingStrictness.normal => true,
        MatchingStrictness.hard => false,
      };

  /// Whether to enable early word committing when Tajweed mode is off.
  bool get enableEarlyMatching => switch (this) {
        MatchingStrictness.easy => true,
        MatchingStrictness.normal => true,
        MatchingStrictness.hard => false,
      };

  /// Resolves strictness from string identifier (with fallback to [normal]).
  static MatchingStrictness fromName(String? name) {
    if (name == null) return MatchingStrictness.normal;
    return switch (name.toLowerCase().trim()) {
      'easy' || 'lenient' || 'سهل' || 'مرن' => MatchingStrictness.easy,
      'hard' || 'strict' || 'صعب' || 'دقيق' => MatchingStrictness.hard,
      _ => MatchingStrictness.normal,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. TRACKER CONFIGURATION (CORE RECITATION SETTINGS)
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified immutable configuration for recitation tracking and Tajweed evaluation.
///
/// Designed with two primary controls for application UI and settings:
/// 1. [recitationSpeed]: Controls Tajweed Harakat lengths (fast, normal, slow).
/// 2. [matchingStrictness]: Controls ASR word matching acceptance hardness (easy, normal, hard).
@immutable
class TrackerConfig {
  /// Recitation speed / pacing (مراتب التلاوة: الحدر، التدوير، التحقيق).
  final RecitationSpeed recitationSpeed;

  /// Word matching hardness / strictness (مرن، معياري، دقيق).
  final MatchingStrictness matchingStrictness;

  const TrackerConfig({
    this.recitationSpeed = RecitationSpeed.normal,
    this.matchingStrictness = MatchingStrictness.normal,
  });

  /// Standard baseline configuration (Tadweer pacing + Balanced matching).
  factory TrackerConfig.normal({
    RecitationSpeed speed = RecitationSpeed.normal,
  }) =>
      TrackerConfig(
        recitationSpeed: speed,
        matchingStrictness: MatchingStrictness.normal,
      );

  /// Easy mode for beginners, children, or noisy microphones.
  factory TrackerConfig.easy({
    RecitationSpeed speed = RecitationSpeed.fast,
  }) =>
      TrackerConfig(
        recitationSpeed: speed,
        matchingStrictness: MatchingStrictness.easy,
      );

  /// Strict mode for advanced reciters, exams, or Tajweed certification.
  factory TrackerConfig.strict({
    RecitationSpeed speed = RecitationSpeed.slow,
  }) =>
      TrackerConfig(
        recitationSpeed: speed,
        matchingStrictness: MatchingStrictness.hard,
      );

  // ── Delegated ASR Thresholds from [matchingStrictness] ──
  double get defaultMaxPathCost => matchingStrictness.defaultMaxPathCost;
  double get shortWordPathCost => matchingStrictness.shortWordPathCost;
  double get mediumWordPathCost => matchingStrictness.mediumWordPathCost;
  int get maxSkipWords => matchingStrictness.maxSkipWords;
  double get acousticConfusionCost => matchingStrictness.acousticConfusionCost;
  double get standardInsertionCost => matchingStrictness.standardInsertionCost;
  double get standardDeletionCost => matchingStrictness.standardDeletionCost;
  double get maxTokenDurationAllowed =>
      matchingStrictness.maxTokenDurationAllowed;
  bool get hideExpectedAsrNoise => matchingStrictness.hideExpectedAsrNoise;
  bool get enableEarlyMatching => matchingStrictness.enableEarlyMatching;

  TrackerConfig copyWith({
    RecitationSpeed? recitationSpeed,
    MatchingStrictness? matchingStrictness,
  }) {
    return TrackerConfig(
      recitationSpeed: recitationSpeed ?? this.recitationSpeed,
      matchingStrictness: matchingStrictness ?? this.matchingStrictness,
    );
  }
}
