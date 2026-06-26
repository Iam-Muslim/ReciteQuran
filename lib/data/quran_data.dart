import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ---------------------------------------------------------------------------
// quran_data.dart
// ---------------------------------------------------------------------------

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
    List<int>? wordMap,
  }) : _wordMap = wordMap;

  factory QuranVerse.fromJson(
    int surahNum,
    int ayahNum,
    Map<String, dynamic> json,
  ) {
    final rawUthmani = json['aya_ui'] as String? ?? '';
    final rawWords = rawUthmani.trim().split(' ');

    if (rawWords.length > 1) {
      rawWords.removeLast();
    }

    final uthmaniWords = rawWords
        .map((w) => w.replaceAll(RegExp(r'[۞۩]'), ''))
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

    return QuranVerse(
      surah: surahNum,
      ayah: ayahNum,
      textUthmani: uthmaniWords.join(' '),
      surahName: json['suraname_ar'] as String? ?? '',
      surahNameEn: json['suraname_en'] as String? ?? '',
      uthmaniWords: uthmaniWords,
      textPhoneme: phonemeStr,
      phonemeWords: phonemeWords,
    );
  }
}

List<QuranVerse> _parseDatabaseInBackground(String data) {
  final Map<String, dynamic> phonemesList = jsonDecode(data);

  final List<QuranVerse> verses = [];
  for (final entry in phonemesList.entries) {
    final keyParts = entry.key.split(':');
    if (keyParts.length == 2) {
      final surahNum = int.tryParse(keyParts[0]) ?? 1;
      final ayahNum = int.tryParse(keyParts[1]) ?? 1;
      final phonemeObj = entry.value as Map<String, dynamic>;
      verses.add(QuranVerse.fromJson(surahNum, ayahNum, phonemeObj));
    }
  }

  // Sort sequentially by surah then ayah
  verses.sort((a, b) {
    if (a.surah != b.surah) return a.surah.compareTo(b.surah);
    return a.ayah.compareTo(b.ayah);
  });

  return verses;
}

class QuranMetadataService {
  List<QuranVerse>? _allVerses;
  Future<List<QuranVerse>> loadAll() async {
    if (_allVerses != null) return _allVerses!;

    String phonemeData = '{}';
    try {
      phonemeData = await rootBundle.loadString(
        'assets/model/ordered_quran_phonemes.json',
      );
    } catch (_) {
      // Fallback if missing
    }

    _allVerses = await compute(_parseDatabaseInBackground, phonemeData);
    return _allVerses!;
  }
}

class QuranRepository {
  final QuranMetadataService _service;

  List<QuranVerse> _allVerses = [];
  bool _isLoaded = false;
  final Map<int, List<QuranVerse>> _surahCache = {};

  QuranRepository(this._service);

  List<QuranVerse> get verses => _allVerses;

  List<QuranVerse> get surahMetadata {
    if (!_isLoaded) return [];
    return List.generate(114, (i) {
      final s = getSurah(i + 1);
      return s.isNotEmpty ? s.first : _allVerses.first;
    });
  }

  Future<void> loadSurahAsync(int surah) async {
    if (_isLoaded) return;
    _allVerses = await _service.loadAll();
    _isLoaded = true;

    for (final v in _allVerses) {
      (_surahCache[v.surah] ??= []).add(v);
    }
  }

  List<QuranVerse> getSurah(int surah) {
    if (!_isLoaded) return [];
    return _surahCache[surah] ?? [];
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
    final nextSurah = getSurah(surah + 1);
    if (nextSurah.isNotEmpty) {
      return nextSurah.first;
    }
    return null;
  }
}
