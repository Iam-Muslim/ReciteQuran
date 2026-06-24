// lib/tracking/matchers/phoneme_chunker.dart
//
// Splits a continuous Arabic phonetic string into individual phoneme groups.
//
// A "phoneme group" is one BASE CONSONANT followed by zero or more HARAKAT
// (vowel marks / modifiers). This is the fundamental unit of Arabic phonology.
//
// Example:
//   Input:  "بِسمِللَاا"
//   Output: ["بِ", "س", "مِ", "ل", "لَ", "ا", "ا"]
//
//   "بِ" = consonant ب + kasra ِ
//   "س"  = consonant only (no harakat)
//   "لَ" = consonant ل + fatha َ
//   "ا"  = pure vowel (alef, counts as its own phoneme group)
//
// This is a Dart port of chunk_phonemes() from:
//   quran-transcript/src/quran_transcript/utils.py
//
// Why does this matter?
//   The ErrorExplainer compares phoneme groups, not raw characters.
//   Without chunking, a harakat mismatch ("بَ" vs "بِ") would look like
//   TWO errors instead of one. Chunking ensures we compare consonant+vowel
//   as one atomic unit.

class PhonemeChunker {
  // ── Residual characters (harakat, tanween, sukun, etc.) ───────────────────
  // These are "modifier" characters that attach to a base consonant.
  // Unicode ranges covered:
  //   U+064B–U+0652 = tanween fath/damm/kasr + fatha/damma/kasra + shadda/sukun
  //   U+0670        = small alef (alef khinjariyya)
  //   U+0687, U+0619, U+065C, U+0653–U+0655 = additional Quran-specific marks
  //   U+06DF–U+06E8 = extended Arabic presentation marks
  static final String _residualsStr =
      r'\u064B-\u0652\u0670\u0687\u0619\u065C\u0653\u0654\u0655\u06DF\u06E0\u06E2\u06E5\u06E6\u06E7\u06E8';

  // ── Regex: one non-residual char + optional trailing residuals ─────────────
  // This matches Python's: re.findall(r'[^residuals][residuals]*', text)
  static final RegExp _chunkRegex = RegExp('([^$_residualsStr][$_residualsStr]*)');

  /// Chunks a continuous phonetic string into phoneme groups.
  ///
  /// Each group contains exactly one base consonant/vowel followed by
  /// zero or more harakat modifiers.
  ///
  /// ```dart
  /// PhonemeChunker.chunkPhonemes("بِسمِ")
  /// // → ["بِ", "س", "مِ"]
  /// ```
  static List<String> chunkPhonemes(String phoneticScript) {
    return _chunkRegex
        .allMatches(phoneticScript)
        .map((m) => m.group(1)!)
        .toList();
  }
}
