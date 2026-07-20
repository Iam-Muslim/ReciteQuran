// lib/tracking/tajweed/tajweed_rules.dart
// ═══════════════════════════════════════════════════════════════════════════════
// TAJWEED RULES MODULE (CONFIGURABLE, PURE & FULLY DOCUMENTED)
//
// This file defines the acoustic duration and consonant closure domain models
// for Tajweed evaluation. It is 100% dead-code free and focuses purely on:
//   1. Shaddah (`الشدة`) — Doubled consonant duration and closure check.
//   2. Madd (`المدود`) — Vowel elongation duration checks across 7 types.
//   3. Ghunnah (`الغنة`) — Nasal resonance duration checks for Noon/Meem.
//
// Every class, variable, and line is richly commented for long-term clarity.
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: TAJWEED TIMING CONFIGURATION (CENTRAL CONFIG - EASY TO TWEAK)
//
// This configuration class acts as the single source of truth for all duration
// thresholds in the application. By centralizing these constants here, any
// developer or AI assistant can tune overall recitation speed (e.g., Hadr vs Tahqeeq)
// by modifying `harakahBaseSeconds` or specific rule constants below.
// ═══════════════════════════════════════════════════════════════════════════════

class TajweedTimingConfig {
  /// Base duration of a single Harakah (vowel beat unit) in seconds.
  /// Standard Tadweer (medium pace) is calibrated to 0.40s (400ms).
  /// To make the app more lenient for fast speech (Hadr), reduce to ~0.30s.
  /// To make the app stricter for slow recitation (Tahqeeq), increase to ~0.50s.
  static const double harakahBaseSeconds = 0.25;

  /// ── 1. Shaddah (الشدة) Duration Threshold ──
  /// Required minimum acoustic holding time when pronouncing a doubled consonant
  /// closure (e.g., in "الرَّحْمَنِ"). Equivalent to 1 Harakah (0.40s).
  static const double shaddahSeconds = 1.5 * harakahBaseSeconds;

  /// ── 2. Normal Madd (المد الطبيعي) Duration Threshold ──
  /// Required minimum duration for natural vowel elongation (2 Harakat).
  /// Applies to standard Alif, Waw, and Yaa madd without following hamza or sukoon.
  static const double normalMaddSeconds = 1.2 * harakahBaseSeconds;

  /// ── 3. Ghunnah (الغنة) Duration Threshold ──
  /// Required minimum duration for nasal resonance (2 Harakat).
  /// Applies to Mushaddad Noon/Meem (e.g., "إِنَّ") and Idgham/Ikhfa nasal sounds.
  static const double ghunnahSeconds = 2.0 * harakahBaseSeconds;

  /// ── 4. The Locked 4/4/4/4 Group Duration Threshold ──
  /// Required minimum duration for Monfasel, Mottasel, Aared, and Leen Madds.
  /// Calibrated to 4 Harakat (1.60s) to match `ordered_quran_phonemes.json`.
  static const double group4MaddSeconds = 4.0 * harakahBaseSeconds;

  /// ── 5. Lazem Madd (المد اللازم) Duration Threshold ──
  /// Required minimum duration for compulsory/prolonged elongation (6 Harakat).
  /// Applies when a Madd letter is followed by a permanent sukoon or Shaddah (e.g., "الضَّالِّينَ").
  static const double lazemMaddSeconds = 6.0 * harakahBaseSeconds;

  /// ── 6. Qalqalah (القلقلة) Duration Threshold ──
  /// Required MAXIMUM duration for a Qalqalah bounce (e.g. 'ڇ').
  /// If the duration is longer than this, it means the user held the closure (Maktum) and suppressed the bounce.
  static const double qalqalahMaxSeconds =
      0.60 * harakahBaseSeconds; // approx 0.24s
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: PHONETIC CONSTANTS (ACTIVE ASR ALPHABET)
//
// Defines the exact Unicode symbols emitted by the ASR acoustic model and stored
// in `ordered_quran_phonemes.json`. Only symbols actively checked by duration
// or doubling rules are kept here to ensure zero dead code.
// ═══════════════════════════════════════════════════════════════════════════════

class PhoneticConstants {
  /// Standard Arabic Alif ('\u0627' -> 'ا') acting as a Madd carrier.
  static const String alif = '\u0627';

