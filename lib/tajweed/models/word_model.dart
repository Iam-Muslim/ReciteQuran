import 'package:flutter/material.dart';
import 'dart:math' as math;
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

class _DiffPos {
  final String text;
  final int position;
  _DiffPos(this.text, this.position);
}

class WordModel {
  final int index;
  final String text;
  final String cleanText;
  final bool hasError;
  final List<TajweedError> sifatErrors;
  final double? startMs;
  final double? endMs;
  final double startFraction;
  final double endFraction;

  WordModel({
    required this.index,
    required this.text,
    required this.cleanText,
    this.hasError = false,
    this.sifatErrors = const [],
    this.startMs,
    this.endMs,
    this.startFraction = 0.0,
    this.endFraction = 1.0,
  });

  static final Set<String> _maddChars = {
    'ا',
    'و',
    'ي',
    'ۥ',
    'ۦ',
    'آ',
    'ٱ',
    'ى',
  };
  static final Set<String> _harakatChars = {'َ', 'ُ', 'ِ', 'ْ', 'ً', 'ٌ', 'ٍ'};

  static String _harakaName(String haraka) {
    if (haraka.contains('َ')) return "فتحة";
    if (haraka.contains('ُ')) return "ضمة";
    if (haraka.contains('ِ')) return "كسرة";
    if (haraka.contains('ْ')) return "سكون";
    if (haraka.contains('ً')) return "تنوين فتح";
    if (haraka.contains('ٌ')) return "تنوين ضم";
    if (haraka.contains('ٍ')) return "تنوين كسر";
    return haraka;
  }

  static String _normalizeForMatching(String text) {
    // First strip diacritics
    var result = stripArabicDiacritics(text);
    
    // Map phonetic symbols to base letters
    result = result
        .replaceAll('ۦ', 'ي')
        .replaceAll('ۥ', 'و')
        .replaceAll('ٰ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ـ', '');

    // Deduplicate consecutive characters (e.g. اا -> ا)
    if (result.isEmpty) return result;
    
    String deduplicated = result[0];
    for (int i = 1; i < result.length; i++) {
      if (result[i] != deduplicated[deduplicated.length - 1]) {
        deduplicated += result[i];
      }
    }
    
    return deduplicated;
  }

  static Map<int, int> _buildIndexToWordMapping(
    Iterable<dynamic> items,
    List<String> cleanWords,
  ) {
    Map<int, int> mapping = {};
    int wordIndex = 0;

    // Use Swift's logic exactly: Emlaey words normalized and deduplicated.
    List<String> normalizedWords = cleanWords.map((w) => _normalizeForMatching(w)).toList();
    List<String> remainingInWord = List.from(normalizedWords);

    String findFirstMatchingChar(String phoneme, String word) {
      if (phoneme.isEmpty || word.isEmpty) return "";
      for (int i = 0; i < phoneme.length; i++) {
        if (word.contains(phoneme[i])) return phoneme[i];
      }
      return "";
    }

    for (final sifa in items) {
      final sifaIndex = sifa.index;
      String rawPhoneme = '';
      if (sifa is ExpectedSifaItem) {
        rawPhoneme = sifa.phonemes;
      } else if (sifa is SifaItem) {
        rawPhoneme = sifa.phonemesGroup;
      }

      var normalizedPhoneme = _normalizeForMatching(rawPhoneme);

      if (wordIndex < remainingInWord.length) {
        final currentRemaining = remainingInWord[wordIndex];
        final matchedChar = findFirstMatchingChar(
          normalizedPhoneme,
          currentRemaining,
        );

        if (matchedChar.isNotEmpty) {
          mapping[sifaIndex] = wordIndex;
          final idx = currentRemaining.indexOf(matchedChar);
          if (idx != -1) {
            remainingInWord[wordIndex] = currentRemaining.substring(idx + 1);
          }
        } else if (wordIndex + 1 < remainingInWord.length) {
          final nextRemaining = remainingInWord[wordIndex + 1];
          final shouldMove =
              currentRemaining.isEmpty ||
              findFirstMatchingChar(
                normalizedPhoneme,
                nextRemaining,
              ).isNotEmpty;

          if (shouldMove) {
            wordIndex++;
            mapping[sifaIndex] = wordIndex;
            final nextMatchedChar = findFirstMatchingChar(
              normalizedPhoneme,
              remainingInWord[wordIndex],
            );
            if (nextMatchedChar.isNotEmpty) {
              final idx2 = remainingInWord[wordIndex].indexOf(nextMatchedChar);
              if (idx2 != -1) {
                remainingInWord[wordIndex] = remainingInWord[wordIndex]
                    .substring(idx2 + 1);
              }
            }
          } else {
            mapping[sifaIndex] = wordIndex;
          }
        } else {
          mapping[sifaIndex] = wordIndex;
        }
      } else {
        mapping[sifaIndex] = cleanWords.length - 1;
      }
    }

    return mapping;
  }

