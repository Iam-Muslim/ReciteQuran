// lib/tracking/tajweed/tajweed_rules.dart

import '../tracker_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TAJWEED RULES MODULE (EXPLICIT ACOUSTIC PROFILE MATRIX)
//
// Defines deterministic acoustic duration boundaries for Tajweed rules.
// Every rule specifies an explicit [AcousticThreshold] (min, target, max)
// for each [RecitationSpeed] tier (Fast, Normal, Slow).
//
// Architectural Principles:
//   1. 100% Deterministic: No magic tolerance factors, headroom hacks, or formulas.
//   2. Strictly DRY: Variable Waqf Madds (Aared & Leen) share their common matrix.
//   3. Compile-time Const: All thresholds are immutable, zero-allocation singletons.
//   4. Empirically Calibrated: Aligned with Sheikh Al-Husary and real mic recordings.
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: CORE DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a bilingual display name (Arabic and English) for user-facing errors.
class LangName {
  final String ar;
  final String en;
  const LangName({required this.ar, required this.en});
}

/// Represents the exact diagnosis of an acoustic duration check (`valid`, `underheld`, or `overheld`).
enum TajweedDurationStatus {
  /// The acoustic holding time matches the required duration within tolerance (`PASS`).
  valid,

  /// The reciter held the sound for less than the required duration (`FAIL - underheld / نقص`).
  underheld,

  /// The reciter held the sound longer than the allowed maximum duration (`FAIL - overheld / زيادة`).
  overheld;
}

/// Represents the deterministic acoustic duration boundaries (in seconds) for a rule.
class AcousticThreshold {
  /// The minimum acoustic duration in seconds before flagging [underheld].
  final double minSeconds;

  /// The nominal target duration in seconds for pedagogical reference.
  final double targetSeconds;

  /// The maximum acoustic duration in seconds before flagging [overheld].
  final double maxSeconds;

  const AcousticThreshold({
    required this.minSeconds,
    required this.targetSeconds,
    required this.maxSeconds,
  });

  /// Evaluates an actual acoustic duration against these boundaries.
  TajweedDurationStatus evaluate(double measuredSeconds) {
    if (measuredSeconds < 0.0 ||
        measuredSeconds.isNaN ||
        measuredSeconds.isInfinite) {
      return TajweedDurationStatus.valid;
    }
    if (measuredSeconds < minSeconds) {
      return TajweedDurationStatus.underheld;
    }
    if (measuredSeconds > maxSeconds) {
      return TajweedDurationStatus.overheld;
    }
    return TajweedDurationStatus.valid;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: BASE RULE
// ═══════════════════════════════════════════════════════════════════════════════

/// Abstract base class representing a duration-evaluated Tajweed rule.
abstract class TajweedRule {
  final LangName name;
  final num goldenLen; // Classical Harakat count (2, 4, 6) for pedagogical display

  const TajweedRule({
    required this.name,
    required this.goldenLen,
  });

  /// Returns the explicit acoustic threshold boundaries for the given recitation speed.
  AcousticThreshold getThreshold(RecitationSpeed speed);

  /// Verifies whether the actual acoustic duration is valid, too short, or too long.
  TajweedDurationStatus checkDurationStatus(
    double durationSeconds, [
    RecitationSpeed speed = RecitationSpeed.normal,
  ]) =>
      getThreshold(speed).evaluate(durationSeconds);

  /// Verifies if the actual acoustic duration meets the required duration within tolerance.
  bool checkDuration(
    double durationSeconds, [
    RecitationSpeed speed = RecitationSpeed.normal,
  ]) =>
      checkDurationStatus(durationSeconds, speed) == TajweedDurationStatus.valid;

  /// Calculates target acoustic duration in seconds for pedagogical reference.
  double getRequiredDuration([RecitationSpeed speed = RecitationSpeed.normal]) =>
      getThreshold(speed).targetSeconds;

  /// Calculates minimum allowed acoustic duration in seconds before [underheld] error.
  double getMinAllowedDuration([RecitationSpeed speed = RecitationSpeed.normal]) =>
      getThreshold(speed).minSeconds;

  /// Calculates maximum allowed acoustic duration in seconds before [overheld] error.
  double getMaxAllowedDuration([RecitationSpeed speed = RecitationSpeed.normal]) =>
      getThreshold(speed).maxSeconds;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: MADD RULES (المدود)
// ═══════════════════════════════════════════════════════════════════════════════

class MaddRule extends TajweedRule {
  const MaddRule({
    required super.name,
    required super.goldenLen,
  });

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) {
    if (goldenLen <= 2) {
      return const NormalMaddRule().getThreshold(speed);
    }
    if (goldenLen >= 6) {
      return const LazemMaddRule().getThreshold(speed);
    }
    return const MottaselMaddRule().getThreshold(speed);
  }
}

/// ── 3.1 Normal Madd (`المد الطبيعي`) — 2 Harakat ──
class NormalMaddRule extends MaddRule {
  const NormalMaddRule()
      : super(
          name: const LangName(ar: "المد الطبيعي", en: "Normal Madd"),
          goldenLen: 2,
        );

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.075,
            targetSeconds: 0.240,
            maxSeconds: 0.600,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.150,
            targetSeconds: 0.300,
            maxSeconds: 0.700,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.180,
            targetSeconds: 0.360,
            maxSeconds: 0.850,
          ),
      };
}

