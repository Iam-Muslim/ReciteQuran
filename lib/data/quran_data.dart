import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'qiraat_ayah_mapper.dart';

// ---------------------------------------------------------------------------
// quran_data.dart
// ---------------------------------------------------------------------------

class WordTajweedRule {
  final int ruleId; // 1-7 (Madd), 9 (Shaddah), 10 (Mushaddad Ghunnah)
  final String nameAr;
  final String nameEn;
  final num goldenLen; // in Harakat (1, 1.5, 2, 4, 6)

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
        goldenLen: (map['goldenLen'] as num?) ?? 0,
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

  QuranVerse copyWith({
    int? surah,
    int? ayah,
    String? textUthmani,
    String? surahName,
    String? surahNameEn,
    List<String>? uthmaniWords,
    String? textPhoneme,
    List<String>? phonemeWords,
    List<List<WordTajweedRule>>? wordRules,
    List<int>? wordMap,
  }) {
    return QuranVerse(
      surah: surah ?? this.surah,
      ayah: ayah ?? this.ayah,
      textUthmani: textUthmani ?? this.textUthmani,
      surahName: surahName ?? this.surahName,
      surahNameEn: surahNameEn ?? this.surahNameEn,
      uthmaniWords: uthmaniWords ?? this.uthmaniWords,
      textPhoneme: textPhoneme ?? this.textPhoneme,
      phonemeWords: phonemeWords ?? this.phonemeWords,
      wordRules: wordRules ?? this.wordRules,
      wordMap: wordMap ?? _wordMap,
    );
  }

  static final RegExp _hizbSajdahRegex = RegExp(r'[۞۩]');

