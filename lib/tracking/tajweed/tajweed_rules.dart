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
  ///   - 2 Harakat (Normal Madd / Ghunnah) = ~0.30s (range ~0.16s - 0.40s)
  ///   - 4 Harakat (Madd Aared Tawassut)  = ~0.60s (range ~0.50s - 1.80s at Waqf)
  ///   - 6 Harakat (Madd Lazem Ishba')    = ~0.90s - 1.20s (range ~0.80s - 3.80s)
  static const double harakahBaseSeconds = 0.15;
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
  overheld;
}

/// Abstract base class representing a single duration check in Quranic recitation.
abstract class TajweedRule {
  final LangName name;
  final num goldenLen; // Expected Harakat count

  const TajweedRule({
    required this.name,
    required this.goldenLen,
  });

  /// The minimum tempo tolerance factor below nominal duration before flagging [underheld].
  /// Default across Tajweed rules is 0.80 (allowing 20% tempo variation).
  double get minToleranceFactor => 0.80;

  /// Headroom in Harakat allowed above target duration before flagging [overheld].
  double get maxHeadroomHarakat => (goldenLen <= 2) ? 3.5 : 4.0;

  /// Calculates exact required acoustic duration in seconds = goldenLen * harakahBase.
  double getRequiredDuration(
      [double harakahBase = TajweedTimingConfig.harakahBaseSeconds]) {
    return goldenLen * harakahBase;
  }

  /// Verifies if the actual acoustic duration meets the required duration within tolerance.
  bool checkDuration(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    return checkDurationStatus(durationSeconds, harakahBase) ==
        TajweedDurationStatus.valid;
  }

  /// Verifies whether the actual acoustic duration is valid, too short (underheld), or too long (overheld).
  TajweedDurationStatus checkDurationStatus(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    // 0. Acoustic telemetry guard:
    // Guard against negative durations, NaN, or infinite values resulting from ASR telemetry glitches.
    if (durationSeconds < 0.0 ||
        durationSeconds.isNaN ||
        durationSeconds.isInfinite) {
      return TajweedDurationStatus.valid;
    }
    if (goldenLen <= 0) return TajweedDurationStatus.valid;

    // Minimum required threshold based on rule tolerance
    final double req = getRequiredDuration(harakahBase) * minToleranceFactor;

    // 1. Underheld: Reciter held less than the required Harakat duration (minus margin)
    if (durationSeconds < req) {
      return TajweedDurationStatus.underheld;
    }

    // 2. Overheld: Reciter held beyond the target duration plus allowable headroom
    final double maxAllowedSeconds = req + (maxHeadroomHarakat * harakahBase);

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

  /// Madd vowels allow natural connected elongation tolerance:
  /// - 2 Harakat Madds (Normal Madd, or Monfasel / Aared / Leen with Qasr in fast mode):
  ///   factor = 0.50 (minimum ~0.12s in fast, ~0.15s in normal).
  /// - Multiple Harakat Madds (4, 5, 6 Harakat):
  ///   factor = 0.75 (strictly requires prolonged vowel: ~0.36s for 4h fast, ~0.54s for 6h fast).
  @override
  double get minToleranceFactor => (goldenLen <= 2) ? 0.50 : 0.75;
}

/// ── 3.1 Normal Madd (`المد الطبيعي`) — 2 Harakat (0.30s) ──
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

/// Base class for Madds at Waqf with speed-dependent variable faces (2, 4, 6 Harakat).
abstract class VariableWaqfMaddRule extends MaddRule {
  const VariableWaqfMaddRule({
    required super.name,
    required super.goldenLen,
  });

  /// Accommodates natural Waqf breath deceleration and Ishba' pause boundary (~1.8s - 2.1s).
  @override
  double get maxHeadroomHarakat => 8.0;

  @override
  TajweedDurationStatus checkDurationStatus(
    double durationSeconds, [
    double harakahBase = TajweedTimingConfig.harakahBaseSeconds,
  ]) {
    if (durationSeconds < 0.0 ||
        durationSeconds.isNaN ||
        durationSeconds.isInfinite) {
      return TajweedDurationStatus.valid;
    }
    if (goldenLen <= 0) return TajweedDurationStatus.valid;

    // Minimum required duration strictly enforced by configured speed / Harakat count:
    final double req = goldenLen * harakahBase * minToleranceFactor;
    if (durationSeconds < req) {
      return TajweedDurationStatus.underheld;
    }

    // Upper bound tolerance: allows legitimate Waqf holding up to Tool (6 Harakat) + waqf headroom
    final double maxAllowed = (max(goldenLen.toDouble(), 6.0) * harakahBase) +
        (maxHeadroomHarakat * harakahBase);
    if (durationSeconds > maxAllowed) {
      return TajweedDurationStatus.overheld;
    }

    return TajweedDurationStatus.valid;
  }
}

/// ── 3.5 Aared Madd (`المد العارض للسكون`) ──
/// In Tajweed, Al-Madd Al-Aared Lissukun at Waqf allows three legitimate faces:
/// 1. Fast (Hadr) = Qasr (2 Harakat) -> min 2 Harakat
/// 2. Normal (Tadweer) = Tawassut (4 Harakat) -> min 4 Harakat
/// 3. Slow (Tahqiq) = Tool / Ishba' (6 Harakat) -> min 6 Harakat
class AaredMaddRule extends VariableWaqfMaddRule {
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

  /// In Tajweed, Al-Madd Al-Lazem is held with reverberating Tartil resonance
  /// (Ishba' / إشباع, ~2.0s - 3.8s) and is never penalized for prolonged Ishba'.
  @override
  double get maxHeadroomHarakat => 20.0;
}

/// ── 3.7 Leen Madd (`مد اللين`) ──
/// Uses the target Harakat defined by active recitation speed (2, 4, or 6).
class LeenMaddRule extends VariableWaqfMaddRule {
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

  /// Ghunnah in Hadr/Tadweer allows 75% tempo tolerance (0.18s in fast, 0.225s in normal).
  @override
  double get minToleranceFactor => 0.75;

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
// SECTION 5: SHADDAH RULE (الشدة)
// ═══════════════════════════════════════════════════════════════════════════════

/// Consonant holding / gemination closure (1.5 beats: ساكن + متحرك).
class ShaddahRule extends TajweedRule {
  const ShaddahRule()
      : super(
          name: const LangName(ar: "الشدة", en: "Shaddah"),
          goldenLen: 1.5,
        );

  /// Deliberate Tartil gemination holding up to ~0.85s.
  @override
  double get maxHeadroomHarakat => 4.5;
}