  /// Quranic small Waw ('\u06e5' -> 'ۥ') indicating an elongated Waw sound.
  static const String wawMadd = '\u06e5';

  /// Quranic small Yaa ('\u06e6' -> 'ۦ') indicating an elongated Yaa sound.
  static const String yaaMadd = '\u06e6';

  /// Standard Arabic letter Noon ('\u0646' -> 'ن').
  static const String noon = '\u0646';

  /// Standard Arabic letter Yaa ('\u064a' -> 'ي').
  static const String yaa = '\u064a';

  /// Standard Arabic letter Waw ('\u0648' -> 'و').
  static const String waw = '\u0648';

  /// Standard Arabic letter Meem ('\u0645' -> 'م').
  static const String meem = '\u0645';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3: BASE CLASSES & METADATA
//
// Provides the abstract foundational contracts for all Tajweed rules.
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a bilingual display name (Arabic and English) for user-facing errors.
class LangName {
  /// The rule name in Arabic (e.g., "المد الطبيعي").
  final String ar;

  /// The rule name in English (e.g., "Normal Madd").
  final String en;

  /// Const constructor ensuring zero runtime allocation overhead for names.
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

/// Abstract base class representing a single duration or doubling check in Quranic recitation.
abstract class TajweedRule {
  /// The bilingual display name shown in logs and user feedback.
  final LangName name;

  /// The expected Harakat count (e.g., 1 for Shaddah, 2 for Normal Madd, 4 for Mottasel).
  final int goldenLen;

  /// Optional sub-category tag distinguishing variants of the same rule (e.g., "noon" vs "meem").
  final String? tag;

  /// Set of allowed tag values valid for this specific rule class.
  final Set<String>? availableTags;

  /// Flag indicating that this rule's correctness is verified by checking acoustic timestamps (`chunkDuration`).
  /// Always `true` for active rules in this duration-based system.
  final bool useDurationOnly;

  /// Base constructor validating optional tags upon initialization.
  TajweedRule({
    required this.name,
    required this.goldenLen,
    this.tag,
    this.availableTags,
    this.useDurationOnly = true,
  }) {
    // If a tag and a set of available tags are provided, ensure the tag is strictly valid.
    if (tag != null && availableTags != null) {
      if (!availableTags!.contains(tag)) {
        throw ArgumentError(
          'Invalid tag value: `$tag`. Available ones are: `$availableTags`',
        );
      }
    }
  }

  /// Calculates exact required acoustic duration in seconds.
  /// MATH: `goldenLen` * `harakahBaseSeconds` (0.25s).
  /// For example, a Normal Madd (goldenLen=2) requires 0.50s.
  /// Subclasses like `Ghonnah` or `QalqalahRule` override this to return hardcoded ceilings.
  double getRequiredDuration() {
    return goldenLen * TajweedTimingConfig.harakahBaseSeconds;
  }

  /// Verifies if the actual acoustic duration held by the reciter meets or exceeds the required threshold.
  bool checkDuration(double durationSeconds) {
    return checkDurationStatus(durationSeconds) == TajweedDurationStatus.valid;
  }