  factory QuranVerse.fromJson(
    int surahNum,
    int ayahNum,
    Map<String, dynamic> json, {
    Map<String, dynamic>? globalRuleNames,
  }) {
    final rawUthmani = json['aya_ui'] as String? ??
        json['uthmani'] as String? ??
        json['aya_text'] as String? ??
        '';
    final rawWords = rawUthmani.trim().split(' ');

    if (rawWords.length > 1 && json.containsKey('aya_ui')) {
      rawWords.removeLast();
    }

    final uthmaniWords = rawWords
        .map((w) => w.replaceAll(_hizbSajdahRegex, ''))
        .where((s) => s.isNotEmpty)
        .toList();

    String phonemeStr = json['aya_phoneme'] as String? ??
        json['phoneme'] as String? ??
        '';
    List<String> phonemeWords = [];

    if (json.containsKey('aya_phonemes_list')) {
      phonemeWords = List<String>.from(json['aya_phonemes_list']);
    } else if (json.containsKey('phoneme_words')) {
      phonemeWords = List<String>.from(json['phoneme_words']);
    }

    if (phonemeWords.isNotEmpty) {
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

// Verses are parsed lazily on demand from the decoded JSON map.
class QuranMetadataService {
  /// Optional absolute path to a custom phoneme JSON file on disk.
  ///
  /// Useful when phoneme data is downloaded on demand or selected dynamically
  /// per riwaya. When null, defaults to loading the bundled asset.
  QuranMetadataService({this.phonemeFilePath});

  final String? phonemeFilePath;

  Map<String, dynamic>? _rawJson;

  Future<void> loadData() async {
    if (_rawJson != null) return;

    final String phonemeData = phonemeFilePath != null
        ? await File(phonemeFilePath!).readAsString()
        : await _loadFromBundle();

    // Decode synchronously on the main isolate.
    _rawJson = jsonDecode(phonemeData) as Map<String, dynamic>;
  }

  /// Loads phoneme data from the rootBundle asset.
  Future<String> _loadFromBundle() async {
    String phonemeData = '{}';
    try {
      try {
        phonemeData = await rootBundle.loadString(
          'packages/recite_quran/assets/model/ordered_quran_phonemes.json',
        );
      } catch (_) {
        phonemeData = await rootBundle.loadString(
          'assets/model/ordered_quran_phonemes.json',
        );
      }
    } catch (e, stack) {
      print('CRITICAL ERROR loading quran phonemes: $e\n$stack');
      rethrow;
    }
    return phonemeData;
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
  QiraatAyahMapper? _ayahMapper;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded || _service.rawJson != null;
  final Map<int, List<QuranVerse>> _surahCache = {};
  final Map<int, List<ContinuousQuranWord>> _surahWordsCache = {};
  final Map<int, Map<int, int>> _ayahStartWordIndexCache = {};

  final List<QuranVerse> _fallbackMetadata = [];

  QuranRepository(this._service, {QiraatAyahMapper? ayahMapper})
      : _ayahMapper = ayahMapper;

  QiraatAyahMapper? get ayahMapper => _ayahMapper;

  void setAyahMapper(QiraatAyahMapper? mapper) {
    if (_ayahMapper == mapper) return;
    _ayahMapper = mapper;
    _surahCache.clear();
    _surahWordsCache.clear();
    _ayahStartWordIndexCache.clear();
  }

  List<QuranVerse> get surahMetadata {
    if (!isLoaded) return [];

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
    if (!isLoaded) {
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
    final mapper = _ayahMapper;

    if (mapper == null || mapper.system == QuranCountingSystem.kufi) {
      // 1:1 default Kufi (Hafs) loading
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
          break;
        }
      }
    } else {
      // Dynamic Non-Kufi Ayah Mapping
      final int sourceAyahCount = mapper.getSourceAyahCount(surah);
      final count = sourceAyahCount > 0 ? sourceAyahCount : 300;

      for (int ayah = 1; ayah <= count; ayah++) {
        // Special handling for Al-Fatihah across non-Kufi traditions
        if (surah == 1) {
          final fatihahVerse = _buildFatihahVerse(
            surah,
            ayah,
            mapper.system,
            versesMap,
            ruleNames,
          );
          if (fatihahVerse != null) {
            verses.add(fatihahVerse);
            continue;
          }
        }

        final hafsAyahs = mapper.getHafsAyahs(surah, ayah);
        final status = mapper.getMappingStatus(surah, ayah);

        if (status == 'covers_multiple' || hafsAyahs.length > 1) {
          final List<QuranVerse> subVerses = [];
          for (final h in hafsAyahs) {
            final hObj = versesMap['$surah:$h'];
            if (hObj != null) {
              subVerses.add(
                QuranVerse.fromJson(
                  surah,
                  h,
                  hObj as Map<String, dynamic>,
                  globalRuleNames: ruleNames,
                ),
              );
            }
          }
          if (subVerses.isNotEmpty) {
            verses.add(_mergeVerses(surah, ayah, subVerses));
          }
        } else {
          final int hafsAyah = mapper.getPrimaryHafsAyah(surah, ayah);
          final hObj = versesMap['$surah:$hafsAyah'];
          if (hObj != null) {
            verses.add(
              QuranVerse.fromJson(
                surah,
                ayah,
                hObj as Map<String, dynamic>,
                globalRuleNames: ruleNames,
              ),
            );
          } else if (sourceAyahCount == 0) {
            break;
          }
        }
      }
    }

    _surahCache[surah] = verses;
  }

  QuranVerse? _buildFatihahVerse(
    int surah,
    int ayah,
    QuranCountingSystem system,
    Map<String, dynamic> versesMap,
    Map<String, dynamic>? ruleNames,
  ) {
    if (system == QuranCountingSystem.madaniLast ||
        system == QuranCountingSystem.madaniFirst ||
        system == QuranCountingSystem.basri) {
      if (ayah >= 1 && ayah <= 5) {
        final hafsAyah = ayah + 1;
        final obj = versesMap['1:$hafsAyah'];
        if (obj == null) return null;
        return QuranVerse.fromJson(
          1,
          ayah,
          obj as Map<String, dynamic>,
          globalRuleNames: ruleNames,
        );
      } else if (ayah == 6 || ayah == 7) {
        final obj7 = versesMap['1:7'];
        if (obj7 == null) return null;
        final baseVerse = QuranVerse.fromJson(
          1,
          7,
          obj7 as Map<String, dynamic>,
          globalRuleNames: ruleNames,
        );
        if (ayah == 6) {
          // First 4 words: صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ
          final uWords = baseVerse.uthmaniWords.take(4).toList();
          final pWords = baseVerse.phonemeWords.take(4).toList();
          final rules = baseVerse.wordRules.take(4).toList();
          return QuranVerse(
            surah: 1,
            ayah: 6,
            textUthmani: uWords.join(' '),
            surahName: baseVerse.surahName,
            surahNameEn: baseVerse.surahNameEn,
            uthmaniWords: uWords,
            textPhoneme: pWords.join(''),
            phonemeWords: pWords,
            wordRules: rules,
          );
        } else {
          // Remaining words: غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ
          final uWords = baseVerse.uthmaniWords.skip(4).toList();
          final pWords = baseVerse.phonemeWords.skip(4).toList();
          final rules = baseVerse.wordRules.skip(4).toList();
          return QuranVerse(
            surah: 1,
            ayah: 7,
            textUthmani: uWords.join(' '),
            surahName: baseVerse.surahName,
            surahNameEn: baseVerse.surahNameEn,
            uthmaniWords: uWords,
            textPhoneme: pWords.join(''),
            phonemeWords: pWords,
            wordRules: rules,
          );
        }
      }
    }
    return null;
  }

  QuranVerse _mergeVerses(int surah, int ayah, List<QuranVerse> subVerses) {
    final List<String> uthmaniWords = [];
    final List<String> phonemeWords = [];
    final List<List<WordTajweedRule>> wordRules = [];

    for (final v in subVerses) {
      uthmaniWords.addAll(v.uthmaniWords);
      phonemeWords.addAll(v.phonemeWords);
      wordRules.addAll(v.wordRules);
    }

    return QuranVerse(
      surah: surah,
      ayah: ayah,
      textUthmani: uthmaniWords.join(' '),
      surahName: subVerses.first.surahName,
      surahNameEn: subVerses.first.surahNameEn,
      uthmaniWords: uthmaniWords,
      textPhoneme: phonemeWords.join(''),
      phonemeWords: phonemeWords,
      wordRules: wordRules,
    );
  }

  List<QuranVerse> getSurah(int surah) {
    if (!isLoaded) return [];
    _ensureSurahParsed(surah);
    return _surahCache[surah] ?? [];
  }

  List<ContinuousQuranWord> getSurahWords(int surah) {
    if (!isLoaded) return [];
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
    if (!isLoaded) return null;
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
