import 'dart:convert';

import 'package:flutter/services.dart';


// ---------------------------------------------------------------------------
// quran_data.dart
// ---------------------------------------------------------------------------

class WordTajweedRule {
  final int ruleId; // 1-7 (Madd), 9 (Shaddah), 10 (Mushaddad Ghunnah)
  final String nameAr;
  final String nameEn;
  final int goldenLen; // in Harakat (1, 2, 4, 6)

  const WordTajweedRule({
    required this.ruleId,
    required this.nameAr,
    required this.nameEn,
    required this.goldenLen,
  });

  Map<String, dynamic> toMap() => {
        'ruleId': ruleId,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'goldenLen': goldenLen,
      };

  factory WordTajweedRule.fromMap(Map map) => WordTajweedRule(
        ruleId: map['ruleId'] as int? ?? 0,
        nameAr: map['nameAr'] as String? ?? '',
        nameEn: map['nameEn'] as String? ?? '',
        goldenLen: map['goldenLen'] as int? ?? 0,
      );
}

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

  /// Per-word Uthmani strings. Index [i] corresponds to the i-th word.
  final List<String> uthmaniWords;

  /// Full phonetic text of this ayah
  final String textPhoneme;

  /// Per-word Phonetic strings. Index [i] corresponds to the i-th word.
  final List<String> phonemeWords;

  /// Pre-assigned Tajweed duration rules per word (Madds 1-7, Shaddah, Mushaddad Ghunnah).
  final List<List<WordTajweedRule>> wordRules;

  /// Maps an index in [uthmaniWords] to the corresponding index in [phonemeWords].
  /// This fixes UI drifting when idgham/wasl merges multiple Uthmani words into one phoneme word.
  List<int>? _wordMap;

  List<int> get wordMap {
    if (_wordMap == null) {
      _wordMap = List.generate(uthmaniWords.length, (i) => i);
    }
    return _wordMap!;
  }

  QuranVerse({
    required this.surah,
    required this.ayah,
    required this.textUthmani,
    required this.surahName,
    required this.surahNameEn,
    required this.uthmaniWords,
    required this.textPhoneme,
    required this.phonemeWords,
    this.wordRules = const [],
    List<int>? wordMap,
  }) : _wordMap = wordMap;

  static final RegExp _hizbSajdahRegex = RegExp(r'[۞۩]');

  factory QuranVerse.fromJson(
    int surahNum,
    int ayahNum,
    Map<String, dynamic> json, {
    Map<String, dynamic>? globalRuleNames,
  }) {
    final rawUthmani = json['aya_ui'] as String? ?? '';
    final rawWords = rawUthmani.trim().split(' ');

    if (rawWords.length > 1) {
      rawWords.removeLast();
    }

    final uthmaniWords = rawWords
        .map((w) => w.replaceAll(_hizbSajdahRegex, ''))
        .where((s) => s.isNotEmpty)
        .toList();

    String phonemeStr = json['aya_phoneme'] as String? ?? '';
    List<String> phonemeWords = [];

    if (json.containsKey('aya_phonemes_list')) {
      phonemeWords = List<String>.from(json['aya_phonemes_list']);

      // Safety check: Pad if mismatch
      if (phonemeWords.length < uthmaniWords.length) {
        phonemeWords.addAll(
          List.filled(uthmaniWords.length - phonemeWords.length, ''),
        );
      }
    } else {
      phonemeWords = List.filled(uthmaniWords.length, '');
    }

    // ── Build Word Tajweed Rules directly from V2 JSON and reference phonemes ──
    final List<List<WordTajweedRule>> wordRules = List.generate(
      uthmaniWords.length,
      (_) => [],
    );

    final rawText = json['aya_text'] as String? ?? '';
    final textWords = rawText.trim().split(' ');
    final rawRules = json['rules'] as List? ?? const [];

    int curOffset = 0;
    for (int w = 0; w < uthmaniWords.length; w++) {
      final int textLen = (w < textWords.length) ? textWords[w].length : 0;
      final int start = curOffset;
      final int end = curOffset + textLen;
      curOffset = end + 1; // space

      // 1. Direct Madd Rules (IDs 1-7) from V2 rules array
      for (var r in rawRules) {
        if (r is List && r.length >= 3) {
          final int pos = r[0] as int;
          final int rId = r[1] as int;
          final int harakat = r[2] as int;

          // Only keep Madd rules (1-7)
          if (rId >= 1 && rId <= 7 && pos >= start && pos < end) {
            final meta = globalRuleNames?[rId.toString()] as Map? ?? const {};
            final String nameAr = meta['ar'] as String? ?? 'مد';
            final String nameEn = meta['en'] as String? ?? 'Madd';
            wordRules[w].add(
              WordTajweedRule(
                ruleId: rId,
                nameAr: nameAr,
                nameEn: nameEn,
                goldenLen: harakat,
              ),
            );
          }
        }
      }

      // 2. Direct Ghunnah (~2 beats) on Mushaddad Noon & Meem only
      final String ph = (w < phonemeWords.length) ? phonemeWords[w] : '';

      if (ph.contains('نننن')) {
        wordRules[w].add(
          const WordTajweedRule(
            ruleId: 10,
            nameAr: 'النون المشددة',
            nameEn: 'Mushaddad Noon',
            goldenLen: 2,
          ),
        );
      } else if (ph.contains('مممم')) {
        wordRules[w].add(
          const WordTajweedRule(
            ruleId: 10,
            nameAr: 'الميم المشددة',
            nameEn: 'Mushaddad Meem',
            goldenLen: 2,
          ),
        );
      } else {
        // 3. Direct Shaddah (~1-1.5 beats) on any other doubled consonant
        for (int i = 0; i < ph.length - 1; i++) {
          final c1 = ph[i];
          final c2 = ph[i + 1];
          if (c1 == c2 && !'اۥۦ'.contains(c1)) {
            wordRules[w].add(
              const WordTajweedRule(
                ruleId: 9,
                nameAr: 'الشدة',
                nameEn: 'Shaddah',
                goldenLen: 1,
              ),
            );
            break;
          }
        }
      }
    }

    return QuranVerse(
      surah: surahNum,
      ayah: ayahNum,
      textUthmani: uthmaniWords.join(' '),
      surahName: json['suraname_ar'] as String? ?? '',
      surahNameEn: json['suraname_en'] as String? ?? '',
      uthmaniWords: uthmaniWords,
      textPhoneme: phonemeStr,
      phonemeWords: phonemeWords,
      wordRules: wordRules,
    );
  }
}