  /// Verifies whether the actual acoustic duration held by the reciter is valid, too short (defect), or too long (surplus).
  ///
  /// Mathematical Bounds Check:
  /// 1. Lower Bound (Defect): The reciter must hold the sound for AT LEAST `req` seconds.
  ///    If `durationSeconds < req`, it fails immediately as a 'defect' (نقص).
  TajweedDurationStatus checkDurationStatus(double durationSeconds) {
    // If goldenLen is 0 or less, the rule requires no acoustic holding time.
    if (goldenLen <= 0) return TajweedDurationStatus.valid;
    double req = getRequiredDuration();

    // 1. Check defect (Lower Bound): Must hold at least the required duration threshold (`durationSeconds < req`).
    if (durationSeconds < req) {
      return TajweedDurationStatus.defect;
    }

    // 2. Check Surplus (Upper Bound Tolerance): 
    // Tajweed has natural human variation. We don't want to penalize a reciter for holding
    // a 2-beat Madd for 2.5 beats.
    //
    // - For short rules (<= 2 Harakat like Shaddah or Ghunnah): Allow +2.5 Harakat of headroom.
    //   Example: Shaddah requires 0.375s. Max allowed is 0.375 + 0.625 = 1.0s.
    // - For long rules (4-6 Harakat like Lazem Madd): Allow +4.0 Harakat of headroom.
    //   Example: Mottasel requires 1.0s. Max allowed is 1.0 + 1.0 = 2.0s.
    double maxAllowedSeconds;
    if (goldenLen <= 2) {
      maxAllowedSeconds = req + (2.5 * TajweedTimingConfig.harakahBaseSeconds);
    } else {
      maxAllowedSeconds = req + (4.0 * TajweedTimingConfig.harakahBaseSeconds);
    }

    if (durationSeconds > maxAllowedSeconds) {
      return TajweedDurationStatus.surplus;
    }

    return TajweedDurationStatus.valid;
  }

  /// Checks if a phoneme string (`phStr`) triggers or belongs to this Tajweed rule.
  bool isPhStrIn(String phStr) => true;

  /// Returns a specialized instance (`copyWith`) of this rule tailored to `phStr` (e.g., setting tag="noon").
  TajweedRule? getRelevantRule(String phStr) => this;

  /// Creates a copy of this rule instance with updated properties (`tag`, `name`, or `offset`).
  TajweedRule copyWith({String? tag, LangName? name, int? offset});
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4: SHADDAH RULE (الشدة)
//
// Evaluates doubled consonants (`Mushaddadah`). Ensures both structural closure
// (letter is pronounced twice) and adequate acoustic holding duration (`shaddahSeconds`).
// ═══════════════════════════════════════════════════════════════════════════════

class ShaddahRule extends TajweedRule {
  /// Initializes Shaddah with `goldenLen = 1` (~1 Harakah holding time).
  ShaddahRule({super.tag})
    : super(
        name: const LangName(ar: "الشدة", en: "Shaddah"),
        goldenLen: 1,
      );

  @override
  bool isPhStrIn(String phStr) {
    // A doubled consonant must have at least 2 characters in the phoneme chunk.
    if (phStr.isEmpty || phStr.length < 2) return false;

    // CRITICAL CHECK: Verify that the first two characters are identical (e.g., "للَ", "ررَ", "ببِ").
    // A single consonant followed by diacritics (e.g., "بِ" -> Ba + Kasra) has length 2 but is NOT Shaddah.
    if (phStr[1] != phStr[0]) return false;

    // Exclude Madd letters ('ا', 'ۥ', 'ۦ') and Mushaddad Noon ('ن') / Meem ('م').
    // Those are handled separately by `MaddRule` and `Ghonnah` respectively.
    return phStr[0] != PhoneticConstants.alif &&
        phStr[0] != PhoneticConstants.wawMadd &&
        phStr[0] != PhoneticConstants.yaaMadd &&
        phStr[0] != PhoneticConstants.noon &&
        phStr[0] != PhoneticConstants.meem;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    // Return this rule instance only if `phStr` contains a valid doubled consonant.
    if (isPhStrIn(phStr)) return this;
    return null;
  }