/// ── 3.2 Monfasel Madd (`المد المنفصل`) ──
class MonfaselMaddRule extends MaddRule {
  const MonfaselMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد المنفصل", en: "Monfasel Madd"),
          goldenLen: harakat,
        );

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.075,
            targetSeconds: 0.240,
            maxSeconds: 0.800,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.450,
            targetSeconds: 0.600,
            maxSeconds: 1.400,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.650,
            targetSeconds: 0.900,
            maxSeconds: 1.800,
          ),
      };
}

/// ── 3.3 Mottasel Madd (`المد المتصل`) ──
class MottaselMaddRule extends MaddRule {
  const MottaselMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد المتصل", en: "Mottasel Madd"),
          goldenLen: harakat,
        );

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.350,
            targetSeconds: 0.480,
            maxSeconds: 1.200,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.450,
            targetSeconds: 0.600,
            maxSeconds: 1.500,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.650,
            targetSeconds: 0.900,
            maxSeconds: 1.800,
          ),
      };
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

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.350,
            targetSeconds: 0.480,
            maxSeconds: 1.800,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.450,
            targetSeconds: 0.600,
            maxSeconds: 2.000,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.800,
            targetSeconds: 1.080,
            maxSeconds: 2.500,
          ),
      };
}

/// Base class for Madds at Waqf with speed-dependent variable faces (2, 4, 6 Harakat).
class VariableWaqfMaddRule extends MaddRule {
  const VariableWaqfMaddRule({
    required super.name,
    required super.goldenLen,
  });

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.120,
            targetSeconds: 0.240,
            maxSeconds: 1.800,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.300,
            targetSeconds: 0.600,
            maxSeconds: 2.200,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.500,
            targetSeconds: 1.080,
            maxSeconds: 2.500,
          ),
      };
}

/// ── 3.5 Aared Madd (`المد العارض للسكون`) ──
class AaredMaddRule extends VariableWaqfMaddRule {
  const AaredMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "المد العارض للسكون", en: "Aared Madd"),
          goldenLen: harakat,
        );
}

/// ── 3.6 Leen Madd (`مد اللين`) ──
class LeenMaddRule extends VariableWaqfMaddRule {
  const LeenMaddRule([int harakat = 4])
      : super(
          name: const LangName(ar: "مد اللين", en: "Leen Madd"),
          goldenLen: harakat,
        );
}

/// ── 3.7 Lazem Madd (`المد اللازم`) — 6 Harakat ──
class LazemMaddRule extends MaddRule {
  const LazemMaddRule()
      : super(
          name: const LangName(ar: "المد اللازم", en: "Lazem Madd"),
          goldenLen: 6,
        );

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.540,
            targetSeconds: 0.720,
            maxSeconds: 4.000,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.680,
            targetSeconds: 0.900,
            maxSeconds: 4.000,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.850,
            targetSeconds: 1.080,
            maxSeconds: 4.500,
          ),
      };
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

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.180,
            targetSeconds: 0.240,
            maxSeconds: 0.650,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.225,
            targetSeconds: 0.300,
            maxSeconds: 0.850,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.270,
            targetSeconds: 0.360,
            maxSeconds: 1.000,
          ),
      };

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

/// Consonant gemination closure.
/// In Fast mode: min floor is 0.190s so that light single consonants (0.120s - 0.160s)
/// are strictly CAUGHT as UNDERHELD, while real Shaddah holding passes.
class ShaddahRule extends TajweedRule {
  const ShaddahRule()
      : super(
          name: const LangName(ar: "الشدة", en: "Shaddah"),
          goldenLen: 1.5,
        );

  @override
  AcousticThreshold getThreshold(RecitationSpeed speed) => switch (speed) {
        RecitationSpeed.fast => const AcousticThreshold(
            minSeconds: 0.190,
            targetSeconds: 0.240,
            maxSeconds: 0.650,
          ),
        RecitationSpeed.normal => const AcousticThreshold(
            minSeconds: 0.200,
            targetSeconds: 0.250,
            maxSeconds: 0.850,
          ),
        RecitationSpeed.slow => const AcousticThreshold(
            minSeconds: 0.240,
            targetSeconds: 0.300,
            maxSeconds: 1.000,
          ),
      };
}
