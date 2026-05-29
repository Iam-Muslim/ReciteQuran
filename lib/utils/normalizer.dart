// Arabic text normalization utilities for ASR matching.
//
// The ASR engine outputs raw Arabic text that may differ from the Quran's
// written form due to:
// - Diacritical marks (tashkeel) present in Quran but absent in ASR output
// - Alef variants (أ إ آ ٱ) that ASR may normalize differently
// - Ta marbuta (ة) vs Ha (ه) ambiguity
// - SentencePiece tokenizer artifacts (▁ characters)
//
// This normalizer strips these differences so that "بِسْمِ" and "بسم"
// compare as equal.
class Normalizer {
  /// Regex matching all Arabic diacritical marks and the tatweel character.
  static final RegExp _diacritics = RegExp(
    '[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC'
    '\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\u0640]',
  );

  /// Character normalization map — maps variant forms to canonical forms.
  static final Map<String, String> _normMap = {
    '\u0623': '\u0627', // أ → ا
    '\u0625': '\u0627', // إ → ا
    '\u0622': '\u0627', // آ → ا
    '\u0671': '\u0627', // ٱ → ا
    '\u0629': '\u0647', // ة → ه
    '\u0649': '\u064A', // ى → ي
  };

  /// Processes Huroof Muqatta'ah (الحروف المقطعة).
  /// Currently a no-op — muqattaat handling is commented out because
  /// the ASR model already handles them correctly for most cases.
  static String processMuqattaat(String text) {
    if (text.isEmpty) return text;
    return text;
  }

  /// Normalizes Arabic text for comparison:
  /// 1. Strips BOM if present
  /// 2. Removes all diacritical marks (tashkeel)
  /// 3. Normalizes alef/ta-marbuta/alef-maqsura variants
  /// 4. Replaces SentencePiece block characters with spaces
  /// 5. Collapses multiple spaces and trims
  static String normalizeArabic(String text) {
    if (text.isEmpty) return text;

    // Strip BOM (Byte Order Mark)
    if (text.startsWith('\ufeff')) {
      text = text.substring(1);
    }

    // Remove diacritics
    text = text.replaceAll(_diacritics, '');

    // Apply character normalization map
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(_normMap[char] ?? char);
    }
    text = buffer.toString();

    // Replace SentencePiece lower-one-eighth block with standard space
    text = text.replaceAll('\u2581', ' ');

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Maps specific small Uthmani Madd characters to standard letters
  /// to align character count indexing with the JSON response arrays.
  static String maddLetterMapping(String text) {
    if (text.isEmpty) return text;
    // Small Yaa (ۦ) -> Standard Yaa (ي)
    // Small Waw (ۥ) -> Standard Waw (و)
    return text.replaceAll('\u06E6', '\u064A').replaceAll('\u06E5', '\u0648');
  }
}