  @override
  double getRequiredDuration() {
    // Return the exact centralized Shaddah duration threshold (0.40s / 400ms).
    return TajweedTimingConfig.shaddahSeconds;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) => this;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5: MADD RULES (المدود)
//
// Evaluates all forms of vowel elongation (`Madd`). Organized into a generic parent
// class (`MaddRule`) and 7 specific subclasses for each Quranic Madd category.
// ═══════════════════════════════════════════════════════════════════════════════

class MaddRule extends TajweedRule {
  /// Internal lookup mapping the first character of a phoneme string (`phStr[0]`) to its tag.
  static const Map<String, String> _maddToTag = {
    PhoneticConstants.alif: "alif",
    PhoneticConstants.wawMadd: "waw",
    PhoneticConstants.yaaMadd: "yaa",
  };

  /// Initializes a generic Madd rule with allowed tags ("alif", "waw", "yaa").
  MaddRule({required super.name, required super.goldenLen, super.tag})
    : super(availableTags: {"alif", "waw", "yaa"});

  @override
  bool isPhStrIn(String phStr) {
    // Check if the chunk starts with a recognized Madd carrier character.
    if (phStr.isNotEmpty) {
      return _maddToTag.containsKey(phStr[0]);
    }
    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (phStr.isEmpty) return null;
    // If not a Madd letter, return null.
    if (!_maddToTag.containsKey(phStr[0])) return null;
    // Return a copy tagged specifically with the detected vowel type ("alif", "waw", or "yaa").
    return copyWith(tag: _maddToTag[phStr[0]]);
  }

  @override
  double getRequiredDuration() {
    // Calculates duration based on `goldenLen` times the base Harakah duration (0.40s).
    return goldenLen * TajweedTimingConfig.harakahBaseSeconds;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return MaddRule(
      name: name ?? this.name,
      goldenLen: goldenLen,
      tag: tag ?? this.tag,
    );
  }
}

/// ── 5.1 Normal Madd (`المد الطبيعي`) ──
/// Natural 2-Harakah elongation of Alif, Waw, or Yaa (`0.80s` / `normalMaddSeconds`).
class NormalMaddRule extends MaddRule {
  NormalMaddRule({super.tag})
    : super(
        name: const LangName(ar: "المد الطبيعي", en: "Normal Madd"),
        goldenLen: 2,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.normalMaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return NormalMaddRule(tag: tag ?? this.tag);
  }
}

/// ── 5.2 Monfasel Madd (`المد المنفصل`) ──
/// Separate Madd where the Madd letter is at the end of a word and Hamza is at the start
/// of the next word. Calibrated to 4 Harakat (`1.60s` / `group4MaddSeconds`).
class MonfaselMaddRule extends MaddRule {
  MonfaselMaddRule({super.tag})
    : super(
        name: const LangName(ar: "المد المنفصل", en: "Monfasel Madd"),
        goldenLen: 4,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.group4MaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return MonfaselMaddRule(tag: tag ?? this.tag);
  }
}

/// ── 5.3 Mottasel Madd at Pause (`المد المتصل وقفا`) ──
/// Connected Madd when stopping on the word containing the Hamza. Calibrated to 4 Harakat (`1.60s`).
class MottaselMaddPauseRule extends MaddRule {
  MottaselMaddPauseRule({super.tag})
    : super(
        name: const LangName(
          ar: "المد المتصل وقفا",
          en: "Mottasel Madd at Pause",
        ),
        goldenLen: 4,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.group4MaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return MottaselMaddPauseRule(tag: tag ?? this.tag);
  }
}

/// ── 5.4 Mottasel Madd (`المد المتصل`) ──
/// Connected Madd where the Madd letter and Hamza are inside the same word. Calibrated to 4 Harakat (`1.60s`).
class MottaselMaddRule extends MaddRule {
  MottaselMaddRule({super.tag})
    : super(
        name: const LangName(ar: "المد المتصل", en: "Mottasel Madd"),
        goldenLen: 4,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.group4MaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return MottaselMaddRule(tag: tag ?? this.tag);
  }
}

/// ── 5.5 Lazem Madd (`المد اللازم`) ──
/// Compulsory 6-Harakah elongation (`2.40s` / `lazemMaddSeconds`). Occurs when a Madd letter
/// is followed by an original permanent sukoon or Shaddah (e.g., "الضَّالِّينَ" or "الحَاقَّةُ").
class LazemMaddRule extends MaddRule {
  LazemMaddRule({super.tag})
    : super(
        name: const LangName(ar: "المد اللازم", en: "Lazem Madd"),
        goldenLen: 6,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.lazemMaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return LazemMaddRule(tag: tag ?? this.tag);
  }
}

/// ── 5.6 Aared Madd (`المد العارض للسكون`) ──
/// Elongation caused by a temporary sukoon when pausing at the end of a verse or word.
/// Calibrated to 4 Harakat (`1.60s` / `group4MaddSeconds`).
class AaredMaddRule extends MaddRule {
  AaredMaddRule({super.tag})
    : super(
        name: const LangName(ar: "المد العارض للسكون", en: "Aared Madd"),
        goldenLen: 4,
      );

