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
  final int lookBackWords;
  final int retryLookAheadWords;
  final int retryLookBackWords;
  final bool isTajweedEnabled;

  final List<WordMatchStatus> statuses;
  final List<List<ReciterError>?> errors;

  final List<String> _rawExpected;
  final List<String> _normalizedExpected;

  final List<int> _flatR;
  final List<int> _rPhoneToWord;

  int _wordCursor = 0;
  int _asrCursor = 0;

  String _accumNorm = '';
  String _accumRaw = '';
  bool _isFirstMatch = true;

  PhoneticWordTracker({
    required this.expectedPhonemes,
    this.matchThreshold = 0.25,
    this.relaxedMatchThreshold = 0.35,
    this.lookAheadWords = 10,
    this.lookBackWords = 30,
    this.retryLookAheadWords = 40,
    this.retryLookBackWords = 30,
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
       _rPhoneToWord = [] {
    for (int w = 0; w < _normalizedExpected.length; w++) {
      String word = _normalizedExpected[w];
      for (int i = 0; i < word.length; i++) {
        _flatR.add(word.codeUnitAt(i));
        _rPhoneToWord.add(w);
      }
    }
  }

  bool get isComplete => _wordCursor >= expectedPhonemes.length;
  int get cursor => _wordCursor;

  double _getSubCost(int c1, int c2) {
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
    if (alifs.contains(minC) && alifs.contains(maxC)) return 0.25;

    if (minC == 0x0629 && maxC == 0x062A) return 0.25;
    if (minC == 0x0633 && maxC == 0x0635) return 0.25;
    if (minC == 0x062A && maxC == 0x0637) return 0.25;
    if (minC == 0x0630 && maxC == 0x0638) return 0.25;
    if (minC == 0x062F && maxC == 0x0636) return 0.25;
    if (minC == 0x0630 && maxC == 0x0632) return 0.25;
    if (minC == 0x062D && maxC == 0x0647) return 0.25;
    if (minC == 0x062D && maxC == 0x062E) return 0.25;
    if (minC == 0x0643 && maxC == 0x0642) return 0.25;
    if (minC == 0x0645 && maxC == 0x0646) return 0.25;
    if (minC == 0x0644 && maxC == 0x0646) return 0.25;

    return 1.0;
  }

  _DpOutcome _alignWraparound3D(
    List<int> P,
    List<int> R,
    List<int> rPhoneToWord,
    int expectedWord,
    double priorWeight,
    int maxWraps,
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

    int K = maxWraps;
    double wrapPenalty = 3.5;
    double wrapSpanWeight = 0.1;
    int BIG_W = 999999;

    var dp = List.generate(
      m + 1,
      (_) => List.generate(K + 1, (_) => List.filled(n + 1, INF)),
    );
    var startArr = List.generate(
      m + 1,
      (_) => List.generate(K + 1, (_) => List.filled(n + 1, -1)),
    );
    var iStartArr = List.generate(
      m + 1,
      (_) => List.generate(K + 1, (_) => List.filled(n + 1, -1)),
    );
    var maxJArr = List.generate(
      m + 1,
      (_) => List.generate(K + 1, (_) => List.filled(n + 1, -1)),
    );
    var minWArr = List.generate(
      m + 1,
      (_) => List.generate(K + 1, (_) => List.filled(n + 1, BIG_W)),
    );

    for (int j in wordStarts) {
      dp[0][0][j] = 0.0;
      startArr[0][0][j] = j;
      iStartArr[0][0][j] = 0;
      maxJArr[0][0][j] = j;
      minWArr[0][0][j] = j < n ? rPhoneToWord[j] : BIG_W;
    }

    double bestScore = INF;
    int? bestI;
    int? bestJ;
    int? bestJStart;
    double bestCostVal = INF;
    double bestNorm = INF;
    int bestMaxJ = 0;

    for (int i = 1; i <= m; i++) {
      for (int k = 0; k <= K; k++) {
        if (k == 0 && wordStarts.contains(0)) {
          dp[i][k][0] = 0.0; // Free skip of audio prefix for the first expected word
          startArr[i][k][0] = 0;
          iStartArr[i][k][0] = i;
          maxJArr[i][k][0] = 0;
          minWArr[i][k][0] = minWArr[i - 1][k][0];
        }

        for (int j = 1; j <= n; j++) {
          double delOpt = dp[i - 1][k][j] < INF ? dp[i - 1][k][j] + 1.0 : INF;
          double insOpt = dp[i][k][j - 1] < INF ? dp[i][k][j - 1] + 1.0 : INF;
          double subOpt = dp[i - 1][k][j - 1] < INF
              ? dp[i - 1][k][j - 1] + _getSubCost(P[i - 1], R[j - 1])
              : INF;

          double best = subOpt;
          if (delOpt < best) best = delOpt;
          if (insOpt < best) best = insOpt;

          if (best < INF) {
            dp[i][k][j] = best;
            int wJ = j > 0 ? rPhoneToWord[j - 1] : BIG_W;
            if (best == subOpt) {
              startArr[i][k][j] = startArr[i - 1][k][j - 1];
              iStartArr[i][k][j] = iStartArr[i - 1][k][j - 1];
              maxJArr[i][k][j] = max(maxJArr[i - 1][k][j - 1], j);
              minWArr[i][k][j] = min(minWArr[i - 1][k][j - 1], wJ);
            } else if (best == delOpt) {
              startArr[i][k][j] = startArr[i - 1][k][j];
              iStartArr[i][k][j] = iStartArr[i - 1][k][j];
              maxJArr[i][k][j] = maxJArr[i - 1][k][j];
              minWArr[i][k][j] = minWArr[i - 1][k][j];
            } else {
              startArr[i][k][j] = startArr[i][k][j - 1];
              iStartArr[i][k][j] = iStartArr[i][k][j - 1];
              maxJArr[i][k][j] = max(maxJArr[i][k][j - 1], j);
              minWArr[i][k][j] = min(minWArr[i][k][j - 1], wJ);
            }
          }
        }
      }

      for (int k = 0; k < K; k++) {
        for (int jEnd in wordEnds) {
          if (dp[i][k][jEnd] >= INF) continue;
          double costAtEnd = dp[i][k][jEnd];

          for (int jS in wordStarts) {
            if (jS >= jEnd) continue;

            int wordSpan = (rPhoneToWord[jEnd - 1] - rPhoneToWord[jS]).abs();
            double newCost =
                costAtEnd + wrapPenalty + (wrapSpanWeight * wordSpan);

            if (newCost < dp[i][k + 1][jS]) {
              dp[i][k + 1][jS] = newCost;
              startArr[i][k + 1][jS] = startArr[i][k][jEnd];
              iStartArr[i][k + 1][jS] = iStartArr[i][k][jEnd];
              maxJArr[i][k + 1][jS] = max(maxJArr[i][k][jEnd], jEnd);
              minWArr[i][k + 1][jS] = min(
                minWArr[i][k][jEnd],
                rPhoneToWord[jS],
              );
            }
          }
        }

        for (int j = 1; j <= n; j++) {
          double insOpt = dp[i][k + 1][j - 1] < INF
              ? dp[i][k + 1][j - 1] + 1.0
              : INF;
          if (insOpt < dp[i][k + 1][j]) {
            dp[i][k + 1][j] = insOpt;
            startArr[i][k + 1][j] = startArr[i][k + 1][j - 1];
            iStartArr[i][k + 1][j] = iStartArr[i][k + 1][j - 1];
            maxJArr[i][k + 1][j] = max(maxJArr[i][k + 1][j - 1], j);
            int wJ = j > 0 ? rPhoneToWord[j - 1] : BIG_W;
            minWArr[i][k + 1][j] = min(minWArr[i][k + 1][j - 1], wJ);
          }
        }
      }
    } // End of i loop

    // Best-match selection
    for (int k = 0; k <= K; k++) {
      for (int j = 1; j <= n; j++) {
        if (!wordEnds.contains(j)) continue;
        if (dp[m][k][j] >= INF) continue;

        double dist = dp[m][k][j];
        int jS = startArr[m][k][j];
        int iS = iStartArr[m][k][j];
        if (jS < 0 || iS < 0) continue;

        int mj = maxJArr[m][k][j];
        int refLen = max(mj, j) - jS;
        if (refLen <= 0) continue;
        
        int audioLen = m - iS;
        int denom = max(audioLen, refLen);
        if (denom < 1) denom = 1;

        double pc =
            dist - (k * wrapPenalty); // matching qua_sdk additive default
        double nd = pc / denom;

        int sw = jS < n ? rPhoneToWord[jS] : rPhoneToWord[j - 1];
        int mw = minWArr[m][k][j];
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

    if (normNew.length < _accumNorm.length) {
      _accumNorm = KmpStitcher.mergeText(_accumNorm, normNew);
      _accumRaw = KmpStitcher.mergeText(_accumRaw, asrText);
    } else {
      _accumNorm = normNew;
      _accumRaw = asrText;
    }
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
      int winStart = max(0, _wordCursor - lookBackWords);
      int maxLookahead = lookAheadWords;
      int winEnd = min(
        expectedPhonemes.length,
        _wordCursor + estWords + maxLookahead,
      );

      if (winStart < expectedPhonemes.length) {
        List<int> R = [];
        List<int> rPhoneToWordLocal = [];

        for (int i = 0; i < _rPhoneToWord.length; i++) {
          if (_rPhoneToWord[i] >= winStart && _rPhoneToWord[i] < winEnd) {
            R.add(_flatR[i]);
            rPhoneToWordLocal.add(_rPhoneToWord[i]);
          }
        }

        if (R.isNotEmpty) {
          double priorWeight = 0.005;
          int maxWraps = 1;

          print('[Tracker] ----- NEW DP EVALUATION -----');
          print(
            '[Tracker] Cursor: $_wordCursor | Window: $winStart to ${winEnd - 1}',
          );
          print('[Tracker] Audio (P): ${String.fromCharCodes(P)}');
          print('[Tracker] Expected (R): ${String.fromCharCodes(R)}');

          _DpOutcome match = _alignWraparound3D(
            P,
            R,
            rPhoneToWordLocal,
            _wordCursor,
            priorWeight,
            maxWraps,
          );

          // Detect if the current word is one of the Muqatta'at (disjointed letters)
          // Note: _rawExpected contains phonetic spelled-out words (e.g. 'ءَلِفلَاامِۦۦم')
          bool isMuqattaat = false;
          if (_wordCursor < _rawExpected.length) {
            String cleanCurrentWord = _rawExpected[_wordCursor].replaceAll(RegExp(r'[^ء-ي]'), '');
            if (cleanCurrentWord.startsWith('ءلف') || // الم, المص, المر, الر
                cleanCurrentWord.startsWith('كاف') || // كهيعص
                cleanCurrentWord.startsWith('طا') ||  // طه, طسم, طس
                cleanCurrentWord.startsWith('يا') ||  // يس
                cleanCurrentWord.startsWith('صاد') || // ص
                cleanCurrentWord.startsWith('حا') ||  // حم, حمعسق
                cleanCurrentWord.startsWith('عين') || // عسق
                cleanCurrentWord.startsWith('قاف') || // ق
                cleanCurrentWord.startsWith('نون')) { // ن
              isMuqattaat = true;
            }
          }

          double effectiveThreshold = isMuqattaat ? max(0.60, matchThreshold) : matchThreshold;

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
                bool found = false;
                while (pIdx >= P.length - lookback && pIdx >= 0) {
                  if (_getSubCost(P[pIdx], expectedChar) < 0.5) {
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

            if (isTajweedEnabled && isLastWord && !hasExactTail && !forceCommit) {
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
              statuses[w] = WordMatchStatus.correct;
              errors[w] = [];
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
    _accumNorm = '';
    _isFirstMatch = true;

    for (int i = 0; i < statuses.length; i++) {
      statuses[i] = WordMatchStatus.pending;
      errors[i] = null;
    }
  }
}

class KmpStitcher {
  static List<int> computePrefixFunction(String pattern) {
    if (pattern.isEmpty) return [];

    Int32List pi = Int32List(pattern.length);
    int k = 0;

    for (int q = 1; q < pattern.length; q++) {
      while (k > 0 && pattern.codeUnitAt(k) != pattern.codeUnitAt(q)) {
        k = pi[k - 1];
      }
      if (pattern.codeUnitAt(k) == pattern.codeUnitAt(q)) {
        k++;
      }
      pi[q] = k;
    }

    return pi;
  }

  static String mergeText(String baseText, String nextText) {
    if (baseText.isEmpty) return nextText;
    if (nextText.isEmpty) return baseText;

    int maxOverlap = baseText.length < nextText.length
        ? baseText.length
        : nextText.length;
    String tail = baseText.substring(baseText.length - maxOverlap);

    List<int> pi = computePrefixFunction(nextText);
    int state = 0;

    for (int i = 0; i < tail.length; i++) {
      int charCode = tail.codeUnitAt(i);
      while (state > 0 && nextText.codeUnitAt(state) != charCode) {
        state = pi[state - 1];
      }
      if (nextText.codeUnitAt(state) == charCode) {
        state++;
      }
    }

    return baseText + nextText.substring(state);
  }
}
