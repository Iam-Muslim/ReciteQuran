// Core Quran domain model.
//
// Each [QuranVerse] stores the Uthmani Arabic text alongside a pre-computed
// phoneme representation used by the matching engine.


// A single Quranic verse (ayah) with its Arabic text and phoneme data.
//
// The [cleanWords] list is computed dynamically from the clean text
// to support Arabic word-by-word evaluation.
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

  /// Maps an index from [uthmaniWords] (UI) to its corresponding index in [cleanWords] (Matcher).
  /// Required because [uthmaniWords] contains stop marks (e.g. ۖ) as separate
  /// words which do not exist in [cleanWords]. Stop marks map to the previous word's index.
  final List<int> uthmaniToCleanMap;

  const QuranVerse({
    required this.surah,
    required this.ayah,
    required this.textUthmani,
    required this.surahName,
    required this.surahNameEn,
    required this.textClean,
    required this.cleanWords,
    required this.uthmaniWords,
    required this.uthmaniToCleanMap,
  });

  factory QuranVerse.fromJson(Map<String, dynamic> json) {
    final cleanWords =
        (json['aya_text_emlaey'] as String? ??
                json['text_clean'] as String? ??
                '')
            .split(' ')
            .where((s) => s.isNotEmpty)
            .toList();
    final uthmaniWords =
        (json['aya_text'] as String? ?? json['text_uthmani'] as String? ?? '')
            .split(' ')
            .where((s) => s.isNotEmpty)
            .toList();

    final List<int> map = [];
    int cleanIdx = 0;
    for (int uIdx = 0; uIdx < uthmaniWords.length; uIdx++) {
      final cleanAttempt = uthmaniWords[uIdx]
          .replaceAll(
            RegExp(
              r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\u0640]',
            ),
            '',
          )
          .trim();
      if (cleanAttempt.isNotEmpty) {
        map.add(cleanIdx);
        cleanIdx++;
      } else {
        // Stop mark — attach its visual state to the preceding word
        map.add(cleanIdx > 0 ? cleanIdx - 1 : -1);
      }
    }

    // Safety fallback
    if (cleanIdx != cleanWords.length) {
      map.clear();
      for (int i = 0; i < uthmaniWords.length; i++) {
        map.add(i < cleanWords.length ? i : cleanWords.length - 1);
      }
    }

    return QuranVerse(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      textUthmani:
          json['aya_text'] as String? ?? json['text_uthmani'] as String? ?? '',
      surahName: json['surah_name'] as String? ?? '',
      surahNameEn: json['surah_name_en'] as String? ?? '',
      textClean:
          json['aya_text_emlaey'] as String? ??
          json['text_clean'] as String? ??
          '',
      cleanWords: cleanWords,
      uthmaniWords: uthmaniWords,
      uthmaniToCleanMap: map,
    );
  }
}