  @override
  double getRequiredDuration() => TajweedTimingConfig.group4MaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return AaredMaddRule(tag: tag ?? this.tag);
  }
}

/// ── 5.7 Leen Madd (`مد اللين`) ──
/// Soft elongation of Waw ('و') or Yaa ('ي') with sukoon preceded by a fatha when pausing.
/// Calibrated to 4 Harakat (`1.60s` / `group4MaddSeconds`).
class LeenMaddRule extends MaddRule {
  /// Lookup mapping Waw and Yaa specifically for Leen evaluation.
  static const Map<String, String> _leenMaddToTag = {
    PhoneticConstants.waw: "waw",
    PhoneticConstants.yaa: "yaa",
  };

  LeenMaddRule({super.tag})
    : super(
        name: const LangName(ar: "مد اللين", en: "Leen Madd"),
        goldenLen: 4,
      );

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isNotEmpty) {
      return _leenMaddToTag.containsKey(phStr[0]);
    }
    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (phStr.isEmpty) return null;
    if (!_leenMaddToTag.containsKey(phStr[0])) return null;
    return copyWith(tag: _leenMaddToTag[phStr[0]]);
  }

  @override
  double getRequiredDuration() => TajweedTimingConfig.group4MaddSeconds;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return LeenMaddRule(tag: tag ?? this.tag);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6: GHONNAH RULE (الغنة)
//
// Evaluates nasal resonance lasting ~2 Harakat (`0.80s` / `ghunnahSeconds`).
// Targets Mushaddad Noon/Meem ("إِنَّ", "ثُمَّ") and Idgham/Ikhfa/Iqlab nasal sounds.
// ═══════════════════════════════════════════════════════════════════════════════

/// Metadata container associating a specific nasal symbol with its display name and tag.
class GhonnahMetadata {
  /// Bilingual display name for the specific nasal rule (e.g., "Shaddah/Idgham Noon").
  final LangName name;

  /// Internal category tag ("noon", "meem", "noon_yaa", etc.).
  final String tag;

  /// Character offset adjustment (default 0).
  final int offset;

  const GhonnahMetadata({
    required this.name,
    required this.tag,
    this.offset = 0,
  });
}

/// Evaluates nasal resonance duration and doubling across all 6 Quranic Ghunnah categories.
class Ghonnah extends TajweedRule {
  /// Optional character offset for specific Ghunnah transitions.
  final int offset;

  /// Lookup table mapping each nasal phoneme character to its specific `GhonnahMetadata`.
  static const Map<String, GhonnahMetadata> _phToMetadata = {
    PhoneticConstants.noon: GhonnahMetadata(
      name: LangName(ar: "النون المشددة أو المدغمة", en: "Shaddah/Idgham Noon"),
      tag: "noon",
      offset: 0,
    ),
    PhoneticConstants.yaa: GhonnahMetadata(
      name: LangName(ar: "إدغام النون في الياء", en: "Noon-Yaa Idgham"),
      tag: "noon_yaa",
      offset: 1,
    ),
    PhoneticConstants.waw: GhonnahMetadata(
      name: LangName(ar: "إدغام النون في الواو", en: "Noon-Waw Idgham"),
      tag: "noon_waw",
      offset: 1,
    ),
    PhoneticConstants.meem: GhonnahMetadata(
      name: LangName(ar: "الميم المشددة", en: "Shaddah Meem"),
      tag: "meem",
      offset: 0,
    ),
  };

