import 'dart:math';
import 'dart:typed_data';

import 'package:the_great_quran/tracking/quran_normalizer.dart';
import 'matchers/error_explainer.dart';

enum WordMatchStatus { pending, correct, wrong, skipped }

class _DpOutcome {
  final int? bestI;
  final int? bestJ;
  final int? jStart;
  final double bestCost;
  final double normDist;
  final int maxJReached;

  _DpOutcome(
    this.bestI,
    this.bestJ,
    this.jStart,
    this.bestCost,
    this.normDist,
    this.maxJReached,
  );
}

class PhoneticWordTracker {
  final List<String> expectedPhonemes;

  final double matchThreshold;
  final double relaxedMatchThreshold;
  final int lookAheadWords;
  final int retryLookAheadWords;
  final bool isTajweedEnabled;

  final List<WordMatchStatus> statuses;
  final List<List<ReciterError>?> errors;

  final List<String> _rawExpected;
  final List<String> _normalizedExpected;

  final List<int> _flatR;
  final List<int> _rPhoneToWord;
  final List<int> _wordStartCharIdx;

  int _wordCursor = 0;
  int _asrCursor = 0;

  String _historyNorm = '';
  String _historyRaw = '';
  String _accumNorm = '';
  String _accumRaw = '';
  bool _isFirstMatch = true;

  PhoneticWordTracker({
    required this.expectedPhonemes,
    this.matchThreshold = 0.15,
    this.relaxedMatchThreshold = 0.25,
    this.lookAheadWords = 2,
    this.retryLookAheadWords = 4,
    this.isTajweedEnabled = false,
  }) : statuses = List<WordMatchStatus>.filled(
         expectedPhonemes.length,
         WordMatchStatus.pending,
       ),
       errors = List<List<ReciterError>?>.filled(expectedPhonemes.length, null),
       _rawExpected = expectedPhonemes,
       _normalizedExpected = expectedPhonemes
           .map(QuranNormalizer.normalizeWithTashkeel)
           .toList(),
       _flatR = [],
       _rPhoneToWord = [],
       _wordStartCharIdx = List<int>.filled(expectedPhonemes.length + 1, 0) {
    int charIdx = 0;
    for (int w = 0; w < _normalizedExpected.length; w++) {
      String word = _normalizedExpected[w];
      _wordStartCharIdx[w] = charIdx;
      charIdx += word.length;
      for (int i = 0; i < word.length; i++) {
        _flatR.add(word.codeUnitAt(i));
        _rPhoneToWord.add(w);
      }
    }
    _wordStartCharIdx[expectedPhonemes.length] = charIdx;
  }

  bool get isComplete => _wordCursor >= expectedPhonemes.length;
  int get cursor => _wordCursor;

  static double _getInsDelCost(int c) {
    // 0x06E6=ۦ, 0x06E5=ۥ, 0x06E7=ۧ
    if (c == 0x06E6 || c == 0x06E5 || c == 0x06E7) return 0.0;
    return 1.0;
  }

  static double _getSubCost(int c1, int c2) {
    if (c1 == c2) return 0.0;
    int minC = c1 < c2 ? c1 : c2;
    int maxC = c1 > c2 ? c1 : c2;
    const alifs = [
      0x0627,
      0x0649,
      0x0648,
      0x0624,
      0x0626,
      0x0622,
      0x0623,
      0x0625,
      0x0621,
    ];
    if (alifs.contains(minC) && alifs.contains(maxC)) return 0.0;
    if (minC == 0x0629 && maxC == 0x062A) return 0.0; // ة / ت
    if (minC == 0x0633 && maxC == 0x0635) return 0.0; // س / ص
    if (minC == 0x062A && maxC == 0x0637) return 0.0; // ت / ط
    if (minC == 0x0630 && maxC == 0x0638) return 0.0; // ذ / ظ
    if (minC == 0x062F && maxC == 0x0636) return 0.0; // د / ض
    if (minC == 0x0630 && maxC == 0x0632) return 0.0; // ذ / ز
    if (minC == 0x0632 && maxC == 0x0638) return 0.0; // ز / ظ
    // if (minC == 0x062D && maxC == 0x0647) return 0.0; // ح / ه
    if (minC == 0x062D && maxC == 0x062E) return 0.0; // ح / خ
    if (minC == 0x0643 && maxC == 0x0642) return 0.0; // ك / ق
    if (minC == 0x0645 && maxC == 0x0646) return 0.0; // م / ن
    return 1.0;
  }

