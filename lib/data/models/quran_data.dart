/// Core Quran domain model.
///
/// Each [QuranVerse] stores the Uthmani Arabic text alongside a pre-computed
/// phoneme representation used by the matching engine.
library data.models.quran_data;

/// A single Quranic verse (ayah) with its Arabic text and phoneme data.
///
/// The [cleanWords] list is computed dynamically from the clean text
/// to support Arabic word-by-word evaluation.
class QuranVerse {
  /// The surah (chapter) number, 1-indexed.
  final int surah;

  /// The ayah (verse) number within [surah], 1-indexed.
  final int ayah;

  /// Full Uthmani Arabic text of this ayah.
  final String textUthmani;

  /// Arabic name of the surah (e.g. "الفاتحة").
  final String surahName;

  /// Transliterated English name of the surah (e.g. "Al-Fatihah").
  final String surahNameEn;

  /// The normalized version of the Arabic text without diacritics.
  final String textClean;

  /// Per-word clean Arabic strings. Index [i] corresponds to the i-th word in
  /// [textUthmani] (split on whitespace).
  final List<String> cleanWords;

  /// Per-word Uthmani strings. Index [i] corresponds to the i-th word.
  final List<String> uthmaniWords;

  const QuranVerse({
    required this.surah,
    required this.ayah,
    required this.textUthmani,
    required this.surahName,
    required this.surahNameEn,
    required this.textClean,
    required this.cleanWords,
    required this.uthmaniWords,
  });

  factory QuranVerse.fromJson(Map<String, dynamic> json) {
    return QuranVerse(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      textUthmani: json['text_uthmani'] as String? ?? '',
      surahName: json['surah_name'] as String? ?? '',
      surahNameEn: json['surah_name_en'] as String? ?? '',
      textClean: json['text_clean'] as String? ?? '',
      cleanWords: (json['text_clean'] as String? ?? '').split(' '),
      uthmaniWords: (json['text_uthmani'] as String? ?? '').split(' '),
    );
  }
}