  /// Initializes Ghunnah rule with allowed nasal tags.
  Ghonnah({
    required super.name,
    super.goldenLen = 4,
    super.tag,
    this.offset = 0,
  }) : super(
         availableTags: {
           "noon",
           "noon_yaa",
           "noon_waw",
           "meem",
         },
       );

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isEmpty) return false;
    String firstChar = phStr[0];
    // Check if first character is in our Ghunnah metadata lookup table.
    if (!_phToMetadata.containsKey(firstChar)) return false;

    // CRITICAL DISTINCTION FOR NOON AND MEEM:
    // A single light Meem (e.g., "مَ" in "الرَّحْمَنِ") or Noon ("نِ") has NO Ghunnah duration requirement!
    // We ONLY match when the base letter is doubled/mushaddadah (e.g., "ننَ", "ممَ", "ننن").
    if (firstChar == PhoneticConstants.noon ||
        firstChar == PhoneticConstants.meem) {
      return phStr.length >= 2 && phStr[1] == firstChar;
    }

    // For Yaa and Waw representing Idgham bi-Ghunnah of Noon, require a doubled base (e.g., "يَّ" or "وََّ").
    if (firstChar == PhoneticConstants.yaa ||
        firstChar == PhoneticConstants.waw) {
      return phStr.length >= 2 && phStr[1] == firstChar;
    }

    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (!isPhStrIn(phStr)) return null;
    // Retrieve the specific metadata associated with `phStr[0]` (`_phToMetadata`).
    final meta = _phToMetadata[phStr[0]]!;
    // Return a specialized copy displaying the specific bilingual name and tag.
    return copyWith(name: meta.name, offset: meta.offset, tag: meta.tag);
  }

  @override
  double getRequiredDuration() {
    // Returns the exact centralized Ghunnah duration threshold (0.80s / 800ms).
    return TajweedTimingConfig.ghunnahSeconds;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return Ghonnah(
      name: name ?? this.name,
      goldenLen: goldenLen,
      tag: tag ?? this.tag,
      offset: offset ?? this.offset,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 7: QALQALAH RULE (القلقلة)
//
// Evaluates the Qalqalah bounce duration to ensure the ASR didn't hallucinate it.
// ═══════════════════════════════════════════════════════════════════════════════

class QalqalahRule extends TajweedRule {
  QalqalahRule({super.tag})
    : super(
        name: const LangName(ar: "القلقلة", en: "Qalqalah"),
        goldenLen: 0,
        useDurationOnly: false,
      );

  @override
  bool isPhStrIn(String phStr) {
    // We only trigger this rule if the base character has the Qalqalah marker attached (e.g., 'بڇ').
    // Because the marker is a residual appended to the base character, we must check if the string contains it.
    return phStr.isNotEmpty && phStr.contains('ڇ');
  }

  @override
  double getRequiredDuration() {
    return TajweedTimingConfig.qalqalahMaxSeconds;
  }

  @override
  bool checkDuration(double durationSeconds) {
    return checkDurationStatus(durationSeconds) == TajweedDurationStatus.valid;
  }

  @override
  TajweedDurationStatus checkDurationStatus(double durationSeconds) {
    // REVERSE LOGIC: A correct Qalqalah is a quick bounce (short duration).
    // If they suppress it (Maktum), they hold their tongue on the roof of their mouth,
    // making the duration abnormally LONG (> qalqalahMaxSeconds).
    if (durationSeconds > TajweedTimingConfig.qalqalahMaxSeconds) {
      return TajweedDurationStatus.surplus;
    }
    return TajweedDurationStatus.valid;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return QalqalahRule(tag: tag ?? this.tag);
  }
}
