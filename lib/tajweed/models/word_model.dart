import 'package:flutter/material.dart';
import '../models/muaalem_result.dart';
import '../utils/text_helper.dart';

class TajweedError {
  final String phoneme;
  final String expectedPhoneme;
  final String word;
  final int? wordIndex;
  final int? charIndex;
  final String rule;
  final String expected;
  final String actual;
  final double confidence;

  TajweedError({
    required this.phoneme,
    required this.expectedPhoneme,
    required this.word,
    this.wordIndex,
    this.charIndex,
    required this.rule,
    required this.expected,
    required this.actual,
    required this.confidence,
  });
}

class WordModel {
  final int index;
  final String text;
  final String cleanText;
  final bool hasError; // We can keep this if needed, or remove it later
  final List<SifaItem> sifatList;
  final double? startMs;
  final double? endMs;
  final double startFraction;
  final double endFraction;

  WordModel({
    required this.index,
    required this.text,
    required this.cleanText,
    this.hasError = false,
    this.sifatList = const [],
    this.startMs,
    this.endMs,
    this.startFraction = 0.0,
    this.endFraction = 1.0,
  });

  static String _normalizeForMatching(String text) {
    var result = stripArabicDiacritics(text);
    result = result
        .replaceAll('ۦ', 'ي')
        .replaceAll('ۥ', 'و')
        .replaceAll('ٰ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ـ', '');

    if (result.isEmpty) return result;

    String deduplicated = result[0];
    for (int i = 1; i < result.length; i++) {
      if (result[i] != deduplicated[deduplicated.length - 1]) {
        deduplicated += result[i];
      }
    }

    return deduplicated;
  }

  static Map<int, MapEntry<int, int>> _buildIndexToWordCharMapping(
    Iterable<dynamic> items,
    List<String> cleanWords,
  ) {
    Map<int, MapEntry<int, int>> mapping = {};
    int wordIndex = 0;
    int charIndexOffset = 0;

    List<String> normalizedWords = cleanWords
        .map((w) => _normalizeForMatching(w))
        .toList();

    String findFirstMatchingCharIndex(
      String phoneme,
      String word,
      int startIdx,
    ) {
      if (phoneme.isEmpty || word.isEmpty || startIdx >= word.length) return "";
      for (int i = 0; i < phoneme.length; i++) {
        final c = phoneme[i];
        final idx = word.indexOf(c, startIdx);
        if (idx != -1) return "$c:$idx";
      }
      return "";
    }

    for (final sifa in items) {
      final sifaIndex = sifa.index;
      String rawPhoneme = '';
      if (sifa is SifaItem) {
        rawPhoneme = sifa.phonemesGroup;
      }
      var normalizedPhoneme = _normalizeForMatching(rawPhoneme);

      if (wordIndex < normalizedWords.length) {
        final currentWord = normalizedWords[wordIndex];
        final matchResult = findFirstMatchingCharIndex(
          normalizedPhoneme,
          currentWord,
          charIndexOffset,
        );

        if (matchResult.isNotEmpty) {
          final parts = matchResult.split(':');
          final matchIdx = int.parse(parts[1]);
          mapping[sifaIndex] = MapEntry(wordIndex, matchIdx);
          charIndexOffset = matchIdx + 1;
        } else if (wordIndex + 1 < normalizedWords.length) {
          final nextWord = normalizedWords[wordIndex + 1];
          final nextMatchResult = findFirstMatchingCharIndex(
            normalizedPhoneme,
            nextWord,
            0,
          );

          if (nextMatchResult.isNotEmpty ||
              currentWord.substring(charIndexOffset).isEmpty) {
            wordIndex++;
            if (nextMatchResult.isNotEmpty) {
              final parts = nextMatchResult.split(':');
              final matchIdx = int.parse(parts[1]);
              mapping[sifaIndex] = MapEntry(wordIndex, matchIdx);
              charIndexOffset = matchIdx + 1;
            } else {
              mapping[sifaIndex] = MapEntry(wordIndex, 0);
              charIndexOffset = 0;
            }
          } else {
            mapping[sifaIndex] = MapEntry(wordIndex, charIndexOffset);
          }
        } else {
          mapping[sifaIndex] = MapEntry(wordIndex, charIndexOffset);
        }
      } else {
        mapping[sifaIndex] = MapEntry(cleanWords.length - 1, 0);
      }
    }

    return mapping;
  }

  static List<WordModel> buildFrom(dynamic verse, MuaalemResponse? response) {
    debugPrint(
      '🔧 [WordModel.buildFrom] uthmaniWords=${verse.uthmaniWords.length} cleanWords=${verse.cleanWords.length}',
    );

    Map<int, MapEntry<int, int>> indexToWordMapping = {};
    if (response != null && response.sifat.isNotEmpty) {
      final wordsToMap = verse.cleanWords.length == verse.uthmaniWords.length
          ? verse.cleanWords
          : verse.uthmaniWords;

      indexToWordMapping = _buildIndexToWordCharMapping(
        response.sifat,
        wordsToMap,
      );
    }

    final uthmaniSifatMap = <int, List<SifaItem>>{};
    if (response != null && response.sifat.isNotEmpty) {
      for (final sifa in response.sifat) {
        final mappedEntry = indexToWordMapping[sifa.index];
        if (mappedEntry != null &&
            mappedEntry.key >= 0 &&
            mappedEntry.key < verse.uthmaniWords.length) {
          sifa.charIndex = mappedEntry.value;
          uthmaniSifatMap.putIfAbsent(mappedEntry.key, () => []).add(sifa);
        }
      }
    }

    final words = <WordModel>[];
    for (int i = 0; i < verse.uthmaniWords.length; i++) {
      final sifatForWord = uthmaniSifatMap[i] ?? [];
      double? startMs;
      double? endMs;

      if (sifatForWord.isNotEmpty) {
        startMs = sifatForWord.first.startMs;
        endMs = sifatForWord.last.endMs;
      }

      bool hasError = false;
      if (response != null && response.phonemes.probs.isNotEmpty) {
        for (final sifa in sifatForWord) {
          if (sifa.index >= 0 && sifa.index < response.phonemes.probs.length) {
            sifa.phonemeProb = response.phonemes.probs[sifa.index];
            if (sifa.phonemeProb < 0.85) {
              hasError = true;
            }
          }
        }
      }

      words.add(
        WordModel(
          index: i,
          text: verse.uthmaniWords[i],
          cleanText: verse.cleanWords.length > i
              ? verse.cleanWords[i]
              : verse.uthmaniWords[i],
          hasError: hasError,
          sifatList: sifatForWord,
          startMs: startMs,
          endMs: endMs,
          startFraction: verse.uthmaniWords.isEmpty
              ? 0.0
              : (i / verse.uthmaniWords.length),
          endFraction: verse.uthmaniWords.isEmpty
              ? 1.0
              : ((i + 1) / verse.uthmaniWords.length),
        ),
      );
    }

    debugPrint('🔧 [WordModel.buildFrom] Built ${words.length} words');
    return words;
  }
}

// ─── InteractiveVerse ────────────────────────────────────────────────────────
