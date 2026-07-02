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
  final double? expectedDuration;
  final double? actualDuration;

  ReciterError({
    required this.errorType,
    required this.speechErrorType,
    required this.expectedPh,
    required this.predictedPh,
    this.expectedRule,
    this.predictedRule,
    this.expectedDuration,
    this.actualDuration,
  });

  @override
  String toString() {
    return 'ReciterError(type: $errorType, action: $speechErrorType, expected: "$expectedPh", predicted: "$predictedPh", expectedRule: ${expectedRule?.name.en}, predictedRule: ${predictedRule?.name.en}, expDur: $expectedDuration, actDur: $actualDuration)';
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
    List<String> refChars = List.generate(
      n,
      (i) => refGroups[i].isNotEmpty ? refGroups[i][0] : '',
    );
    List<String> predChars = List.generate(
      m,
      (i) => predGroups[i].isNotEmpty ? predGroups[i][0] : '',
    );

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

  static Map<int, List<ReciterError>> explainAyahError(
    List<String> phonemeWords,
    List<String> predictedWordsPh,
    List<List<double>> predictedWordDurations,
  ) {
    final Map<int, List<ReciterError>> errorsByWord = {};

    for (int wIdx = 0; wIdx < phonemeWords.length; wIdx++) {
      String expectedWord = phonemeWords[wIdx].replaceAll(' ', '');
      String predictedWord = '';
      if (wIdx < predictedWordsPh.length) {
        predictedWord = predictedWordsPh[wIdx].replaceAll(' ', '');
      }

      // Skip words not yet matched
      if (predictedWord.isEmpty) continue;

      List<double> wordDurations = [];
      if (wIdx < predictedWordDurations.length) {
        wordDurations = predictedWordDurations[wIdx];
      }

      final refGroups = QuranNormalizer.chunkPhonemes(expectedWord);

      // Append the first chunk of the next word for boundary rules (Idgham etc)
      bool hasBoundaryContext = false;
      if (wIdx < phonemeWords.length - 1) {
        String nextWord = phonemeWords[wIdx + 1].replaceAll(' ', '');
        if (nextWord.isNotEmpty) {
          final nextChunks = QuranNormalizer.chunkPhonemes(nextWord);
          if (nextChunks.isNotEmpty) {
            refGroups.add(nextChunks.first);
            hasBoundaryContext = true;
          }
        }
      }

      final predGroups = QuranNormalizer.chunkPhonemes(predictedWord);
      final alignments = _alignPhonemeGroups(refGroups, predGroups);
      final List<String> wordErrorDesc = [];

      for (final align in alignments) {
        if (hasBoundaryContext && align.refIdx == refGroups.length - 1)
          continue;

        String refChunk = align.refIdx >= 0 && align.refIdx < refGroups.length
            ? refGroups[align.refIdx]
            : '';
        String predChunk =
            align.predIdx >= 0 && align.predIdx < predGroups.length
            ? predGroups[align.predIdx]
            : '';

        double chunkDuration = 0.0;
        if (predChunk.isNotEmpty && align.predIdx >= 0) {
          int charIdx = 0;
          for (int k = 0; k < align.predIdx; k++) {
            charIdx += predGroups[k].length;
          }
          for (int k = 0; k < predChunk.length; k++) {
            if (charIdx + k < wordDurations.length) {
              chunkDuration += wordDurations[charIdx + k];
            }
          }
          if (chunkDuration <= 0.0) chunkDuration = 0.15;
        }

        ReciterError? error;

        if (align.opType == 'insert') {
          error = ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.insert,
            expectedPh: '',
            predictedPh: predChunk,
          );
        } else {
          if (align.opType == 'delete' ||
              align.opType == 'replace' ||
              (align.opType == 'equal' && refChunk != predChunk)) {
            TajweedRule? expectedTajweed;

            //Tashkeel of last letter checking
            if (align.opType == 'equal' &&
                refChunk.isNotEmpty &&
                predChunk.isNotEmpty &&
                refChunk[0] == predChunk[0]) {
              ReciterError tashkeelErr = ReciterError(
                errorType: ErrorCategory.tashkeel,
                speechErrorType: SpeechErrorType.replace,
                expectedPh: refChunk,
                predictedPh: predChunk,
              );
              errorsByWord.putIfAbsent(wIdx, () => []).add(tashkeelErr);
              wordErrorDesc.add('Tashkeel(ref:$refChunk got:$predChunk)');
              continue; // Move to the next phoneme chunk, skipping Tajweed checks for this specific letter
            }

            bool isLastWord = wIdx == phonemeWords.length - 1;

            final allRules = [
              Qalqalah(),
              TafkheemRule(),
              HamsRule(),
              LeenMaddRule(),
              IqlabRule(),
              IkhfaRule(),
              isLastWord
                  ? AaredMaddRule()
                  : MaddRule(
                      name: const LangName(ar: "مد", en: "Madd"),
                      goldenLen: refChunk.length,
                    ),
              Ghonnah(
                name: const LangName(ar: "غنة", en: "Ghonnah"),
                goldenLen: refChunk.length,
              ),
            ];

            bool isValidTajweedVariation = false;
            double? errExpectedDuration;
            double? errActualDuration;

            for (var rule in allRules) {
              if (rule.isPhStrIn(refChunk)) {
                var specificRule = rule.getRelevantRule(refChunk);
                if (specificRule != null) {
                  if (specificRule.correctnessType == CorrectnessType.match &&
                      !specificRule.match(refChunk, predChunk)) {
                    expectedTajweed = specificRule;
                    wordErrorDesc.add(
                      '${specificRule.name.en}(ref:$refChunk pred:$predChunk)',
                    );
                    break;
                  } else if (specificRule.correctnessType ==
                      CorrectnessType.count) {
                    if (specificRule.goldenLen >= 2) {
                      bool hasValidDuration = specificRule.checkDuration(
                        chunkDuration,
                      );
                      if (!hasValidDuration) {
                        expectedTajweed = specificRule;
                        errExpectedDuration = specificRule.goldenLen * 0.20;
                        errActualDuration = chunkDuration;
                        wordErrorDesc.add(
                          '${specificRule.name.en}Duration(ref:$refChunk got:${chunkDuration.toStringAsFixed(2)}s need:${errExpectedDuration.toStringAsFixed(2)}s)',
                        );
                        break;
                      } else {
                        isValidTajweedVariation = true;
                      }
                    } else {
                      isValidTajweedVariation = true;
                    }
                  }
                }
              }
            }

            if (expectedTajweed != null) {
              error = ReciterError(
                errorType: ErrorCategory.tajweed,
                speechErrorType: align.opType == 'delete'
                    ? SpeechErrorType.delete
                    : SpeechErrorType.replace,
                expectedPh: refChunk,
                predictedPh: predChunk,
                expectedRule: expectedTajweed,
                expectedDuration: errExpectedDuration,
                actualDuration: errActualDuration,
              );
            } else if (!isValidTajweedVariation) {
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
              } else {
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
      } // end for align

      // Print word-level summary
      if (wordErrorDesc.isNotEmpty) {
        print(
          '[Tajweed] Word $wIdx | ref:$expectedWord pred:$predictedWord | errors: ${wordErrorDesc.join(", ")}',
        );
      } else {
        print(
          '[Tajweed] Word $wIdx | ref:$expectedWord pred:$predictedWord | OK ✓',
        );
      }
    } // end for wIdx

    return errorsByWord;
  }

  /// Real-time single-word Tajweed evaluation.
  /// Call this the exact moment the ASR engine commits to a word boundary,
  /// instead of waiting for the full Ayah to finish.
  static List<ReciterError> explainWordError(
    String expectedWordPh,
    String predictedWordPh, {
    bool isLastWordOfAyah = false,
  }) {
    // 1. Chunk just this specific word
    final refGroups = QuranNormalizer.chunkPhonemes(
      expectedWordPh.replaceAll(' ', ''),
    );
    final predGroups = QuranNormalizer.chunkPhonemes(
      predictedWordPh.replaceAll(' ', ''),
    );

    // 2. Align the groups for this single word
    final alignments = _alignPhonemeGroups(refGroups, predGroups);
    final List<ReciterError> wordErrors = [];

    // 3. Evaluate rules instantly
    for (final align in alignments) {
      String refChunk = align.refIdx >= 0 && align.refIdx < refGroups.length
          ? refGroups[align.refIdx]
          : '';
      String predChunk = align.predIdx >= 0 && align.predIdx < predGroups.length
          ? predGroups[align.predIdx]
          : '';

      ReciterError? error;

      if (align.opType == 'insert') {
        error = ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.insert,
          expectedPh: '',
          predictedPh: predChunk,
        );
      } else if (align.opType == 'delete' ||
          align.opType == 'replace' ||
          (align.opType == 'equal' && refChunk != predChunk)) {
        //TashkeelError
        if (align.opType == 'equal' &&
            refChunk.isNotEmpty &&
            predChunk.isNotEmpty &&
            refChunk[0] == predChunk[0]) {
          ReciterError tashkeelErr = ReciterError(
            errorType: ErrorCategory.tashkeel,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          );
          wordErrors.add(tashkeelErr);
          continue;
        }
        TajweedRule? expectedTajweed;

        final allRules = [
          Qalqalah(),
          TafkheemRule(),
          HamsRule(),
          LeenMaddRule(),
          isLastWordOfAyah
              ? AaredMaddRule()
              : MaddRule(
                  name: const LangName(ar: "مد", en: "Madd"),
                  goldenLen: refChunk.length,
                ),
          Ghonnah(
            name: const LangName(ar: "غنة", en: "Ghonnah"),
          ),
        ];

        bool isValidTajweedVariation = false;

        for (var rule in allRules) {
          if (rule.isPhStrIn(refChunk)) {
            var specificRule = rule.getRelevantRule(refChunk);
            if (specificRule != null) {
              if (specificRule.correctnessType == CorrectnessType.match &&
                  !specificRule.match(refChunk, predChunk)) {
                expectedTajweed = specificRule;
                break;
              } else if (specificRule.correctnessType ==
                  CorrectnessType.count) {
                int count = specificRule.count(refChunk, predChunk);
                int expectedCount = specificRule.count(refChunk, refChunk);
                int requiredCount = specificRule.goldenLen > 0
                    ? min(expectedCount, specificRule.goldenLen)
                    : expectedCount;

                if (expectedCount > 1 && count < requiredCount) {
                  expectedTajweed = specificRule;
                  break;
                } else if (expectedCount > 1 &&
                    count >= requiredCount &&
                    predChunk.isNotEmpty) {
                  String baseChar = predChunk[0];
                  if (predChunk.split('').every((c) => c == baseChar) &&
                      refChunk.contains(baseChar)) {
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
            speechErrorType: align.opType == 'delete'
                ? SpeechErrorType.delete
                : SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
            expectedRule: expectedTajweed,
          );
        } else if (!isValidTajweedVariation) {
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
          } else {
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

      if (error != null) {
        wordErrors.add(error);
      }
    }

    return wordErrors;
  }
}
