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
  
  _DpOutcome(this.bestI, this.bestJ, this.jStart, this.bestCost, this.normDist);
}

class PhoneticWordTracker {
  final List<String> expectedPhonemes;

  final double matchThreshold;
  final int lookAheadWords;
  final int lookBackWords;
  final bool strictTracking;
  final bool isTajweedEnabled;
  final bool isLookaheadEnabled;

  final List<WordMatchStatus> statuses;
  final List<List<ReciterError>?> errors;

  final List<String> _rawExpected;
  final List<String> _bareExpectedWithoutAl;

  final List<int> _flatR;
  final List<int> _rPhoneToWord;

  int _wordCursor = 0;
  int _asrCursor = 0;

  String _accumNorm = '';
  bool _isFirstMatch = true;

  PhoneticWordTracker({
    required this.expectedPhonemes,
    this.matchThreshold = 0.65,
    this.lookAheadWords = 3,
    this.lookBackWords = 1,
    this.strictTracking = false,
    this.isTajweedEnabled = false,
    this.isLookaheadEnabled = true,
  }) : statuses = List<WordMatchStatus>.filled(
         expectedPhonemes.length,
         WordMatchStatus.pending,
       ),
       errors = List<List<ReciterError>?>.filled(expectedPhonemes.length, null),
       _rawExpected = expectedPhonemes,
       _bareExpectedWithoutAl = expectedPhonemes.map(QuranNormalizer.normalizeWithTashkeel).map(QuranNormalizer.normalizeBare).map((s) => s.startsWith('ال') && s.length > 2 ? s.substring(2) : s).toList(),
       _flatR = [],
       _rPhoneToWord = [] {
    for (int w = 0; w < _bareExpectedWithoutAl.length; w++) {
      String word = _bareExpectedWithoutAl[w];
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

    const alifs = [0x0627, 0x0649, 0x0648, 0x0624, 0x0626, 0x0622, 0x0623, 0x0625, 0x0621];
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
    
    if (m == 0 || n == 0) return _DpOutcome(null, null, null, INF, INF);

    Set<int> wordStarts = {};
    Set<int> wordEnds = {};
    for (int j = 0; j <= n; j++) {
      if (j == 0 || (j < n && rPhoneToWord[j] != rPhoneToWord[j - 1])) {
        wordStarts.add(j);
      }
      if (j == n || (j > 0 && j < n && rPhoneToWord[j] != rPhoneToWord[j - 1])) {
        wordEnds.add(j);
      }
    }

    int K = maxWraps;
    double wrapPenalty = 2.0;

    var dp = List.generate(m + 1, (_) => List.generate(K + 1, (_) => List.filled(n + 1, INF)));
    var startArr = List.generate(m + 1, (_) => List.generate(K + 1, (_) => List.filled(n + 1, -1)));
    var maxJArr = List.generate(m + 1, (_) => List.generate(K + 1, (_) => List.filled(n + 1, -1)));

    for (int j in wordStarts) {
      dp[0][0][j] = 0.0;
      startArr[0][0][j] = j;
      maxJArr[0][0][j] = j;
    }

    double bestScore = INF;
    int? bestI;
    int? bestJ;
    int? bestJStart;
    double bestCostVal = INF;
    double bestNorm = INF;

    for (int i = 1; i <= m; i++) {
      for (int k = 0; k <= K; k++) {
        if (k == 0 && wordStarts.contains(0)) {
          dp[i][k][0] = i * 1.0;
          startArr[i][k][0] = 0;
          maxJArr[i][k][0] = 0;
        }

        for (int j = 1; j <= n; j++) {
          double delOpt = dp[i - 1][k][j] < INF ? dp[i - 1][k][j] + 1.0 : INF;
          double insOpt = dp[i][k][j - 1] < INF ? dp[i][k][j - 1] + 1.0 : INF;
          double subOpt = dp[i - 1][k][j - 1] < INF ? dp[i - 1][k][j - 1] + _getSubCost(P[i - 1], R[j - 1]) : INF;

          double best = subOpt;
          if (delOpt < best) best = delOpt;
          if (insOpt < best) best = insOpt;

          if (best < INF) {
            dp[i][k][j] = best;
            if (best == subOpt) {
              startArr[i][k][j] = startArr[i - 1][k][j - 1];
              maxJArr[i][k][j] = max(maxJArr[i - 1][k][j - 1], j);
            } else if (best == delOpt) {
              startArr[i][k][j] = startArr[i - 1][k][j];
              maxJArr[i][k][j] = maxJArr[i - 1][k][j];
            } else {
              startArr[i][k][j] = startArr[i][k][j - 1];
              maxJArr[i][k][j] = max(maxJArr[i][k][j - 1], j);
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
            double newCost = costAtEnd + wrapPenalty + (0.1 * wordSpan);
            
            if (newCost < dp[i][k + 1][jS]) {
              dp[i][k + 1][jS] = newCost;
              startArr[i][k + 1][jS] = startArr[i][k][jEnd];
              maxJArr[i][k + 1][jS] = max(maxJArr[i][k][jEnd], jEnd);
            }
          }
        }

        for (int j = 1; j <= n; j++) {
          double insOpt = dp[i][k + 1][j - 1] < INF ? dp[i][k + 1][j - 1] + 1.0 : INF;
          if (insOpt < dp[i][k + 1][j]) {
            dp[i][k + 1][j] = insOpt;
            startArr[i][k + 1][j] = startArr[i][k + 1][j - 1];
            maxJArr[i][k + 1][j] = max(maxJArr[i][k + 1][j - 1], j);
          }
        }
      }

      for (int k = 0; k <= K; k++) {
        for (int j = 1; j <= n; j++) {
          if (!wordEnds.contains(j)) continue;
          if (dp[i][k][j] >= INF) continue;

          double dist = dp[i][k][j];
          int jS = startArr[i][k][j];
          if (jS < 0) continue;
          
          int mj = maxJArr[i][k][j];
          int refLen = max(mj, j) - jS;
          if (refLen <= 0) continue;
          
          int denom = max(i, refLen);
          if (denom < 1) denom = 1;

          double pc = dist - (k * wrapPenalty);
          double nd = pc / denom;

          if (strictTracking && nd > 0.0) continue;

          int sw = jS < n ? rPhoneToWord[jS] : rPhoneToWord[j - 1];
          double prior = priorWeight * (sw - expectedWord).abs();
          double score = nd + prior + (k * 0.01);

          if (score < bestScore) {
            bestScore = score;
            bestI = i;
            bestJ = j;
            bestJStart = jS;
            bestCostVal = dist;
            bestNorm = nd;
          } else if (score == bestScore) {
            if (i > (bestI ?? 0)) {
               bestI = i;
               bestJ = j;
               bestJStart = jS;
               bestCostVal = dist;
               bestNorm = nd;
            }
          }
        }
      }
    }

    return _DpOutcome(bestI, bestJ, bestJStart, bestCostVal, bestNorm);
  }

  bool feed(String asrText, {bool isEndpoint = false}) {
    if (isComplete) return false;

    String normNew = QuranNormalizer.normalizeWithTashkeel(asrText);

    if (normNew.length < _accumNorm.length) {
      _accumNorm = KmpStitcher.mergeText(_accumNorm, normNew);
    } else {
      _accumNorm = normNew;
    }
    String activeChunk = _accumNorm.substring(_asrCursor);

    if (activeChunk.length > 250) {
      int excess = activeChunk.length - 250;
      _asrCursor += excess;
      activeChunk = _accumNorm.substring(_asrCursor);
    }

    Int32List bareToRawIndex = Int32List(activeChunk.length);
    Int32List bareChars = Int32List(activeChunk.length);
    int bareLen = 0;
    
    for (int i = 0; i < activeChunk.length; i++) {
      int code = activeChunk.codeUnitAt(i);
      if (code != 0x064E && code != 0x064F && code != 0x0650) {
        bareChars[bareLen] = code;
        bareToRawIndex[bareLen] = i;
        bareLen++;
      }
    }
    
    List<int> P = List<int>.generate(bareLen, (i) => bareChars[i]);

    bool changed = false;

    while (_wordCursor < expectedPhonemes.length && P.isNotEmpty) {
      int estWords = max(1, (P.length / 5.0).round());
      int winStart = max(0, _wordCursor - lookBackWords);
      int maxLookahead = isLookaheadEnabled ? lookAheadWords : 0;
      int winEnd = min(expectedPhonemes.length, _wordCursor + estWords + maxLookahead);

      if (winStart >= expectedPhonemes.length) break;

      List<int> R = [];
      List<int> rPhoneToWordLocal = [];

      for (int i = 0; i < _rPhoneToWord.length; i++) {
        if (_rPhoneToWord[i] >= winStart && _rPhoneToWord[i] < winEnd) {
          R.add(_flatR[i]);
          rPhoneToWordLocal.add(_rPhoneToWord[i]);
        }
      }

      if (R.isEmpty) break;

      double priorWeight = 0.15;
      int maxWraps = P.length >= 8 ? 1 : 0;
      
      print('[Tracker] ----- NEW DP EVALUATION -----');
      print('[Tracker] Cursor: $_wordCursor | Window: $winStart to ${winEnd - 1}');
      print('[Tracker] Audio (P): ${String.fromCharCodes(P)}');
      print('[Tracker] Expected (R): ${String.fromCharCodes(R)}');

      _DpOutcome match = _alignWraparound3D(P, R, rPhoneToWordLocal, _wordCursor, priorWeight, maxWraps);

      print('[Tracker] DP Outcome: bestI=${match.bestI}, bestJ=${match.bestJ}, normDist=${match.normDist.toStringAsFixed(3)} (Threshold: $matchThreshold)');

      if (match.bestI != null && match.bestJ != null && match.normDist <= matchThreshold) {
        
        if (match.bestI == P.length && match.normDist > 0.0 && !isEndpoint) {
           print('[Tracker] -> Wait: Match reached end of active chunk but normDist > 0. User still speaking.');
           break;
        }

        int startWord = rPhoneToWordLocal[match.jStart!];
        int endWord = rPhoneToWordLocal[match.bestJ! - 1];
        
        print('[Tracker] -> COMMIT: Matched words $startWord to $endWord');

        if (!_isFirstMatch && startWord > _wordCursor) {
          print('[Tracker] -> SKIP DETECTED: words $_wordCursor to ${startWord - 1} missing.');
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

        int bestBareL = match.bestI!;
        int rawEnd = bareToRawIndex[bestBareL - 1];
        
        while (rawEnd + 1 < activeChunk.length) {
          int nextCode = activeChunk.codeUnitAt(rawEnd + 1);
          if (nextCode == 0x064E || nextCode == 0x064F || nextCode == 0x0650) {
            rawEnd++;
          } else {
            break;
          }
        }
        
        _asrCursor += rawEnd + 1;
        _wordCursor = endWord + 1;

        activeChunk = _accumNorm.substring(_asrCursor);
        
        bareLen = 0;
        for (int i = 0; i < activeChunk.length; i++) {
          int code = activeChunk.codeUnitAt(i);
          if (code != 0x064E && code != 0x064F && code != 0x0650) {
            bareChars[bareLen] = code;
            bareToRawIndex[bareLen] = i;
            bareLen++;
          }
        }
        P = List<int>.generate(bareLen, (i) => bareChars[i]);

        changed = true;
      } else {
        print('[Tracker] -> FAIL: Score too high or missing bounds.');
        break;
      }
    }

    return changed;
  }

  String get accumulatedNormText => _accumNorm;

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