  static List<TajweedError> _detectMaddErrors(
    dynamic verse,
    MuaalemResponse result,
  ) {
    final diffs = result.phonemeDiff;
    if (diffs == null) return [];

    final expectedPhonemes = result.reference.phoneticScript.phonemesText;
    var expectedPosition = 0;

    final deletions = <_DiffPos>[];
    final insertions = <_DiffPos>[];

    for (final diff in diffs) {
      final count = diff.text.runes.length;
      if (diff.type == "equal") {
        expectedPosition += count;
      } else if (diff.type == "delete") {
        deletions.add(_DiffPos(diff.text, expectedPosition));
        expectedPosition += count;
      } else if (diff.type == "insert") {
        insertions.add(_DiffPos(diff.text, expectedPosition));
      }
    }

    String findLetterAtPosition(int position) {
      if (position <= 0) return "";
      final runes = expectedPhonemes.runes.toList();
      final idx = (position - 1).clamp(0, runes.length - 1);
      final char = String.fromCharCode(runes[idx]);
      if (_harakatChars.contains(char) && position > 1) {
        return String.fromCharCode(runes[(idx - 1).clamp(0, runes.length - 1)]);
      }
      return char;
    }

    Map<int, int> indexToWordMapping = {};
    if (result.expectedSifat != null &&
        verse.cleanWords.length == verse.uthmaniWords.length) {
      indexToWordMapping = _buildIndexToWordMapping(
        result.expectedSifat!,
        verse.cleanWords,
      );
    } else if (result.expectedSifat != null) {
      indexToWordMapping = _buildIndexToWordMapping(
        result.expectedSifat!,
        verse.uthmaniWords,
      );
    }

    List<dynamic> findWordAtPosition(int position) {
      final expectedSifat = result.expectedSifat;
      if (expectedSifat == null) return [verse.uthmaniWords.first, 0];

      int charCount = 0;
      int sifaIndex = 0;

      for (int i = 0; i < expectedSifat.length; i++) {
        final sifa = expectedSifat[i];
        final sifaLen = sifa.phonemes.runes.length;
        if (position >= charCount && position < charCount + sifaLen) {
          sifaIndex = i;
          break;
        }
        charCount += sifaLen;
        if (i == expectedSifat.length - 1) sifaIndex = i;
      }

      int? charIndex;
      if (result.phonemesByWord != null &&
          indexToWordMapping.containsKey(sifaIndex)) {
        try {
          final wp = result.phonemesByWord!.firstWhere(
            (w) => w.containsIndex(sifaIndex),
          );
          charIndex = sifaIndex - wp.sifatStart;
        } catch (_) {}
      }

      if (indexToWordMapping.containsKey(sifaIndex)) {
        final mappedIndex = indexToWordMapping[sifaIndex]!;
        if (mappedIndex >= 0 && mappedIndex < verse.uthmaniWords.length) {
          return [verse.uthmaniWords[mappedIndex], mappedIndex, charIndex];
        }
      }

      return [
        verse.uthmaniWords.last,
        verse.uthmaniWords.length - 1,
        charIndex,
      ];
    }

    final errors = <TajweedError>[];
    final pairCount = math.min(deletions.length, insertions.length);

    for (int i = 0; i < pairCount; i++) {
      final expected = deletions[i].text;
      final actual = insertions[i].text;
      final position = deletions[i].position;
      final wordInfo = findWordAtPosition(position);
      final word = wordInfo[0] as String;
      final wordIndex = wordInfo[1] as int;
      final charIndex = wordInfo[2] as int?;

      final expectedHaraka = String.fromCharCodes(
        expected.runes.where(
          (r) => _harakatChars.contains(String.fromCharCode(r)),
        ),
      );
      final actualHaraka = String.fromCharCodes(
        actual.runes.where(
          (r) => _harakatChars.contains(String.fromCharCode(r)),
        ),
      );
      final expectedMadd = String.fromCharCodes(
        expected.runes.where(
          (r) => _maddChars.contains(String.fromCharCode(r)),
        ),
      );
      final actualMadd = String.fromCharCodes(
        actual.runes.where((r) => _maddChars.contains(String.fromCharCode(r))),
      );

      if (expectedHaraka.isNotEmpty || actualHaraka.isNotEmpty) {
        final letter = findLetterAtPosition(position);
        final phonemeToHighlight = letter.isEmpty
            ? (actual.isEmpty ? expected : actual)
            : letter;
        errors.add(
          TajweedError(
            phoneme: phonemeToHighlight,
            expectedPhoneme: phonemeToHighlight,
            word: word,
            wordIndex: wordIndex,
            rule: "الحركات",
            expected: _harakaName(
              expectedHaraka.isEmpty ? "—" : expectedHaraka,
            ),
            actual: _harakaName(actualHaraka.isEmpty ? "—" : actualHaraka),
            confidence: 1.0,
          ),
        );
      } else if (expectedMadd.isNotEmpty || actualMadd.isNotEmpty) {
        errors.add(
          TajweedError(
            phoneme: actual.isEmpty ? expected : actual,
            expectedPhoneme: expected,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "المد",
            expected: expectedMadd.isEmpty
                ? "بدون مد"
                : "مد (${expectedMadd.runes.length} حرف)",
            actual: actualMadd.isEmpty
                ? "بدون مد"
                : "مد (${actualMadd.runes.length} حرف)",
            confidence: 1.0,
          ),
        );
      } else {
        errors.add(
          TajweedError(
            phoneme: actual,
            expectedPhoneme: expected,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "الحروف",
            expected: expected,
            actual: actual,
            confidence: 1.0,
          ),
        );
      }
    }

    for (int i = pairCount; i < deletions.length; i++) {
      final expected = deletions[i].text;
      final position = deletions[i].position;
      final wordInfo = findWordAtPosition(position);
      final word = wordInfo[0] as String;
      final wordIndex = wordInfo[1] as int;
      final charIndex = wordInfo[2] as int?;

      final maddCount = expected.runes
          .where((r) => _maddChars.contains(String.fromCharCode(r)))
          .length;
      final harakaCount = expected.runes
          .where((r) => _harakatChars.contains(String.fromCharCode(r)))
          .length;

      if (maddCount > 0) {
        errors.add(
          TajweedError(
            phoneme: expected,
            expectedPhoneme: expected,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "المد",
            expected: "مد ($maddCount حرف)",
            actual: "بدون مد",
            confidence: 1.0,
          ),
        );
      } else if (harakaCount > 0) {
        final letter = findLetterAtPosition(position);
        errors.add(
          TajweedError(
            phoneme: letter.isEmpty ? expected : letter,
            expectedPhoneme: letter.isEmpty ? expected : letter,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "الحركات",
            expected: _harakaName(expected),
            actual: "ناقص",
            confidence: 1.0,
          ),
        );
      } else {
        errors.add(
          TajweedError(
            phoneme: expected,
            expectedPhoneme: expected,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "الحروف",
            expected: expected,
            actual: "ناقص",
            confidence: 1.0,
          ),
        );
      }
    }

    for (int i = pairCount; i < insertions.length; i++) {
      final actual = insertions[i].text;
      final position = insertions[i].position;
      final wordInfo = findWordAtPosition(position);
      final word = wordInfo[0] as String;
      final wordIndex = wordInfo[1] as int;
      final charIndex = wordInfo[2] as int?;

      final maddCount = actual.runes
          .where((r) => _maddChars.contains(String.fromCharCode(r)))
          .length;
      final harakaCount = actual.runes
          .where((r) => _harakatChars.contains(String.fromCharCode(r)))
          .length;

      if (maddCount > 0) {
        errors.add(
          TajweedError(
            phoneme: actual,
            expectedPhoneme: actual,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "المد",
            expected: "بدون مد زائد",
            actual: "مد زائد ($maddCount حرف)",
            confidence: 1.0,
          ),
        );
      } else if (harakaCount > 0) {
        final letter = findLetterAtPosition(position);
        errors.add(
          TajweedError(
            phoneme: letter.isEmpty ? actual : letter,
            expectedPhoneme: letter.isEmpty ? actual : letter,
            word: word,
            wordIndex: wordIndex,
            charIndex: charIndex,
            rule: "الحركات",
            expected: "بدون",
            actual: _harakaName(actual),
            confidence: 1.0,
          ),
        );
      } else {
        errors.add(
          TajweedError(
            phoneme: actual,
            expectedPhoneme: actual,
            word: word,
            wordIndex: wordIndex,
            rule: "الحروف",
            expected: "بدون",
            actual: actual,
            confidence: 1.0,
          ),
        );
      }
    }

    return errors;
  }

