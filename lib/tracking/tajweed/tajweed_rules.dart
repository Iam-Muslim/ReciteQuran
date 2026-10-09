// lib/tracking/tajweed/tajweed_rules.dart
import 'dart:math';
// ═══════════════════════════════════════════════════════════════════════════════
// TAJWEED RULES MODULE (DETERMINISTIC DURATION-BASED)
//
// Defines the acoustic duration and consonant closure domain models for Tajweed.
// Covers duration-verifiable rules:
//   1. Madd (`المدود`) — Vowel elongation duration checks (2, 4, 5, 6 beats).
//   2. Ghunnah on Mushaddad Noon & Meem (`النون والميم المشددتان`) — 2 beats.
//   3. Shaddah (`الشدة`) — Consonant holding duration (1 beat).
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: TIMING CONSTANTS (DETERMINISTIC ACOUSTIC SCALING)
// ═══════════════════════════════════════════════════════════════════════════════

class TajweedTimingConfig {
  /// Standard duration of a single Harakah (vowel beat unit) in seconds (150ms).
  /// Aligned with Sheikh Mahmoud Khalil Al-Husary's canonical Murattal/Tadweer pacing:
  ///   - 2 Harakat (Normal Madd / Ghunnah) = ~0.30s (range ~0.24s - 0.45s)
  ///   - 4 Harakat (Madd Aared Tawassut)  = ~0.60s (range ~0.50s - 0.85s)
  ///   - 6 Harakat (Madd Lazem Ishba')    = ~0.90s (range ~0.78s - 1.20s)
  static const double harakahBaseSeconds = 0.15;

  /// Tolerance in Harakat below target duration for short rules (<= 2 Harakat)
  /// to account for CTC frame quantization (~40-60ms) and natural human speech micro-variation.
  static const double shortRuleUnderheldToleranceHarakat = 0.4;

  /// Tolerance in Harakat below target duration for long rules (> 2 Harakat).
  static const double longRuleUnderheldToleranceHarakat = 0.6;

  /// Headroom in Harakat allowed above target duration for short rules (<= 2 Harakat).
  static const double shortRuleHeadroomHarakat = 1.5;

  /// Headroom in Harakat allowed above target duration for long rules (> 2 Harakat).
  /// 3.0 Harakat headroom allows natural pause extension (e.g. 4 + 3.0 = 7.0 Harakat = ~1.05s)
  /// matching Sheikh Al-Husary's Ishba' pause boundaries without triggering false overheld errors.
  static const double longRuleHeadroomHarakat = 3.0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: BASE CLASSES & METADATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a bilingual display name (Arabic and English) for user-facing errors.
class LangName {
  final String ar;
  final String en;
  const LangName({required this.ar, required this.en});
}

/// Represents the exact diagnosis of an acoustic duration check (`valid`, `underheld`, or `overheld`).
enum TajweedDurationStatus {
  /// The acoustic holding time matches the required Harakat duration within tolerance (`PASS`).
  valid,

  /// The reciter held the sound for less than the required duration (`FAIL - underheld / نقص`).
  underheld,

  /// The reciter held the sound longer than the allowed maximum duration (`FAIL - overheld / زيادة`).
  overheld,
}

/// Abstract base class representing a single duration check in Quranic recitation.
abstract class TajweedRule {
  final LangName name;
  final num goldenLen; // Expected Harakat count

  const TajweedRule({
    required this.name,
    required this.goldenLen,
  });

  /// Tolerance in Harakat below target duration before sound is flagged underheld.
  double get underheldToleranceHarakat => (goldenLen <= 2)
      ? TajweedTimingConfig.shortRuleUnderheldToleranceHarakat
      : TajweedTimingConfig.longRuleUnderheldToleranceHarakat;

  /// Headroom in Harakat allowed above target duration before sound is flagged overheld.
  double get headroomHarakat => (goldenLen <= 2)
      ? TajweedTimingConfig.shortRuleHeadroomHarakat
      : TajweedTimingConfig.longRuleHeadroomHarakat;

  /// Calculates exact required acoustic duration in seconds = goldenLen * harakahBase.
  double getRequiredDuration([double harakahBase = TajweedTimingConfig.harakahBaseSeconds]) {
    return goldenLen * harakahBase;
  }

  /// Verifies if the actual acoustic duration meets the required duration within tolerance.
  bool checkDuration(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    return checkDurationStatus(durationSeconds, harakahBase) == TajweedDurationStatus.valid;
  }