// We no longer parse the entire database upfront.
// Verses are parsed lazily on demand from the decoded JSON map.
class QuranMetadataService {
  Map<String, dynamic>? _rawJson;

  Future<void> loadData() async {
    if (_rawJson != null) return;

    String phonemeData = '{}';
    try {
      phonemeData = await rootBundle.loadString(
        'assets/model/ordered_quran_phonemes.json',
      );
    } catch (e, stack) {
      // Re-throw so the Orchestrator can show an error instead of silently breaking the matching system
      print('CRITICAL ERROR loading quran phonemes: $e\n$stack');
      rethrow;
    }

    // Decode synchronously on the main isolate.
    // Spawning a 3rd concurrent isolate here (alongside the Sherpa isolate and the
    // alignment isolate) pushes RSS to ~300MB+ during startup on 32-bit low-RAM
    // devices (e.g. Redmi 2020), triggering the OOM killer.
    // jsonDecode of the ~15MB Quran JSON takes < 200ms — acceptable for a one-time load.
    _rawJson = jsonDecode(phonemeData) as Map<String, dynamic>;
  }

  Map<String, dynamic>? get rawJson => _rawJson;
}

class ContinuousQuranWord {
  final int globalIndex;
  final int surah;
  final int ayah;
  final int wordInAyah;
  final String uthmani;
  final String phoneme;
  final List<WordTajweedRule> rules;

  const ContinuousQuranWord({
    required this.globalIndex,
    required this.surah,
    required this.ayah,
    required this.wordInAyah,
    required this.uthmani,
    required this.phoneme,
    this.rules = const [],
  });
}

class QuranRepository {
  final QuranMetadataService _service;

  bool _isLoaded = false;
  final Map<int, List<QuranVerse>> _surahCache = {};
  final Map<int, List<ContinuousQuranWord>> _surahWordsCache = {};
  final Map<int, Map<int, int>> _ayahStartWordIndexCache = {};

  final List<QuranVerse> _fallbackMetadata = [];

