// lib/tracking/tajweed/tajweed_rules.dart
// ═══════════════════════════════════════════════════════════════════════════════
// TAJWEED RULES MODULE (PURE DURATION-BASED & FULLY DETERMINISTIC)
//
// Defines the acoustic duration and consonant closure domain models for Tajweed.
// Covers strictly duration-verifiable rules:
//   1. Madd (`المدود`) — Vowel elongation duration checks across 7 types (2, 4, 6 beats).
//   2. Ghunnah on Mushaddad Noon & Meem (`النون والميم المشددتان`) — 2 beats duration.
//   3. Shaddah (`الشدة`) — Doubled consonant closure and holding duration (~1.5 beats).
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: TAJWEED TIMING CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

class TajweedTimingConfig {
  /// Base duration of a single Harakah (vowel beat unit) in seconds.
  /// Standard Tadweer calibration is 0.25s (250ms).
  static const double harakahBaseSeconds = 0.25;

  /// ── 1. Shaddah (الشدة) Duration Threshold ──
  /// Required minimum acoustic holding time for doubled consonants (1.5 Harakat = 0.375s).
  static const double shaddahSeconds = 1.5 * harakahBaseSeconds;

  /// ── 2. Normal Madd (المد الطبيعي) Duration Threshold ──
  /// Required minimum duration for natural 2-Harakah vowel elongation (2.0 Harakat = 0.50s).
  static const double normalMaddSeconds = 2.0 * harakahBaseSeconds;

  /// ── 3. Ghunnah on Mushaddad Noon/Meem (غنة النون والميم المشددتين) ──
  /// Required minimum duration for nasal resonance hold (2.0 Harakat = 0.50s).
  static const double ghunnahSeconds = 2.0 * harakahBaseSeconds;

  /// ── 4. The 4-Harakat Madd Group Duration Threshold ──
  /// Required minimum duration for Monfasel, Mottasel, Aared, and Leen Madds (4.0 Harakat = 1.00s).
  static const double group4MaddSeconds = 4.0 * harakahBaseSeconds;

  /// ── 5. Lazem Madd (المد اللازم) Duration Threshold ──
  /// Required minimum duration for compulsory elongation (6.0 Harakat = 1.50s).
  static const double lazemMaddSeconds = 6.0 * harakahBaseSeconds;
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

/// Represents the exact diagnosis of an acoustic duration check (`valid`, `defect`, or `surplus`).
enum TajweedDurationStatus {
  /// The acoustic holding time matches the required Harakat duration within tolerance (`PASS`).
  valid,

  /// The reciter shortened the Madd or Ghunnah below the minimum required duration (`FAIL - defect / نقص`).
  defect,

  /// The reciter excessively prolonged the Madd or Ghunnah far beyond the required duration (`FAIL - Surplus / زيادة`).
  surplus,
}

/// Abstract base class representing a single duration check in Quranic recitation.
abstract class TajweedRule {
  final LangName name;
  final int goldenLen; // Expected Harakat count

  const TajweedRule({
    required this.name,
    required this.goldenLen,
  });

  /// Calculates exact required acoustic duration in seconds.
  double getRequiredDuration([double harakahBase = TajweedTimingConfig.harakahBaseSeconds]) {
    return goldenLen * harakahBase;
  }

  /// Verifies if the actual acoustic duration meets or exceeds the required threshold.
  bool checkDuration(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    return checkDurationStatus(durationSeconds, harakahBase) == TajweedDurationStatus.valid;
  }

  /// Verifies whether the actual acoustic duration is valid, too short (defect), or too long (surplus).
  TajweedDurationStatus checkDurationStatus(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    if (goldenLen <= 0) return TajweedDurationStatus.valid;
    final double req = getRequiredDuration(harakahBase);

    // 1. Check defect (Lower Bound): Must hold at least the required duration threshold.
    if (durationSeconds < req) {
      return TajweedDurationStatus.defect;
    }

    // 2. Check Surplus (Upper Bound Tolerance):
    // - For short rules (<= 2 Harakat like Shaddah or Ghunnah): Allow +2.5 Harakat headroom.
    // - For long rules (4-6 Harakat like Lazem Madd): Allow +4.0 Harakat headroom.
    final double maxAllowedSeconds = (goldenLen <= 2)
        ? req + (2.5 * harakahBase)
        : req + (4.0 * harakahBase);

    if (durationSeconds > maxAllowedSeconds) {
      return TajweedDurationStatus.surplus;
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

/// ── 3.2 Monfasel Madd (`المد المنفصل`) — 4 Harakat ──
class MonfaselMaddRule extends MaddRule {
  const MonfaselMaddRule()
      : super(
          name: const LangName(ar: "المد المنفصل", en: "Monfasel Madd"),
          goldenLen: 4,
        );
}

/// ── 3.3 Mottasel Madd (`المد المتصل`) — 4 Harakat ──
class MottaselMaddRule extends MaddRule {
  const MottaselMaddRule()
      : super(
          name: const LangName(ar: "المد المتصل", en: "Mottasel Madd"),
          goldenLen: 4,
        );
}

/// ── 3.4 Mottasel Madd at Pause (`المد المتصل وقفا`) — 4 Harakat ──
class MottaselMaddPauseRule extends MaddRule {
  const MottaselMaddPauseRule()
      : super(
          name: const LangName(
            ar: "المد المتصل وقفا",
            en: "Mottasel Madd at Pause",
          ),
          goldenLen: 4,
        );
}

/// ── 3.5 Aared Madd (`المد العارض للسكون`) — 4 Harakat ──
class AaredMaddRule extends MaddRule {
  const AaredMaddRule()
      : super(
          name: const LangName(ar: "المد العارض للسكون", en: "Aared Madd"),
          goldenLen: 4,
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

/// ── 3.7 Leen Madd (`مد اللين`) — 4 Harakat ──
class LeenMaddRule extends MaddRule {
  const LeenMaddRule()
      : super(
          name: const LangName(ar: "مد اللين", en: "Leen Madd"),
          goldenLen: 4,
        );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4: GHUNNAH RULE (غنة النون والميم المشددتين)
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

  @override
  double getRequiredDuration([double harakahBase = TajweedTimingConfig.harakahBaseSeconds]) =>
      2.0 * harakahBase;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5: SHADDAH RULE (الشدة)
// ═══════════════════════════════════════════════════════════════════════════════

class ShaddahRule extends TajweedRule {
  const ShaddahRule()
      : super(
          name: const LangName(ar: "الشدة", en: "Shaddah"),
          goldenLen: 1,
        );

  @override
  double getRequiredDuration([double harakahBase = TajweedTimingConfig.harakahBaseSeconds]) =>
      1.5 * harakahBase;
}
