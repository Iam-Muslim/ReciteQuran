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
      s = s.replaceAll(RegExp(r'\s+'), '');
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
      s = s.replaceAll(RegExp('[$_tashkeelChars]'), '');
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

  /// Strip tashkeel only — used to get the bare consonant skeleton.
  /// Matches quran-transcript's normalize_aya(remove_tashkeel=True) path.
  static String normalizeBare(String text) => normalize(text);
}