  QuranRepository(this._service);

  List<QuranVerse> get surahMetadata {
    if (!_isLoaded) return [];

    // We lazily parse Surah 1 verse 1 for each Surah to get the metadata
    // (surahName, surahNameEn, etc.) without parsing the whole Surah.
    if (_fallbackMetadata.isEmpty && _service.rawJson != null) {
      final raw = _service.rawJson!;
      final versesMap = (raw['verses'] as Map<String, dynamic>?) ?? raw;
      final ruleNames = raw['rule_names'] as Map<String, dynamic>?;

      for (int i = 1; i <= 114; i++) {
        final key = '$i:1';
        final obj = versesMap[key];
        if (obj != null) {
          _fallbackMetadata.add(
            QuranVerse.fromJson(
              i,
              1,
              obj as Map<String, dynamic>,
              globalRuleNames: ruleNames,
            ),
          );
        }
      }
    }
    return _fallbackMetadata;
  }

  Future<void> loadSurahAsync(int surah) async {
    if (!_isLoaded) {
      await _service.loadData();
      _isLoaded = true;
    }
    _ensureSurahParsed(surah);
  }

  void _ensureSurahParsed(int surah) {
    if (_surahCache.containsKey(surah)) return;

    final rawJson = _service.rawJson;
    if (rawJson == null) return;

    final versesMap = (rawJson['verses'] as Map<String, dynamic>?) ?? rawJson;
    final ruleNames = rawJson['rule_names'] as Map<String, dynamic>?;

    final List<QuranVerse> verses = [];

    // Most surahs have < 300 ayahs (Al-Baqarah has 286).
    for (int ayah = 1; ayah <= 300; ayah++) {
      final key = '$surah:$ayah';
      final phonemeObj = versesMap[key];
      if (phonemeObj != null) {
        verses.add(
          QuranVerse.fromJson(
            surah,
            ayah,
            phonemeObj as Map<String, dynamic>,
            globalRuleNames: ruleNames,
          ),
        );
      } else {
        break; // Assume ayahs are contiguous and we reached the end
      }
    }

    _surahCache[surah] = verses;
  }

  List<QuranVerse> getSurah(int surah) {
    if (!_isLoaded) return [];
    _ensureSurahParsed(surah);
    return _surahCache[surah] ?? [];
  }

  List<ContinuousQuranWord> getSurahWords(int surah) {
    if (!_isLoaded) return [];
    if (_surahWordsCache.containsKey(surah)) {
      return _surahWordsCache[surah]!;
    }

    final verses = getSurah(surah);

    final List<ContinuousQuranWord> words = [];
    final Map<int, int> ayahStartMap = {};
    int globalIdx = 0;

    for (final verse in verses) {
      ayahStartMap[verse.ayah] = globalIdx;
      for (int i = 0; i < verse.phonemeWords.length; i++) {
        final uthmani = i < verse.uthmaniWords.length
            ? verse.uthmaniWords[i]
            : '';
        final rules = (i < verse.wordRules.length) ? verse.wordRules[i] : const <WordTajweedRule>[];
        words.add(
          ContinuousQuranWord(
            globalIndex: globalIdx++,
            surah: verse.surah,
            ayah: verse.ayah,
            wordInAyah: i,
            uthmani: uthmani,
            phoneme: verse.phonemeWords[i],
            rules: rules,
          ),
        );
      }
    }

    _ayahStartWordIndexCache[surah] = ayahStartMap;
    _surahWordsCache[surah] = words;
    return words;
  }

  int getAyahStartGlobalIndex(int surah, int ayah) {
    if (!_surahWordsCache.containsKey(surah)) {
      getSurahWords(surah);
    }
    return _ayahStartWordIndexCache[surah]?[ayah] ?? 0;
  }

  QuranVerse? getVerse(int surah, int ayah) {
    if (!_isLoaded) return null;
    final verses = getSurah(surah);
    if (ayah >= 1 && ayah <= verses.length) {
      return verses[ayah - 1];
    }
    return null;
  }

  QuranVerse? getNextVerse(int surah, int ayah) {
    final verses = getSurah(surah);
    if (ayah >= 1 && ayah < verses.length) {
      return verses[ayah]; // 0-indexed internally
    }
    return null;
  }
}
