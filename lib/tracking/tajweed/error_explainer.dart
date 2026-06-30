import 'dart:math';

import '../word/quran_normalizer.dart';
import 'tajweed_rules.dart';

enum ErrorCategory { tajweed, normal, tashkeel }

enum SpeechErrorType { insert, delete, replace }

class ReciterError {
  final ErrorCategory errorType;
  final SpeechErrorType speechErrorType;
  final String expectedPh;
  final String predictedPh;
  final TajweedRule? expectedRule;
  final TajweedRule? predictedRule;

  ReciterError({
    required this.errorType,
    required this.speechErrorType,
    required this.expectedPh,
    required this.predictedPh,
    this.expectedRule,
    this.predictedRule,
  });

  @override
  String toString() {
    return 'ReciterError(type: $errorType, action: $speechErrorType, expected: "$expectedPh", predicted: "$predictedPh", expectedRule: ${expectedRule?.name.en}, predictedRule: ${predictedRule?.name.en})';
  }
}

class PhonemeGroupAlignment {
  final String opType; // insert, delete, replace, equal
  final int refIdx;
  final int predIdx;

  PhonemeGroupAlignment({
    required this.opType,
    required this.refIdx,
    required this.predIdx,
  });
}

class ErrorExplainer {
  /// Aligns phoneme chunks using the Wagner-Fischer algorithm (Levenshtein distance)
  /// focusing primarily on the first character (the base consonant) of each chunk.
  static List<PhonemeGroupAlignment> _alignPhonemeGroups(
    List<String> refGroups,
    List<String> predGroups,
  ) {
    int n = refGroups.length;
    int m = predGroups.length;

    // Precompute first characters to avoid string operations inside the hot loop
    List<String> refChars = List.generate(n, (i) => refGroups[i].isNotEmpty ? refGroups[i][0] : '');
    List<String> predChars = List.generate(m, (i) => predGroups[i].isNotEmpty ? predGroups[i][0] : '');

    // Create distance matrix
    List<List<int>> dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));

    for (int i = 0; i <= n; i++) dp[i][0] = i;
    for (int j = 0; j <= m; j++) dp[0][j] = j;

    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        int cost = (refChars[i - 1] == predChars[j - 1]) ? 0 : 1;
        
        int del = dp[i - 1][j] + 1;
        int ins = dp[i][j - 1] + 1;
        int sub = dp[i - 1][j - 1] + cost;
        
        dp[i][j] = min(del, min(ins, sub));
      }
    }

    // Traceback to find opcodes
    List<PhonemeGroupAlignment> alignments = [];
    int i = n;
    int j = m;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        int cost = (refChars[i - 1] == predChars[j - 1]) ? 0 : 1;

        if (dp[i][j] == dp[i - 1][j - 1] + cost) {
          alignments.add(
            PhonemeGroupAlignment(
              opType: cost == 0 ? 'equal' : 'replace',
              refIdx: i - 1,
              predIdx: j - 1,
            ),
          );
          i--;
          j--;
          continue;
        }
      }

      if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
        alignments.add(
          PhonemeGroupAlignment(
            opType: 'delete',
            refIdx: i - 1,
            predIdx: j, // or -1
          ),
        );
        i--;
      } else if (j > 0 && dp[i][j] == dp[i][j - 1] + 1) {
        alignments.add(
          PhonemeGroupAlignment(
            opType: 'insert',
            refIdx: i, // or -1
            predIdx: j - 1,
          ),
        );
        j--;
      }
    }

    return alignments.reversed.toList();
  }

  /// Explains errors between a full expected Ayah and a full predicted Ayah string.
  static Map<int, List<ReciterError>> explainAyahError(
    String expectedAyahPh,
    String predictedAyahPh,
    List<String> phonemeWords,
  ) {
    print('\n[ErrorExplainer] === START GLOBAL TAJWEED EVALUATION ===');
    print('[ErrorExplainer] Raw Expected: "$expectedAyahPh"');
    print('[ErrorExplainer] Raw Predicted: "$predictedAyahPh"');

    // 1. Build character-to-word index mapping
    List<int> wordBoundaries = [0];
    String spacelessExpected = '';
    for (String w in phonemeWords) {
      spacelessExpected += w.replaceAll(' ', '');
      wordBoundaries.add(spacelessExpected.length);
    }
    
    // In case expectedAyahPh has spaces, we strip them to match phonemeWords
    expectedAyahPh = expectedAyahPh.replaceAll(' ', '');
    predictedAyahPh = predictedAyahPh.replaceAll(' ', '');

    final refGroups = QuranNormalizer.chunkPhonemes(expectedAyahPh);
    final predGroups = QuranNormalizer.chunkPhonemes(predictedAyahPh);

    // Map each raw chunk to its word index
    List<int> refGroupToWord = [];
    int charCursor = 0;
    for (var chunk in refGroups) {
      int wIdx = 0;
      for (int i = 0; i < phonemeWords.length; i++) {
        if (charCursor >= wordBoundaries[i] && charCursor < wordBoundaries[i+1]) {
          wIdx = i;
          break;
        }
      }
      refGroupToWord.add(wIdx);
      charCursor += chunk.length;
    }

    print('[ErrorExplainer] Reference Groups: $refGroups');
    print('[ErrorExplainer] Predicted Groups: $predGroups');

    // 3. Align Groups
    final alignments = _alignPhonemeGroups(refGroups, predGroups);
    final Map<int, List<ReciterError>> errorsByWord = {};

    for (final align in alignments) {
      String refChunk = align.refIdx >= 0 && align.refIdx < refGroups.length
          ? refGroups[align.refIdx]
          : '';
      String predChunk = align.predIdx >= 0 && align.predIdx < predGroups.length
          ? predGroups[align.predIdx]
          : '';

      int wIdx = align.refIdx >= 0 && align.refIdx < refGroupToWord.length 
          ? refGroupToWord[align.refIdx] 
          : (refGroupToWord.isNotEmpty ? refGroupToWord.last : 0);

      ReciterError? error;

      if (align.opType == 'insert') {
        error = ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.insert,
          expectedPh: '',
          predictedPh: predChunk,
        );
      } else {
        if (align.opType == 'delete' || align.opType == 'replace' || (align.opType == 'equal' && refChunk != predChunk)) {
          // Check for Tajweed rules first for ANY mismatch involving the reference
          TajweedRule? expectedTajweed;
          
          bool isLastWord = wIdx == phonemeWords.length - 1;

          final allRules = [
            Qalqalah(),
            TafkheemRule(),
            HamsRule(),
            LeenMaddRule(),
            isLastWord ? AaredMaddRule() : MaddRule(name: const LangName(ar: "مد", en: "Madd"), goldenLen: refChunk.length),
            Ghonnah(name: const LangName(ar: "غنة", en: "Ghonnah")),
          ];

          bool isValidTajweedVariation = false;

          for (var rule in allRules) {
            if (rule.isPhStrIn(refChunk)) {
              var specificRule = rule.getRelevantRule(refChunk);
              if (specificRule != null) {
                if (specificRule.correctnessType == CorrectnessType.match && !specificRule.match(refChunk, predChunk)) {
                  expectedTajweed = specificRule;
                  print('[ErrorExplainer] Tajweed MATCH error found: ${specificRule.name.en} for ref: $refChunk, pred: $predChunk');
                  break;
                } else if (specificRule.correctnessType == CorrectnessType.count) {
                  int count = specificRule.count(refChunk, predChunk);
                  int expectedCount = specificRule.count(refChunk, refChunk);
                  
                  int requiredCount = expectedCount;
                  if (specificRule.goldenLen > 0) {
                    requiredCount = min(expectedCount, specificRule.goldenLen);
                  }
                  
                  if (expectedCount > 1 && count < requiredCount) {
                    expectedTajweed = specificRule;
                    print('[ErrorExplainer] Tajweed COUNT error found: ${specificRule.name.en}. Expected count >= $requiredCount, got $count. (ref: $refChunk, pred: $predChunk)');
                    break;
                  } else if (expectedCount > 1 && count >= requiredCount) {
                    if (predChunk.isNotEmpty) {
                      String baseChar = predChunk[0];
                      bool isOnlyBase = true;
                      for (int i = 0; i < predChunk.length; i++) {
                         if (predChunk[i] != baseChar) {
                            isOnlyBase = false;
                            break;
                         }
                      }
                      if (isOnlyBase && refChunk.contains(baseChar)) {
                          isValidTajweedVariation = true;
                      }
                    }
                  }
                }
              }
            }
          }

          if (expectedTajweed != null) {
            error = ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete' ? SpeechErrorType.delete : SpeechErrorType.replace,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: expectedTajweed,
            );
          } else if (isValidTajweedVariation) {
            print('[ErrorExplainer] Ignoring valid Tajweed count variation: ref=$refChunk, pred=$predChunk');
          } else {
            if (align.opType == 'delete') {
              error = ReciterError(
                errorType: ErrorCategory.normal,
                speechErrorType: SpeechErrorType.delete,
                expectedPh: refChunk,
                predictedPh: '',
              );
            } else if (align.opType == 'replace') {
              error = ReciterError(
                errorType: ErrorCategory.normal,
                speechErrorType: SpeechErrorType.replace,
                expectedPh: refChunk,
                predictedPh: predChunk,
              );
            } else { // equal but different
              error = ReciterError(
                errorType: ErrorCategory.tashkeel,
                speechErrorType: refChunk.length > predChunk.length
                    ? SpeechErrorType.delete
                    : (refChunk.length < predChunk.length
                          ? SpeechErrorType.insert
                          : SpeechErrorType.replace),
                expectedPh: refChunk,
                predictedPh: predChunk,
              );
            }
          }
        }
      }


      if (error != null) {
        errorsByWord.putIfAbsent(wIdx, () => []).add(error);
      }
    }

    print('[ErrorExplainer] Output Errors By Word Index:');
    if (errorsByWord.isEmpty) {
      print('[ErrorExplainer]   -> No errors found.');
    } else {
      errorsByWord.forEach((wIdx, errs) {
        print('[ErrorExplainer]   -> Word $wIdx: ${errs.map((e) => e.errorType.toString()).toList()}');
      });
    }
    print('[ErrorExplainer] === END GLOBAL TAJWEED EVALUATION ===\n');

    return errorsByWord;
  }

  /// Real-time single-word Tajweed evaluation.
  /// Call this the exact moment the ASR engine commits to a word boundary,
  /// instead of waiting for the full Ayah to finish.
  static List<ReciterError> explainWordError(
    String expectedWordPh,
    String predictedWordPh,
    {bool isLastWordOfAyah = false}
  ) {
    // 1. Chunk just this specific word
    final refGroups = QuranNormalizer.chunkPhonemes(expectedWordPh.replaceAll(' ', ''));
    final predGroups = QuranNormalizer.chunkPhonemes(predictedWordPh.replaceAll(' ', ''));

    // 2. Align the groups for this single word
    final alignments = _alignPhonemeGroups(refGroups, predGroups);
    final List<ReciterError> wordErrors = [];

    // 3. Evaluate rules instantly
    for (final align in alignments) {
      String refChunk = align.refIdx >= 0 && align.refIdx < refGroups.length ? refGroups[align.refIdx] : '';
      String predChunk = align.predIdx >= 0 && align.predIdx < predGroups.length ? predGroups[align.predIdx] : '';

      ReciterError? error;

      if (align.opType == 'insert') {
        error = ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.insert,
          expectedPh: '',
          predictedPh: predChunk,
        );
      } else if (align.opType == 'delete' || align.opType == 'replace' || (align.opType == 'equal' && refChunk != predChunk)) {
        
        TajweedRule? expectedTajweed;
        
        final allRules = [
          Qalqalah(),
          TafkheemRule(),
          HamsRule(),
          LeenMaddRule(),
          isLastWordOfAyah ? AaredMaddRule() : MaddRule(name: const LangName(ar: "مد", en: "Madd"), goldenLen: refChunk.length),
          Ghonnah(name: const LangName(ar: "غنة", en: "Ghonnah")),
        ];

        bool isValidTajweedVariation = false;

        for (var rule in allRules) {
          if (rule.isPhStrIn(refChunk)) {
            var specificRule = rule.getRelevantRule(refChunk);
            if (specificRule != null) {
              if (specificRule.correctnessType == CorrectnessType.match && !specificRule.match(refChunk, predChunk)) {
                expectedTajweed = specificRule;
                break;
              } else if (specificRule.correctnessType == CorrectnessType.count) {
                int count = specificRule.count(refChunk, predChunk);
                int expectedCount = specificRule.count(refChunk, refChunk);
                int requiredCount = specificRule.goldenLen > 0 ? min(expectedCount, specificRule.goldenLen) : expectedCount;
                
                if (expectedCount > 1 && count < requiredCount) {
                  expectedTajweed = specificRule;
                  break;
                } else if (expectedCount > 1 && count >= requiredCount && predChunk.isNotEmpty) {
                  String baseChar = predChunk[0];
                  if (predChunk.split('').every((c) => c == baseChar) && refChunk.contains(baseChar)) {
                    isValidTajweedVariation = true;
                  }
                }
              }
            }
          }
        }

        if (expectedTajweed != null) {
          error = ReciterError(
            errorType: ErrorCategory.tajweed,
            speechErrorType: align.opType == 'delete' ? SpeechErrorType.delete : SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
            expectedRule: expectedTajweed,
          );
        } else if (!isValidTajweedVariation) {
          if (align.opType == 'delete') {
            error = ReciterError(errorType: ErrorCategory.normal, speechErrorType: SpeechErrorType.delete, expectedPh: refChunk, predictedPh: '');
          } else if (align.opType == 'replace') {
            error = ReciterError(errorType: ErrorCategory.normal, speechErrorType: SpeechErrorType.replace, expectedPh: refChunk, predictedPh: predChunk);
          } else {
            error = ReciterError(
              errorType: ErrorCategory.tashkeel,
              speechErrorType: refChunk.length > predChunk.length ? SpeechErrorType.delete : (refChunk.length < predChunk.length ? SpeechErrorType.insert : SpeechErrorType.replace),
              expectedPh: refChunk,
              predictedPh: predChunk,
            );
          }
        }
      }

      if (error != null) {
        wordErrors.add(error);
      }
    }

    return wordErrors;
  }
}