  static _DpOutcome _align2DStatic(
    List<int> P,
    List<int> R,
    List<int> rPhoneToWord,
    int expectedWord,
    double priorWeight,
  ) {
    int m = P.length;
    int n = R.length;
    final double INF = double.infinity;

    if (m == 0 || n == 0) return _DpOutcome(null, null, null, INF, INF, 0);

    Set<int> wordStarts = {};
    Set<int> wordEnds = {};
    for (int j = 0; j <= n; j++) {
      if (j == 0 || (j < n && rPhoneToWord[j] != rPhoneToWord[j - 1])) {
        wordStarts.add(j);
      }
      if (j == n ||
          (j > 0 && j < n && rPhoneToWord[j] != rPhoneToWord[j - 1])) {
        wordEnds.add(j);
      }
    }

    bool targetJStartsContains0 = n > 0 && rPhoneToWord[0] == expectedWord;

    int BIG_W = 999999;

    int colStride = n + 1;
    int totalSize = (m + 1) * colStride;

    Float64List dp = Float64List(totalSize);
    dp.fillRange(0, totalSize, INF);

    Int32List startArr = Int32List(totalSize);
    startArr.fillRange(0, totalSize, -1);

    Int32List iStartArr = Int32List(totalSize);
    iStartArr.fillRange(0, totalSize, -1);

    Int32List maxJArr = Int32List(totalSize);
    maxJArr.fillRange(0, totalSize, -1);

    Int32List minWArr = Int32List(totalSize);
    minWArr.fillRange(0, totalSize, BIG_W);

    for (int j in wordStarts) {
      int curr = j;
      dp[curr] = 0.0;
      startArr[curr] = j;
      iStartArr[curr] = 0;
      maxJArr[curr] = j;
      minWArr[curr] = j < n ? rPhoneToWord[j] : BIG_W;
    }

    double bestScore = INF;
    int? bestI;
    int? bestJ;
    int? bestJStart;
    double bestCostVal = INF;
    double bestNorm = INF;
    int bestMaxJ = 0;

    for (int i = 1; i <= m; i++) {
      int baseCurr = i * colStride;
      int basePrevI = (i - 1) * colStride;

      if (wordStarts.contains(0) && targetJStartsContains0) {
        int curr = baseCurr;
        dp[curr] = 0.0; // Free skip of audio prefix for start of window
        startArr[curr] = 0;
        iStartArr[curr] = i;
        maxJArr[curr] = 0;
        minWArr[curr] = minWArr[basePrevI];
      }

      for (int j = 1; j <= n; j++) {
        int curr = baseCurr + j;
        int prevI = basePrevI + j;
        int prevJ = baseCurr + j - 1;
        int prevIJ = basePrevI + j - 1;

        double delOpt = dp[prevI] < INF
            ? dp[prevI] + _getInsDelCost(P[i - 1])
            : INF;
        double insOpt = dp[prevJ] < INF
            ? dp[prevJ] + _getInsDelCost(R[j - 1])
            : INF;

        double subCost = 1.0;
        if (dp[prevIJ] < INF) {
          subCost = _getSubCost(P[i - 1], R[j - 1]);
        }
        double subOpt = dp[prevIJ] < INF ? dp[prevIJ] + subCost : INF;

        double best = subOpt;
        if (delOpt < best) best = delOpt;
        if (insOpt < best) best = insOpt;

        if (best < INF) {
          dp[curr] = best;
          int wJ = j > 0 ? rPhoneToWord[j - 1] : BIG_W;
          if (best == subOpt) {
            startArr[curr] = startArr[prevIJ];
            iStartArr[curr] = iStartArr[prevIJ];
            maxJArr[curr] = max(maxJArr[prevIJ], j);
            minWArr[curr] = min(minWArr[prevIJ], wJ);
          } else if (best == delOpt) {
            startArr[curr] = startArr[prevI];
            iStartArr[curr] = iStartArr[prevI];
            maxJArr[curr] = maxJArr[prevI];
            minWArr[curr] = minWArr[prevI];
          } else {
            startArr[curr] = startArr[prevJ];
            iStartArr[curr] = iStartArr[prevJ];
            maxJArr[curr] = max(maxJArr[prevJ], j);
            minWArr[curr] = min(minWArr[prevJ], wJ);
          }
        }

        if (wordStarts.contains(j) && rPhoneToWord[j] == expectedWord) {
          dp[curr] = 0.0;
          startArr[curr] = j;
          iStartArr[curr] = i;
          maxJArr[curr] = j;
          minWArr[curr] = rPhoneToWord[j];
        }
      }
    }

    // Best-match selection
    for (int j = 1; j <= n; j++) {
      if (!wordEnds.contains(j)) continue;
      int curr = m * colStride + j;
      if (dp[curr] >= INF) continue;

      double dist = dp[curr];
      int jS = startArr[curr];
      int iS = iStartArr[curr];
      if (jS < 0 || iS < 0) continue;

      int mj = maxJArr[curr];
      int refLen = max(mj, j) - jS;
      if (refLen <= 0) continue;

      int audioLen = m - iS;
      int denom = max(audioLen, refLen);
      if (denom < 1) denom = 1;

      // matching qua_sdk "no_subtract" default mode
      double pc = dist;
      double nd = pc / denom;

      int sw = jS < n ? rPhoneToWord[jS] : rPhoneToWord[j - 1];
      int mw = minWArr[curr];
      int effSw = mw < BIG_W ? min(sw, mw) : sw;
      double prior = priorWeight * (effSw - expectedWord).abs();

      double score = nd + prior;

      if (score < bestScore) {
        bestScore = score;
        bestI = m;
        bestJ = j;
        bestJStart = jS;
        bestCostVal = dist;
        bestNorm = nd;
        bestMaxJ = mj;
      }
    }

    return _DpOutcome(
      bestI,
      bestJ,
      bestJStart,
      bestCostVal,
      bestNorm,
      bestMaxJ,
    );
  }