  /// Verifies whether the actual acoustic duration is valid, too short (underheld), or too long (overheld).
  TajweedDurationStatus checkDurationStatus(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    // 0. Acoustic telemetry guard:
    // Guard against negative durations, NaN, or infinite values resulting from ASR telemetry glitches.
    if (durationSeconds < 0.0 || durationSeconds.isNaN || durationSeconds.isInfinite) {
      return TajweedDurationStatus.valid;
    }
    if (goldenLen <= 0) return TajweedDurationStatus.valid;

    final double req = getRequiredDuration(harakahBase);

    // 1. Underheld: Reciter held less than the required Harakat duration (minus acoustic tolerance)
    final double underTolerance = underheldToleranceHarakat;
    final double minAllowedSeconds = max(0.04, req - (underTolerance * harakahBase));

    if (durationSeconds < minAllowedSeconds) {
      return TajweedDurationStatus.underheld;
    }

    // 2. Overheld: Reciter held beyond the target duration plus allowable headroom
    final double headroom = headroomHarakat;
    final double maxAllowedSeconds = req + (headroom * harakahBase);

    if (durationSeconds > maxAllowedSeconds) {
      return TajweedDurationStatus.overheld;
    }

    return TajweedDurationStatus.valid;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: MADD RULES (المدود)
// ═══════════════════════════════════════════════════════════════════════════════

class MaddRule extends TajweedRule {
  const MaddRule({
    required super.name,
    required super.goldenLen,
  });
}

/// ── 3.1 Normal Madd (`المد الطبيعي`) — 2 Harakat ──
class NormalMaddRule extends MaddRule {
  const NormalMaddRule()
      : super(
          name: const LangName(ar: "المد الطبيعي", en: "Normal Madd"),
          goldenLen: 2,
        );
}

/// ── 3.2 Monfasel Madd (`المد المنفصل`) ──
/// In Hadr (Fast) it is read with Qasr (2 Harakat - Tayyibat An-Nashr),
/// in Tadweer/Tahqiq (Normal/Slow) with Tawassut (4-5 Harakat - Shatibiyyah).
class MonfaselMaddRule extends MaddRule {
  const MonfaselMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد المنفصل", en: "Monfasel Madd"),
          goldenLen: harakat,
        );
}

/// ── 3.3 Mottasel Madd (`المد المتصل`) ──
class MottaselMaddRule extends MaddRule {
  const MottaselMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد المتصل", en: "Mottasel Madd"),
          goldenLen: harakat,
        );
}

/// ── 3.4 Mottasel Madd at Pause (`المد المتصل وقفا`) ──
class MottaselMaddPauseRule extends MaddRule {
  const MottaselMaddPauseRule([int harakat = 4])
      : super(
          name: const LangName(
            ar: "المد المتصل وقفا",
            en: "Mottasel Madd at Pause",
          ),
          goldenLen: harakat,
        );
}

/// ── 3.5 Aared Madd (`المد العارض للسكون`) ──
/// Uses the target Harakat defined by the active recitation speed (2, 4, or 6).
class AaredMaddRule extends MaddRule {
  const AaredMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد العارض للسكون", en: "Aared Madd"),
          goldenLen: harakat,
        );
}

/// ── 3.6 Lazem Madd (`المد اللازم`) — 6 Harakat ──
class LazemMaddRule extends MaddRule {
  const LazemMaddRule()
      : super(
          name: const LangName(ar: "المد اللازم", en: "Lazem Madd"),
          goldenLen: 6,
        );
}

/// ── 3.7 Leen Madd (`مد اللين`) ──
/// Uses the target Harakat defined by the active recitation speed (2, 4, or 6).
class LeenMaddRule extends MaddRule {
  const LeenMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "مد اللين", en: "Leen Madd"),
          goldenLen: harakat,
        );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4: GHUNNAH RULE (غنة النون والميم المشددتين) — 2 Harakat
// ═══════════════════════════════════════════════════════════════════════════════

class MushaddadGhunnahRule extends TajweedRule {
  const MushaddadGhunnahRule({
    LangName name = const LangName(
      ar: "النون أو الميم المشددة",
      en: "Mushaddad Noon/Meem",
    ),
  }) : super(
          name: name,
          goldenLen: 2,
        );

  factory MushaddadGhunnahRule.withNames({
    required String nameAr,
    required String nameEn,
  }) {
    return MushaddadGhunnahRule(
      name: LangName(ar: nameAr, en: nameEn),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5: SHADDAH RULE (الشدة) — 1 Harakah
// ═══════════════════════════════════════════════════════════════════════════════

class ShaddahRule extends TajweedRule {
  const ShaddahRule()
      : super(
          name: const LangName(ar: "الشدة", en: "Shaddah"),
          goldenLen: 1,
        );

  /// Doubled consonant closure requires >= 0.85 Harakat (~128ms at 0.15s base)
  /// to distinguish genuine gemination from a singleton consonant (60-90ms).
  @override
  double get underheldToleranceHarakat => 0.15;
}
