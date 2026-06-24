// lib/tracking/phonetic_word_tracker.dart

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
  int _charCursor = 0;

  String _accumNorm = '';
  int _consumedLen = 0;

  late final List<String> _flatRefPhonemes;
  late final List<int> _rWordIndices;

  // Streaming DP State
  List<double> _dpActiveRow = [];
  static const int _windowRadius = 25; // Window around _charCursor
  
  Map<int, int> _wordStartAsrIndices = {};

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
           .toList(growable: false) {
    _initReferenceArrays();
  }

  void _initReferenceArrays() {
    _flatRefPhonemes = [];
    _rWordIndices = [];

    for (int i = 0; i < _normExpected.length; i++) {
      final wordChars = _normExpected[i].split('');
      for (final char in wordChars) {
        _flatRefPhonemes.add(char);
        _rWordIndices.add(i);
      }
    }
    
    _dpActiveRow = List.filled(_flatRefPhonemes.length + 1, double.infinity);
    _dpActiveRow[0] = 0.0;
    _wordStartAsrIndices[0] = 0;
  }

  bool get isComplete => _wordCursor >= expectedPhonemes.length;
  int get cursor => _wordCursor;

  bool feed(String asrText) {
    if (isComplete) return false;

    final normNew = QuranNormalizer.normalizeBare(asrText);
    
    if (normNew.length <= _consumedLen) return false;
    final newChars = normNew.substring(_consumedLen);
    
    bool changed = false;

    for (int i = 0; i < newChars.length; i++) {
      String predChar = newChars[i];
      int currentAsrIndex = _consumedLen + i;
      
      List<double> nextDpRow = List.filled(_flatRefPhonemes.length + 1, double.infinity);
      List<bool> consumedThisFrame = List.filled(_flatRefPhonemes.length + 1, false);
      
      int windowStart = max(0, _charCursor - _windowRadius);
      int windowEnd = min(_flatRefPhonemes.length, _charCursor + _windowRadius);

      double minCost = double.infinity;

      double currentInsCost = 1.0;
      if (i > 0 && newChars[i - 1] == predChar) {
        currentInsCost = 0.0;
      } else if (i == 0 && _consumedLen > 0 && _accumNorm[_consumedLen - 1] == predChar) {
        currentInsCost = 0.0;
      }

      for (int j = windowStart; j <= windowEnd; j++) {
        // Insertion (consuming predChar without advancing refChar). 
        // Cost is 0 if it's a CTC stutter frame.
        double insCost = _dpActiveRow[j] + currentInsCost;
        
        // Deletion (costs 1)
        double delCost = j > 0 ? nextDpRow[j - 1] + 1.0 : double.infinity;
        
        // Substitution/Match
        double subCost = double.infinity;
        if (j > 0) {
          String refChar = _flatRefPhonemes[j - 1];
          double cost = (refChar == predChar) ? 0.0 : 1.0;
          subCost = _dpActiveRow[j - 1] + cost;
        }

        double best = min(insCost, min(delCost, subCost));

        if (j == 0) {
          // Allow free leading insertions to naturally absorb "Bismillah" or pre-speech noise
          best = min(best, 0.0);
        }

        nextDpRow[j] = best;

        if (best < minCost) {
          minCost = best;
        }
        
        if (best == subCost || best == insCost || j == 0) {
          consumedThisFrame[j] = true;
        }
      }

      // Normalize row and trace furthest robust J
      int furthestJ = _charCursor;
      int furthestConsumedJ = -1;
      for (int j = windowStart; j <= windowEnd; j++) {
        if (nextDpRow[j] < double.infinity) {
          nextDpRow[j] -= minCost; // Normalization prevents cost infinity-lock
          // Allow path drift up to 2.0 errors behind the optimal path
          if (nextDpRow[j] <= 2.0) {
            if (j > furthestJ) {
              furthestJ = j;
            }
            if (consumedThisFrame[j] && j > furthestConsumedJ) {
              furthestConsumedJ = j;
            }
          }
        }
      }

      _dpActiveRow = nextDpRow;

      if (furthestJ > _charCursor) {
        _charCursor = furthestJ;
      }
      
      if (furthestConsumedJ > 0) {
        int newLastMatchedWord = _rWordIndices[furthestConsumedJ - 1];
        for (int w = 1; w <= newLastMatchedWord; w++) {
          if (!_wordStartAsrIndices.containsKey(w)) {
            _wordStartAsrIndices[w] = currentAsrIndex; // Word w starts precisely here
          }
        }
      }
      
      if (furthestConsumedJ == _flatRefPhonemes.length) {
        if (!_wordStartAsrIndices.containsKey(expectedPhonemes.length)) {
          _wordStartAsrIndices[expectedPhonemes.length] = currentAsrIndex + 1;
        }
      }
    }
    
    _accumNorm = normNew;
    _consumedLen = normNew.length;

    if (_charCursor > 0 && _charCursor <= _flatRefPhonemes.length) {
      int activeWordIdx = _charCursor < _flatRefPhonemes.length 
          ? _rWordIndices[_charCursor] 
          : expectedPhonemes.length;

      while (_wordCursor < activeWordIdx) {
        int startAsr = _wordStartAsrIndices[_wordCursor] ?? _consumedLen;
        int endAsr = _wordStartAsrIndices[_wordCursor + 1] ?? _consumedLen;
        
        startAsr = max(0, min(startAsr, _accumNorm.length));
        endAsr = max(startAsr, min(endAsr, _accumNorm.length));
        
        String spokenChunk = _accumNorm.substring(startAsr, endAsr);
        
        if (spokenChunk.isEmpty && statuses[_wordCursor] == WordMatchStatus.pending) {
            // Restore legacy lookahead "skipped" behavior to prevent massive red error blocks
            statuses[_wordCursor] = WordMatchStatus.skipped;
            errors[_wordCursor] = [
              ReciterError(
                errorType: ErrorCategory.normal,
                speechErrorType: SpeechErrorType.delete,
                expectedPh: _rawExpected[_wordCursor],
                predictedPh: '',
              )
            ];
            print('[Streaming DP] Word $_wordCursor skipped entirely.');
            _wordCursor++;
            changed = true;
            continue;
        }

        // 1. We ONLY evaluate simple green/red word boundaries in real-time.
        // No inline Tajweed DP checking is done here anymore.
        statuses[_wordCursor] = WordMatchStatus.correct;
        errors[_wordCursor] = [];
        
        print('[Streaming DP] Word $_wordCursor "${_rawExpected[_wordCursor]}" completed. Spoken slice: "$spokenChunk".');
        
        _wordCursor++;
        changed = true;
      }
    }

    return changed;
  }
  
  String get accumulatedNormText => _accumNorm;

  void reset() {
    _wordCursor = 0;
    _charCursor = 0;
    _consumedLen = 0;
    _accumNorm = '';
    _wordStartAsrIndices.clear();
    
    _dpActiveRow = List.filled(_flatRefPhonemes.length + 1, double.infinity);
    _dpActiveRow[0] = 0.0;
    _wordStartAsrIndices[0] = 0;

    for (int i = 0; i < statuses.length; i++) {
      statuses[i] = WordMatchStatus.pending;
      errors[i] = null;
    }
  }
}