  bool feed(String asrText, {bool isEndpoint = false}) {
    if (isComplete) return false;

    String normNew = QuranNormalizer.normalizeWithTashkeel(asrText);

    // Concatenate the finalized history with the current active ASR segment
    _accumNorm = _historyNorm + normNew;
    _accumRaw = _historyRaw + asrText;

    String activeChunk = _accumNorm.substring(_asrCursor);

    if (activeChunk.length > 250) {
      int excess = activeChunk.length - 250;
      _asrCursor += excess;
      activeChunk = _accumNorm.substring(_asrCursor);
    }

    List<int> P = activeChunk.codeUnits.toList();

    bool changed = false;

    if (_wordCursor < expectedPhonemes.length && P.isNotEmpty) {
      int estWords = max(1, (P.length / 5.0).round());
      int winStart = _wordCursor;
      int maxLookahead = lookAheadWords;
      int winEnd = min(
        expectedPhonemes.length,
        _wordCursor + estWords + maxLookahead,
      );

      if (winStart < expectedPhonemes.length) {
        int startChar = _wordStartCharIdx[winStart];
        int endChar = _wordStartCharIdx[winEnd];

        List<int> R = _flatR.sublist(startChar, endChar);
        List<int> rPhoneToWordLocal = _rPhoneToWord.sublist(startChar, endChar);

        if (R.isNotEmpty) {
          double priorWeight = 0.005;
          print('[Tracker] ----- NEW DP EVALUATION -----');
          print(
            '[Tracker] Cursor: $_wordCursor | Window: $winStart to ${winEnd - 1}',
          );
          print('[Tracker] Audio (P): ${String.fromCharCodes(P)}');
          print('[Tracker] Expected (R): ${String.fromCharCodes(R)}');

          _DpOutcome match = _align2DStatic(
            P,
            R,
            rPhoneToWordLocal,
            _wordCursor,
            priorWeight,
          );

          // Detect if the current word is one of the Muqatta'at (disjointed letters)
          // Note: _rawExpected contains phonetic spelled-out words (e.g. 'ءَلِفلَاامِۦۦم')
          bool isMuqattaat = false;
          if (_wordCursor < _rawExpected.length) {
            String cleanCurrentWord = _rawExpected[_wordCursor].replaceAll(
              RegExp(r'[^ء-ي]'),
              '',
            );
            if (cleanCurrentWord.startsWith('ءلف') || // الم, المص, المر, الر
                cleanCurrentWord.startsWith('كاف') || // كهيعص
                cleanCurrentWord.startsWith('طا') || // طه, طسم, طس
                cleanCurrentWord.startsWith('يا') || // يس
                cleanCurrentWord.startsWith('صاد') || // ص
                cleanCurrentWord.startsWith('حا') || // حم, حمعسق
                cleanCurrentWord.startsWith('عين') || // عسق
                cleanCurrentWord.startsWith('قاف') || // ق
                cleanCurrentWord.startsWith('نون')) {
              // ن
              isMuqattaat = true;
            }
          }

          double effectiveThreshold = isMuqattaat
              ? max(0.60, matchThreshold)
              : matchThreshold;

          print(
            '[Tracker] DP Outcome: bestI=${match.bestI}, bestJ=${match.bestJ}, normDist=${match.normDist.toStringAsFixed(3)} (Threshold: $effectiveThreshold${isMuqattaat ? ' [Muqatta\'at Relaxed]' : ''})',
          );

          bool isMatchSuccessful =
              match.bestI != null &&
              match.bestJ != null &&
              match.normDist <= effectiveThreshold;

          if (!isMatchSuccessful) {
            // Just a partial failure in streaming; wait for more audio
          }

          if (isMatchSuccessful) {
            int startWord = rPhoneToWordLocal[match.jStart!];
            int endWord = rPhoneToWordLocal[match.bestJ! - 1];
            if (match.maxJReached > match.bestJ!) {
              endWord = rPhoneToWordLocal[match.maxJReached - 1];
            }

            bool isLastWord = endWord == expectedPhonemes.length - 1;
            bool hasExactTail = false;

            if (isLastWord && P.isNotEmpty && R.isNotEmpty) {
              int lastWordStartIdx = R.length - 1;
              while (lastWordStartIdx > 0 &&
                  rPhoneToWordLocal[lastWordStartIdx - 1] == endWord) {
                lastWordStartIdx--;
              }

              int lastWordLength = R.length - lastWordStartIdx;
              int tailLen = min(3, lastWordLength);
              List<int> expectedTail = R.sublist(R.length - tailLen);

              // Lookback increased to 15 to handle deep Madd (e.g. 10+ repeated vowels like ييييييي)
              int lookback = min(expectedTail.length + 15, P.length);
              int pIdx = P.length - 1;
              int matchCount = 0;

              for (int i = expectedTail.length - 1; i >= 0; i--) {
                int expectedChar = expectedTail[i];

                if (_getInsDelCost(expectedChar) == 0.0) {
                  matchCount++;
                  continue;
                }

                bool found = false;
                while (pIdx >= P.length - lookback && pIdx >= 0) {
                  double subCost = _getSubCost(P[pIdx], expectedChar);

                  if (subCost < 0.5) {
                    found = true;
                    pIdx--;
                    matchCount++;
                    break;
                  }
                  pIdx--;
                }
                if (!found) break;
              }

              if (matchCount == expectedTail.length) {
                hasExactTail = true;
              }
            }

            bool forceCommit = isEndpoint || P.length > R.length + 12;

            if (isTajweedEnabled &&
                isLastWord &&
                !hasExactTail &&
                !forceCommit) {
              print(
                '[Tracker] -> DELAY: Waiting for full final word sequence or timeout.',
              );
              endWord--;
              if (endWord < startWord) {
                return false;
              }
            }

            print('[Tracker] -> COMMIT: Matched words $startWord to $endWord');

            if (!_isFirstMatch && startWord > _wordCursor) {
              print(
                '[Tracker] -> SKIP DETECTED: words $_wordCursor to ${startWord - 1} missing.',
              );
              for (int skipped = _wordCursor; skipped < startWord; skipped++) {
                statuses[skipped] = WordMatchStatus.skipped;
                errors[skipped] = [
                  ReciterError(
                    errorType: ErrorCategory.normal,
                    speechErrorType: SpeechErrorType.delete,
                    expectedPh: _rawExpected[skipped],
                    predictedPh: '',
                  ),
                ];
              }
            }
            _isFirstMatch = false;

            for (int w = startWord; w <= endWord; w++) {
              if (w >= _wordCursor) {
                statuses[w] = WordMatchStatus.correct;
                errors[w] = [];
              }
            }

            // No slicing: P represents the full segment, mirroring qua_sdk.
            // We only update the word cursor so the UI updates and the lookahead advances.
            if (endWord + 1 > _wordCursor) {
              _wordCursor = endWord + 1;
              changed = true;
            }
          }
        }
      }
    }

    // If this chunk finalized the ASR segment, commit it to history
    // so the next fresh segment appends properly without losing state.
    if (isEndpoint) {
      _historyNorm += normNew;
      _historyRaw += asrText;
    }

    return changed;
  }

  List<List<ReciterError>?> get errorsList => errors;

  String get accumulatedNormText => _accumNorm;
  String get accumulatedRawText => _accumRaw;

  void clearActiveAudio() {
    if (_asrCursor <= _accumNorm.length) {
      _accumNorm = _accumNorm.substring(0, _asrCursor);
    }
  }

  void reset() {
    _wordCursor = 0;
    _asrCursor = 0;
    _historyNorm = '';
    _historyRaw = '';
    _accumNorm = '';
    _isFirstMatch = true;

    for (int i = 0; i < statuses.length; i++) {
      statuses[i] = WordMatchStatus.pending;
      errors[i] = null;
    }
  }
}
