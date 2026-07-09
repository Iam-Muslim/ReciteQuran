// lib/tracking/quran_normalizer.dart
//
// Port of quran-transcript/src/quran_transcript/utils.py :: normalize_aya()
//
// The ASR model (quran_phoneme_zipformer) outputs phonetic Arabic where:
//   - tashkeel (harakat) ARE present in the stream: بِسمِللَ
//   - alef variants (ى → ا) may differ from Uthmani text
//   - small alef "ٰ" (alef khinjariyya U+0670) may appear in Uthmani
//
// To match ASR output against Uthmani reference words, both sides are
// normalized through the same pipeline before Levenshtein comparison.
//
// normalize_aya defaults from quran-transcript (used for tasmeea matching):
//   remove_spaces=True, remove_tashkeel=True,
//   ignore_alef_maksoora=True, remove_small_alef=True

class QuranNormalizer {
  // ── Tashkeel (harakat + shadda + sukun + tanween) ──────────────────────────
  // alphabet.imlaey.tashkeel from quran-alphabet.json:
  // "ًٌٍَُِّْ" + tanween_idhaam_dterminer U+06EB
  static const String _tashkeelChars =
      '\u064B\u064C\u064D\u064E\u064F\u0650\u0651\u0652\u06EB';

  // ── Alef maksura → alef ────────────────────────────────────────────────────
  // ى (U+0649) → ا (U+0627)
  static const String _alefMaksura = '\u0649';
  static const String _alef = '\u0627';

  // ── Small alef (alef khinjariyya U+0670) ──────────────────────────────────
  static const String _smallAlef = '\u0670';

  // ── Hamzat wasl (U+0671 ٱ) → treated same as alef for matching ───────────
  // The Uthmani script uses ٱللَّهِ while imlaey uses اللَّهِ
  // normalize_aya does NOT handle this by default, but for phonetic matching
  // we strip it the same way (it maps to alef in imlaey)
  static const String _hamzatWasl = '\u0671';

  // ── Advanced Tajweed edge cases (MUST BE PRESERVED) ────────────────────────
  // These marks are essential for specific Qira'at rules and error checking.
  static const String sakt = '\u06E3'; // Small seen above (Sakt)
  static const String ishmam = '\u0658'; // Ishmam sign
  static const String tasheel = '\u065F'; // Tasheel sign
  static const String imala = '\u065E'; // Imala sign

  /// Mirror of normalize_aya() with the defaults used in tasmeea_sura():
  ///   remove_spaces=true, remove_tashkeel=true,
  ///   ignore_alef_maksoora=true, remove_small_alef=true
  ///
  /// Both the ASR stream and reference Uthmani words are passed through this
  /// before Levenshtein comparison so differences in tashkeel / alef variants
  /// do not cause false mismatches.
  static String normalize(
    String text, {
    bool removeSpaces = true,
    bool removeTashkeel = true,
    bool ignoreAlefMaksura = true,
    bool removeSmallAlef = true,
    bool normalizeHamzatWasl = true,
  }) {
    String s = text;

    if (removeSpaces) {
      s = s.replaceAll(_whitespaceRegex, '');
    }

    if (ignoreAlefMaksura) {
      s = s.replaceAll(_alefMaksura, _alef);
    }

    if (normalizeHamzatWasl) {
      // ٱ → ا  (Uthmani hamzat-wasl → plain alef used in imlaey/phonetic)
      s = s.replaceAll(_hamzatWasl, _alef);
    }

    if (removeSmallAlef) {
      s = s.replaceAll(_smallAlef, '');
    }

    if (removeTashkeel) {
      // Remove all harakat + shadda + sukun + tanween characters
      s = s.replaceAll(_tashkeelRegex, '');
    }

    return s;
  }

  /// Normalize a single Uthmani word for reference phoneme comparison.
  /// Keeps tashkeel because the ASR stream also carries tashkeel.
  /// Used when comparing the streaming phoneme buffer (which has tashkeel)
  /// against reference words (which also have tashkeel from Uthmani).
  ///
  /// Only normalizes structural differences: alef variants, hamzat wasl.
  static String normalizeWithTashkeel(String word) {
    return normalize(
      word,
      removeSpaces: true,
      removeTashkeel: false,
      ignoreAlefMaksura: true,
      removeSmallAlef: true,
      normalizeHamzatWasl: true,
    );
  }

  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _tashkeelRegex = RegExp('[$_tashkeelChars]');

  // ── Residual characters (harakat, tanween, sukun, etc.) ───────────────────
  // These are "modifier" characters that attach to a base consonant.
  //   U+064E, U+064F, U+0650 = fatha, damma, kasra
  //   U+0687 = qalqalah (small jeem)
  //   U+065E = fatha momala (imala sign)
  //   U+06E3 = sakt (small seen above)
  //   U+0619 = dama mokhtalasa
  static final String _residualsStr =
      r'\u064E\u064F\u0650\u0687\u065E\u06E3\u0619';

  // ── Regex: identical non-residual chars + optional trailing residuals ─────────────
  // This matches Python's: `(?:core_chars+)[residuals]?`
  // We use backreference `\2` to group identical consecutive base characters.
  static final RegExp _chunkRegex = RegExp('(([^$_residualsStr])\\2*[$_residualsStr]*)');

  /// Splits a continuous Arabic phonetic string into individual phoneme groups.
  ///
  /// A "phoneme group" is one BASE CONSONANT followed by zero or more HARAKAT
  /// (vowel marks / modifiers). This is the fundamental unit of Arabic phonology.
  ///
  /// Example:
  ///   Input:  "بِسمِللَاا"
  ///   Output: ["بِ", "س", "مِ", "ل", "لَ", "ا", "ا"]
  ///
  ///   "بِ" = consonant ب + kasra ِ
  ///   "س"  = consonant only (no harakat)
  ///   "لَ" = consonant ل + fatha َ
  ///   "ا"  = pure vowel (alef, counts as its own phoneme group)
  ///
  /// This is a Dart port of chunk_phonemes() from:
  ///   quran-transcript/src/quran_transcript/utils.py
  ///
  /// Why does this matter?
  ///   The ErrorExplainer compares phoneme groups, not raw characters.
  ///   Without chunking, a harakat mismatch ("بَ" vs "بِ") would look like
  ///   TWO errors instead of one. Chunking ensures we compare consonant+vowel
  ///   as one atomic unit.
  ///
  /// ```dart
  /// QuranNormalizer.chunkPhonemes("بِسمِ")
  /// // → ["بِ", "س", "مِ"]
  /// ```
  static List<String> chunkPhonemes(String phoneticScript) {
    return _chunkRegex
        .allMatches(phoneticScript)
        .map((m) => m.group(1)!)
        .toList();
  }
}
