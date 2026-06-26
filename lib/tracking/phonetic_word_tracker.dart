import 'dart:math';

import 'package:the_great_quran/tracking/quran_normalizer.dart';
import 'matchers/error_explainer.dart';

enum WordMatchStatus { pending, correct, wrong, skipped }

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

  final List<String> _normExpected;
  final List<String> _rawExpected;

  int _wordCursor = 0;
  int _asrCursor = 0;

  String _accumNorm = '';
  bool _isFirstMatch = true;

  PhoneticWordTracker({
    required this.expectedPhonemes,
    this.matchThreshold = 0.65,
    this.lookAheadWords = 3,
    this.lookBackWords = 3,
    this.strictTracking = false,
    this.isTajweedEnabled = false,
    this.isLookaheadEnabled = true,
  }) : statuses = List<WordMatchStatus>.filled(
         expectedPhonemes.length,
         WordMatchStatus.pending,
       ),
       errors = List<List<ReciterError>?>.filled(expectedPhonemes.length, null),
       _rawExpected = expectedPhonemes,
       _normExpected = expectedPhonemes
           .map(QuranNormalizer.normalizeBare)
           .toList(growable: false);

  bool get isComplete => _wordCursor >= expectedPhonemes.length;
  int get cursor => _wordCursor;

  double _calcAccuracy(String s1, String s2) {
    if (s1 == s2) return 1.0;

    if (strictTracking) {
      return 0.0; // If they don't exactly match (checked above), it's a fail in strict mode
    }

    if (s1.length >= 4 && s2.length >= 6) {
      if (s2.startsWith(s1) || s2.endsWith(s1)) {
        return 0.85;
      }
    }

    String w1 = s1.startsWith('ال') ? s1.substring(2) : s1;
    String w2 = s2.startsWith('ال') ? s2.substring(2) : s2;

    int distance = _levenshtein(w1, w2);
    int maxLength = max(w1.length, w2.length);
    return maxLength == 0 ? 1.0 : 1.0 - (distance / maxLength);
  }

  /// Feeds new ASR text into the tracker.
  /// [isEndpoint] indicates if the user stopped speaking (VAD triggered).
  bool feed(String asrText, {bool isEndpoint = false}) {
    if (isComplete) return false;

    // Use full phonetic normalizer (preserves Tashkeel, Shaddah, Madd)
    String normNew = QuranNormalizer.normalizeWithTashkeel(asrText);
    
    // Detect if the ASR engine was externally reset (e.g. safety limits or manual clear)
    if (normNew.length < _accumNorm.length) {
      _asrCursor = 0;
      _accumNorm = '';
    }

    if (normNew.length <= _asrCursor) return false;

    _accumNorm = normNew;
    String activeChunk = _accumNorm.substring(_asrCursor);
    
    // Self-healing rolling buffer: If there is too much unmatched noise (> 150 phonemes), 
    // drop the oldest noise to prevent the tracker from getting permanently stuck behind.
    // Increased to 150 because Tashkeel makes strings naturally longer, and a full wrong verse can be 100 chars.
    if (activeChunk.length > 150) {
      int excess = activeChunk.length - 150;
      _asrCursor += excess;
      activeChunk = _accumNorm.substring(_asrCursor);
    }
    
    bool changed = false;

    // Process new phonemes using Sliding Window Prefix Matcher
    while (_wordCursor < expectedPhonemes.length && activeChunk.isNotEmpty) {
      bool wordCommitted = false;
      
      int maxLookahead = isLookaheadEnabled ? lookAheadWords : 0;
      for (int look = 0; look <= maxLookahead && _wordCursor + look < expectedPhonemes.length; look++) {
        int targetIdx = _wordCursor + look;
        String expectedPhoneme = QuranNormalizer.normalizeWithTashkeel(_normExpected[targetIdx]);
        
        // Skip very short words in lookahead (prevent jitter on و, من, في, لا)
        // Adjust length threshold to 4 because Tashkeel makes short words longer
        if (look > 0 && expectedPhoneme.length <= 4) {
          continue;
        }
        
        double bestAcc = -1.0;
        int bestL = -1;
        int bestStartK = -1;
        
        // Scan the entire active chunk for the target word. 
        // The early break on 'L' ensures this remains O(N) performance.
        int maxStartK = activeChunk.length;
        
        // Find the best matching candidate within the RAW active chunk
        for (int startK = 0; startK < maxStartK; startK++) {
          
          for (int L = 1; L <= activeChunk.length - startK; L++) {
            String rawCandidate = activeChunk.substring(startK, startK + L);
            
            // Optimization: If the candidate is significantly longer than the expected word,
            // it mathematically cannot pass the accuracy threshold. Break early to prevent O(N^2).
            if (rawCandidate.length > expectedPhoneme.length * 1.5 + 4) {
              break; 
            }
            
            double acc = _calcAccuracy(rawCandidate, expectedPhoneme);
            
            // Favor highest accuracy. If tied, favor earlier startK. If tied, favor SHORTER match (leaves text for next word).
            if (acc > bestAcc) {
              bestAcc = acc;
              bestL = L;
              bestStartK = startK;
            } else if (acc == bestAcc) {
              if (startK < bestStartK) {
                bestStartK = startK;
                bestL = L;
              } else if (startK == bestStartK && L < bestL) {
                bestL = L;
              }
            }
          }
        }

        // Require slightly higher threshold if we're jumping ahead (skipping words)
        double requiredThreshold = look > 0 ? matchThreshold + 0.15 : matchThreshold;
        
        if (bestAcc >= requiredThreshold) {
          // If ASR is still outputting the word (candidate reaches the very end of our buffer)
          // and it's not a perfect match yet, we wait for more letters rather than chopping it off prematurely.
          if (bestAcc < 1.0 && (bestStartK + bestL) == activeChunk.length) {
             String rawMatched = activeChunk.substring(bestStartK, bestStartK + bestL);
             String bareMatched = QuranNormalizer.normalizeBare(rawMatched);
             String bareExpected = QuranNormalizer.normalizeBare(expectedPhoneme);
             
             // If the bare consonants match perfectly, the user just dropped a trailing vowel (Waqf).
             bool isConsonantPerfect = (bareMatched == bareExpected);
             
             // If consonants aren't perfect, AND the engine hasn't stopped listening, wait for more text!
             if (!isConsonantPerfect && !isEndpoint) {
                 break; 
             }
          }

          // Commit targetIdx!
          
          // 1. Mark skipped words as RED (unless it's the very first match of a new Ayah, avoiding stale audio errors)
          if (!_isFirstMatch) {
            for (int skipped = 0; skipped < look; skipped++) {
              statuses[_wordCursor + skipped] = WordMatchStatus.skipped;
              errors[_wordCursor + skipped] = [
                ReciterError(
                  errorType: ErrorCategory.normal,
                  speechErrorType: SpeechErrorType.delete,
                  expectedPh: _rawExpected[_wordCursor + skipped],
                  predictedPh: '',
                )
              ];
            }
          }
          _isFirstMatch = false;
          
          // 2. Mark targetIdx as GREEN
          statuses[targetIdx] = WordMatchStatus.correct;
          errors[targetIdx] = [];
          
          String rawMatched = activeChunk.substring(bestStartK, bestStartK + bestL);
          print('[Prefix Sliding Window] Word $targetIdx "${_rawExpected[targetIdx]}" matched. Candidate: "$rawMatched", Acc: $bestAcc');
          
          // 3. Advance cursors (consume garbage + the matched raw length)
          _asrCursor += bestStartK + bestL;
          _wordCursor = targetIdx + 1;
          
          // 4. Update the active chunk to evaluate the remaining tail for the next word
          activeChunk = _accumNorm.substring(_asrCursor);
          
          changed = true;
          wordCommitted = true;
          break; 
        }
      }
      
      // If we couldn't confidently commit any word (current or lookahead), 
      // we stop and wait for more ASR text to arrive.
      if (!wordCommitted) {
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

  int _levenshtein(String s, String t) {
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) v0[i] = i;

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j <= t.length; j++) v0[j] = v1[j];
    }

    return v1[t.length];
  }
}
