// lib/tracking/tracker_config.dart
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKER CONFIGURATION (CORE TUNING MATRIX)
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified immutable configuration for recitation tracking, thresholds, and Tajweed.
@immutable
class TrackerConfig {
  // ── Math Thresholds ──
  final double defaultMaxPathCost;    // 0.30: Base acceptance error threshold
  final double shortWordPathCost;     // 0.25: Strict threshold for words <= 3 chars
  final double mediumWordPathCost;    // 0.28: Strict threshold for words <= 7 chars
  final int maxSkipWords;             // 2: Lookahead word skips for omissions

  // ── Phonetic & Edit Costs ──
  final double acousticConfusionCost; // 0.25: Cost for acoustic confusion pairs (e.g. ص vs س)
  final double standardInsertionCost; // 0.75: Cost for extra ASR phonemes
  final double standardDeletionCost;  // 1.00: Cost for missing reference phonemes

  // ── Tajweed & Stream Timing ──
  final double harakatDurationSeconds;  // 0.250s: Duration of 1 Harakah vowel beat
  final double maxTokenDurationAllowed; // 2.5s: Maximum ceiling for a single token
  final double lookaheadDelay;          // 0.320s: CTC blank lookahead delay

  // ── Explainer UI Filtering ──
  final bool hideExpectedAsrNoise;    // true: Hide acceptable ASR slips from UI

  // ── Legacy Aliases (Backwards Compatibility) ──
  double get maxPathCost => defaultMaxPathCost;
  double get costDel => standardDeletionCost;
  double get costIns => standardInsertionCost;

  const TrackerConfig({
    this.defaultMaxPathCost = 0.30,
    this.shortWordPathCost = 0.25,
    this.mediumWordPathCost = 0.28,
    this.maxSkipWords = 2,
    this.acousticConfusionCost = 0.25,
    this.standardInsertionCost = 0.75,
    this.standardDeletionCost = 1.0,
    this.harakatDurationSeconds = 0.200,
    this.maxTokenDurationAllowed = 2.5,
    this.lookaheadDelay = 0.320,
    this.hideExpectedAsrNoise = true,
  });

  /// Standard baseline configuration (identical to original engine calibration).
  factory TrackerConfig.normal() => const TrackerConfig();

  /// Easy mode for beginners, children, or noisy microphones.
  factory TrackerConfig.easy() => const TrackerConfig(
        defaultMaxPathCost: 0.40,
        shortWordPathCost: 0.30,
        mediumWordPathCost: 0.35,
        maxSkipWords: 3,
        acousticConfusionCost: 0.15,
        standardInsertionCost: 0.50,
        standardDeletionCost: 0.80,
        harakatDurationSeconds: 0.150,
        maxTokenDurationAllowed: 3.0,
        lookaheadDelay: 0.320,
        hideExpectedAsrNoise: true,
      );

  /// Strict mode for advanced reciters, exams, or Tajweed certification.
  factory TrackerConfig.strict() => const TrackerConfig(
        defaultMaxPathCost: 0.25,
        shortWordPathCost: 0.20,
        mediumWordPathCost: 0.23,
        maxSkipWords: 1,
        acousticConfusionCost: 0.35,
        standardInsertionCost: 1.0,
        standardDeletionCost: 1.0,
        harakatDurationSeconds: 0.250,
        maxTokenDurationAllowed: 2.0,
        lookaheadDelay: 0.320,
        hideExpectedAsrNoise: false,
      );

  /// Creates a copy of this config with replaced fields.
  TrackerConfig copyWith({
    double? defaultMaxPathCost,
    double? shortWordPathCost,
    double? mediumWordPathCost,
    int? maxSkipWords,
    double? acousticConfusionCost,
    double? standardInsertionCost,
    double? standardDeletionCost,
    double? harakatDurationSeconds,
    double? maxTokenDurationAllowed,
    double? lookaheadDelay,
    bool? hideExpectedAsrNoise,
  }) {
    return TrackerConfig(
      defaultMaxPathCost: defaultMaxPathCost ?? this.defaultMaxPathCost,
      shortWordPathCost: shortWordPathCost ?? this.shortWordPathCost,
      mediumWordPathCost: mediumWordPathCost ?? this.mediumWordPathCost,
      maxSkipWords: maxSkipWords ?? this.maxSkipWords,
      acousticConfusionCost: acousticConfusionCost ?? this.acousticConfusionCost,
      standardInsertionCost: standardInsertionCost ?? this.standardInsertionCost,
      standardDeletionCost: standardDeletionCost ?? this.standardDeletionCost,
      harakatDurationSeconds: harakatDurationSeconds ?? this.harakatDurationSeconds,
      maxTokenDurationAllowed: maxTokenDurationAllowed ?? this.maxTokenDurationAllowed,
      lookaheadDelay: lookaheadDelay ?? this.lookaheadDelay,
      hideExpectedAsrNoise: hideExpectedAsrNoise ?? this.hideExpectedAsrNoise,
    );
  }
}