  static List<WordModel> buildFrom(dynamic verse, MuaalemResponse? response) {
    debugPrint(
      '🔧 [WordModel.buildFrom] uthmaniWords=${verse.uthmaniWords.length} cleanWords=${verse.cleanWords.length}',
    );

    Map<int, int> indexToWordMapping = {};
    if (response != null) {
      final wordsToMap = verse.cleanWords.length == verse.uthmaniWords.length
          ? verse.cleanWords
          : verse.uthmaniWords;

      if (response.expectedSifat != null &&
          response.expectedSifat!.isNotEmpty) {
        indexToWordMapping = _buildIndexToWordMapping(
          response.expectedSifat!,
          wordsToMap,
        );
      } else if (response.sifat.isNotEmpty) {
        indexToWordMapping = _buildIndexToWordMapping(
          response.sifat,
          wordsToMap,
        );
      }
    }

    final uthmaniErrorMap = <int, List<TajweedError>>{};
    if (response?.sifatErrors != null) {
      for (final err in response!.sifatErrors!) {
        for (final attrErr in err.errors) {
          int? charIndex;
          if (response.phonemesByWord != null) {
            try {
              final wp = response.phonemesByWord!.firstWhere(
                (w) => w.containsIndex(err.index),
              );
              charIndex = err.index - wp.sifatStart;
            } catch (_) {}
          }

          final tError = TajweedError(
            phoneme: err.expectedPhoneme.isNotEmpty
                ? err.expectedPhoneme
                : err.phoneme, // Show expected phoneme exactly like iOS
            expectedPhoneme: err.expectedPhoneme,
            word: '',
            charIndex: charIndex,
            rule: attrErr.attributeAr.isNotEmpty
                ? attrErr.attributeAr
                : attrErr.attribute,
            expected: translateSifa(attrErr.expected),
            actual: translateSifa(attrErr.actual),
            confidence: attrErr.prob,
          );
          final mappedIndex = indexToWordMapping[err.index];
          if (mappedIndex != null &&
              mappedIndex >= 0 &&
              mappedIndex < verse.uthmaniWords.length) {
            uthmaniErrorMap.putIfAbsent(mappedIndex, () => []).add(tError);
          }
        }
      }
    }

    // Add phonemeDiff Harakat/Madd errors
    if (response != null) {
      final maddErrors = _detectMaddErrors(verse, response);
      for (final err in maddErrors) {
        if (err.wordIndex != null &&
            err.wordIndex! >= 0 &&
            err.wordIndex! < verse.uthmaniWords.length) {
          uthmaniErrorMap.putIfAbsent(err.wordIndex!, () => []).add(err);
        }
      }
    }

    final words = <WordModel>[];
    for (int i = 0; i < verse.uthmaniWords.length; i++) {
      final errors = uthmaniErrorMap[i] ?? [];
      double? startMs;
      double? endMs;
      if (response != null && response.phonemesByWord != null) {
        try {
          final wp = response.phonemesByWord!.firstWhere(
            (w) => w.wordIndex == i,
          );
          if (wp.startMs != null) {
            startMs = wp.startMs;
            endMs = wp.endMs;
          } else {
            if (wp.sifatStart >= 0 && wp.sifatStart < response.sifat.length) {
              startMs = response.sifat[wp.sifatStart].startMs;
            }
            if (wp.sifatEnd >= 0 && wp.sifatEnd < response.sifat.length) {
              endMs = response.sifat[wp.sifatEnd].endMs;
            }
          }
        } catch (_) {}
      }
      words.add(
        WordModel(
          index: i,
          text: verse.uthmaniWords[i],
          cleanText: verse.cleanWords.length > i
              ? verse.cleanWords[i]
              : verse.uthmaniWords[i],
          hasError: errors.isNotEmpty,
          sifatErrors: errors,
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

    final errorCount = words.where((w) => w.hasError).length;
    debugPrint(
      '🔧 [WordModel.buildFrom] Built ${words.length} words, $errorCount with errors',
    );
    return words;
  }
}

// ─── InteractiveVerse ────────────────────────────────────────────────────────
