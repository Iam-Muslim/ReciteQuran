import 'dart:math';

import '../../data/quran_data.dart';
import '../ayah_search/fuzzy_search.dart';
import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'phoneme_alignment_isolate.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Forward Dictation Sequencer (Direct Continuous String Matching)
//
// Per-word sequential matching with anchored consumption:
// 1. Slice the continuous ASR string at the character anchor.
// 2. Try matching the current word. If GREEN → commit, advance anchor & cursor.
// 3. If current word fails, try skip+1 and skip+2 (omission detection).
// 4. If nothing matches → stay NEUTRAL, wait for more text.
// 5. Loop: after each commit, immediately try the next word.
// ═══════════════════════════════════════════════════════════════════════════════

class DictationSequencer {
  final void Function(Map<String, dynamic> event) onEvent;

  // ── Reference ──
  List<int> wordBoundaries = [];
  String fullPhonemes = '';
  bool isTajweed = false;
  int currentSurahNumber = 0;
  List<List<WordTajweedRule>>? surahWordRules;

  // ── ASR Stream ──
  String currentSegmentAsrText = '';
  List<double> currentSegmentTimestamps = [];
  int asrCharAnchor = 0;
  int _trimmedOffset = 0;
  String? _pendingTail;
  int _lastReanchorAttemptOffset = -1;
  int _lastReanchorAttemptLen = -1;

  // ── Tracking ──
  int targetWordCursor = 0;
  final Set<int> committedGreenWords = {};
  final Set<int> committedRedWords = {};
  String? lastMatchedPhoneme;

  // =========================================================================
  // [EARLY MATCHING / FAST WORD COMMITTING - TAJWEED OFF]
  // -------------------------------------------------------------------------
  // Governed dynamically by `config.enableEarlyMatching`.
  // - When FALSE: All early matching, tail reservation, and shield logic are
  //   completely skipped. Sequencer behaves 100% identically to baseline.
  // - When TRUE:  Shield holds upcoming words while trailing Madd/vowels decay.
  // =========================================================================
  final QuranDictationMatcher _matcher = QuranDictationMatcher();
  TrackerConfig config = const TrackerConfig();

  DictationSequencer(this.onEvent);

  /// Updates the tracking configuration dynamically at runtime.
  void updateConfig(TrackerConfig newConfig) {
    config = newConfig;
  }

  int get _wordCount => max(0, wordBoundaries.length - 1);

  void debugLog(String message) {
    final buf = (asrCharAnchor < currentSegmentAsrText.length)
        ? currentSegmentAsrText.substring(asrCharAnchor)
        : '';
    onEvent(DebugLogEvent(message: message, asrBuffer: buf).toMap());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Public API (called from Isolate message handler)
  // ─────────────────────────────────────────────────────────────────────────────

  void setSurahReference(SetSurahReferenceCommand cmd) {
    currentSurahNumber = cmd.surahNumber;
    fullPhonemes = cmd.fullPhonemes.replaceAll(' ', '');
    wordBoundaries = cmd.boundaries;
    isTajweed = cmd.isTajweed;
    surahWordRules = cmd.wordRules;

    committedGreenWords.clear();
    committedRedWords.clear();
    asrCharAnchor = 0;
    _trimmedOffset = 0;
    _pendingTail = null;
    _lastReanchorAttemptOffset = -1;
    _lastReanchorAttemptLen = -1;

    if (cmd.forceClear) {
      currentSegmentAsrText = '';
      currentSegmentTimestamps = [];
    }

    targetWordCursor = cmd.startGlobalWord.clamp(0, _wordCount);
    lastMatchedPhoneme = null;

    debugLog(
      '📖 Surah $currentSurahNumber | $_wordCount words | cursor=$targetWordCursor | tajweed=$isTajweed',
    );

    if (!cmd.forceClear && currentSegmentAsrText.isNotEmpty) {
      _processSequence();
    }
  }

  void jumpToWord(JumpToWordCommand cmd) {
    targetWordCursor = cmd.globalWordIndex.clamp(0, _wordCount);
    currentSegmentAsrText = '';
    currentSegmentTimestamps = [];
    asrCharAnchor = 0;
    _trimmedOffset = 0;
    _pendingTail = null;
    _lastReanchorAttemptOffset = -1;
    _lastReanchorAttemptLen = -1;
    lastMatchedPhoneme = null;
    committedGreenWords.removeWhere((w) => w >= targetWordCursor);
    committedRedWords.removeWhere((w) => w >= targetWordCursor);
    debugLog('🎯 Jumped to word $targetWordCursor');
  }

  void syncStream(SyncStreamCommand cmd) {
    if (cmd.isNewSegment || cmd.asrText.length < _trimmedOffset) {
      currentSegmentAsrText = '';
      currentSegmentTimestamps = [];
      asrCharAnchor = 0;
      _trimmedOffset = 0;
      _pendingTail = null;
      _lastReanchorAttemptOffset = -1;
      _lastReanchorAttemptLen = -1;
      debugLog('🔄 New segment');
    }
    currentSegmentAsrText = cmd.asrText.substring(_trimmedOffset);
    final int tsStart = min(_trimmedOffset, cmd.timestamps.length);
    currentSegmentTimestamps = cmd.timestamps.sublist(tsStart);
    _processSequence();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Core Tracking Loop
  // ─────────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────────
  // [EARLY MATCHING - TAIL DRAIN HELPER: START]
  // Absorbs prolonged Madd vowels or unuttered trailing letters of an early-committed
  // word. If reciter moves on to next word (non-tail phoneme), lifts immediately.
  // ─────────────────────────────────────────────────────────────────────────────
  void _drainPendingTail() {
    if (!config.enableEarlyMatching) {
      _pendingTail = null;
      return;
    }
    if (_pendingTail == null || _pendingTail!.isEmpty) return;
    int tailIdx = 0;
    while (asrCharAnchor < currentSegmentAsrText.length &&
        tailIdx < _pendingTail!.length) {
      final int code = currentSegmentAsrText.codeUnitAt(asrCharAnchor);
      final int expectedCode = _pendingTail!.codeUnitAt(tailIdx);
      if (code == expectedCode) {
        asrCharAnchor++;
        tailIdx++;
      } else if (PhoneticCostEngine.isMaddVowel(expectedCode) &&
          PhoneticCostEngine.isMaddVowel(code)) {
        // Absorbs repeated / prolonged vowel frames without advancing tailIdx
        asrCharAnchor++;
      } else {
        // Non-tail sound arrived (reciter moved on to next word); lift shield immediately
        _pendingTail = null;
        return;
      }
    }
    if (tailIdx >= _pendingTail!.length) {
      _pendingTail = null;
    }
  }
  // [EARLY MATCHING - TAIL DRAIN HELPER: END]
  // ─────────────────────────────────────────────────────────────────────────────

  void _processSequence() {
    final int wordCount = _wordCount;

    while (asrCharAnchor < currentSegmentAsrText.length &&
        targetWordCursor < wordCount) {
      // [EARLY MATCHING - FRONTIER SHIELD: START]
      // When early matching is enabled and Tajweed is OFF, drain unuttered tail
      // phonemes from previous word before matching the next word.
      if (config.enableEarlyMatching && !isTajweed && _pendingTail != null) {
        _drainPendingTail();
        if (_pendingTail != null) break;
      }
      // [EARLY MATCHING - FRONTIER SHIELD: END]

      final unconsumed = currentSegmentAsrText.substring(asrCharAnchor);
      final int tsStart = min(asrCharAnchor, currentSegmentTimestamps.length);
      final unconsumedTs = currentSegmentTimestamps.sublist(tsStart);

      bool matched = false;
      bool waitingForPartial = false;

      // Outer loop: how many words to SKIP (0 = no skip, 1 = skip W, etc.)
      for (
        int skip = 0;
        skip <= config.maxSkipWords && targetWordCursor + skip < wordCount;
        skip++
      ) {
        final int startW = targetWordCursor + skip;

        // Inner loop: try single word first, then try merging with the next word (Wasl handling)
        for (int merge = 1; merge <= 2; merge++) {
          final int endW = startW + merge - 1;
          if (endW >= wordCount) break;

          final int refStart = wordBoundaries[startW];
          final int refEnd = (endW + 1 < wordBoundaries.length)
              ? wordBoundaries[endW + 1]
              : fullPhonemes.length;

          final result = _matcher.matchWord(
            asrText: unconsumed,
            asrTimestamps: unconsumedTs,
            fullPhonemes: fullPhonemes,
            refStart: refStart,
            refEnd: refEnd,
            config: config,
            isTajweed: isTajweed,
          );

          if (result != null) {
            if (result.isPartial) {
              if (skip == 0) {
                waitingForPartial = true;
                break; // Stop looking ahead, wait for next segment
              } else {
                continue; // A future word is partially matched, ignore for now
              }
            }

            if (result.tokensConsumed > 0) {
              // Ensure that merged words are actually legitimate boundary-merges (Wasl/Idgham)
              if (merge > 1 &&
                  !_isValidMerge(result, startW, endW, unconsumed)) {
                continue; // Reject this merge and try another combination
              }

              // 1. Mark skipped words RED
              for (int s = 0; s < skip; s++) {
                _commitRed(targetWordCursor + s, startW);
              }
              // 2. Mark the matched (or merged) words GREEN
              for (int m = 0; m < merge; m++) {
                final w = startW + m;
                _commitGreen(w, result, unconsumed, unconsumedTs);
              }

              asrCharAnchor += result.tokensConsumed;
              targetWordCursor = endW + 1;
              matched = true;
              _lastReanchorAttemptOffset = -1;
              _lastReanchorAttemptLen = -1;

              // ─────────────────────────────────────────────────────────────────
              // [EARLY MATCHING - TAIL RESERVATION: START]
              // -----------------------------------------------------------------
              // If early matching is active and Tajweed is OFF:
              // When a word commits early (before reciter finished trailing letters),
              // reserve the remaining unuttered phonemes as `_pendingTail`.
              // Upcoming words won't be allowed to match against these leftovers.
              // If `enableEarlyMatching == false`, this block is completely skipped.
              // -----------------------------------------------------------------
              if (config.enableEarlyMatching && !isTajweed) {
                final int wordRefEnd = (endW + 1 < wordBoundaries.length)
                    ? wordBoundaries[endW + 1]
                    : fullPhonemes.length;
                int lastMatchedRef = -1;
                for (int k = result.trace.length - 1; k >= 0; k--) {
                  if (result.trace[k].opType != 'delete') {
                    lastMatchedRef = result.trace[k].refIdx;
                    break;
                  }
                }
                if (lastMatchedRef != -1 && lastMatchedRef < wordRefEnd - 1) {
                  _pendingTail = fullPhonemes.substring(
                    lastMatchedRef + 1,
                    wordRefEnd,
                  );
                  _drainPendingTail();
                } else {
                  _pendingTail = null;
                }
              }
              // [EARLY MATCHING - TAIL RESERVATION: END]
              // ─────────────────────────────────────────────────────────────────
              break;
            }
          }
        }

        if (matched || waitingForPartial) break;
      }

      if (!matched) {
        // [AUTO RE-ANCHOR - LOSS OF TRACKING RECOVERY: START]
        // In Dictation mode (Tajweed OFF), recover synchrony when reciter skips ahead.
        // If unconsumed speech exceeds the stall threshold, any local partial match
        // on the current word was merely an accidental prefix collision.
        if (config.enableAutoReanchor && !isTajweed) {
          final int oldCursor = targetWordCursor;
          _attemptAutoReanchor();
          if (targetWordCursor != oldCursor) {
            // Re-anchored: continue loop to immediately test & commit the new word
            continue;
          }
        }
        // [AUTO RE-ANCHOR - LOSS OF TRACKING RECOVERY: END]
        break; // Wait for more ASR text
      }
    }

    // Sliding-window head-trimming:
    // Keep a generous 50-phoneme cushion (~7-9 words) of consumed text.
    // If consumed text exceeds 100 phonemes, trim the oldest text from the head.
    const int keepCushion = 50;
    if (asrCharAnchor > keepCushion + 50) {
      final int trim = asrCharAnchor - keepCushion;
      _trimmedOffset += trim;
      currentSegmentAsrText = currentSegmentAsrText.substring(trim);
      currentSegmentTimestamps = currentSegmentTimestamps.sublist(
        min(trim, currentSegmentTimestamps.length),
      );
      asrCharAnchor = keepCushion;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // [AUTO RE-ANCHORING - RECOVERY HELPER: START]
  // ─────────────────────────────────────────────────────────────────────────────

  int _findWordIndexAtPhonemeOffset(int charOffset) {
    if (wordBoundaries.isEmpty) return 0;
    int low = 0;
    int high = wordBoundaries.length - 1;
    int found = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (wordBoundaries[mid] <= charOffset) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found.clamp(0, _wordCount);
  }

  ({int wordIndex, int dist, int probeOffset})? _probeQueryWindow(
    String queryText,
    int offset,
  ) {
    final int qLen = queryText.length;
    if (qLen < min(18, config.reanchorStallThreshold)) return null;

    final int maxDist = (qLen * 0.22).toInt();
    final List<FuzzyMatch> matches =
        findNearMatches(queryText, fullPhonemes, maxDist);
    if (matches.isEmpty) return null;

    final List<({int wordIndex, int dist})> candidateWords = [];
    for (final m in matches) {
      final int w = _findWordIndexAtPhonemeOffset(m.start);
      if (w != targetWordCursor && w != targetWordCursor + 1) {
        candidateWords.add((wordIndex: w, dist: m.dist));
      }
    }
    if (candidateWords.isEmpty) return null;

    // Sort primarily by edit distance.
    // If edit distances are tied, prioritize forward progression (w > targetWordCursor)
    // and proximity to the current cursor.
    candidateWords.sort((a, b) {
      if (a.dist != b.dist) return a.dist.compareTo(b.dist);
      final bool aForward = a.wordIndex > targetWordCursor;
      final bool bForward = b.wordIndex > targetWordCursor;
      if (aForward != bForward) return aForward ? -1 : 1;
      return (a.wordIndex - targetWordCursor)
          .abs()
          .compareTo((b.wordIndex - targetWordCursor).abs());
    });
    final best = candidateWords[0];

    // Anti-Ambiguity / Mutashabihat Guard:
    // If there is another candidate at a distant verse (> 2 words apart) with a close
    // edit distance (< 3), it is an ambiguous refrain/verse. Suppress the jump!
    for (int i = 1; i < candidateWords.length; i++) {
      final c = candidateWords[i];
      if ((c.wordIndex - best.wordIndex).abs() > 2 && (c.dist - best.dist) < 3) {
        debugLog(
          '⚠️ [RE-ANCHOR AMBIGUITY] Suppressed jump between word ${best.wordIndex} (dist ${best.dist}) and ${c.wordIndex} (dist ${c.dist})',
        );
        return null;
      }
    }

    return (wordIndex: best.wordIndex, dist: best.dist, probeOffset: offset);
  }

  void _attemptAutoReanchor() {
    if (!config.enableAutoReanchor || isTajweed) return;
    if (wordBoundaries.isEmpty || fullPhonemes.isEmpty) return;

    final int unconsumedLen = currentSegmentAsrText.length - asrCharAnchor;
    if (unconsumedLen < config.reanchorStallThreshold) return;

    final int currentTotalLen = currentSegmentAsrText.length;
    if (_lastReanchorAttemptOffset == asrCharAnchor &&
        _lastReanchorAttemptLen == currentTotalLen) {
      return;
    }
    _lastReanchorAttemptOffset = asrCharAnchor;
    _lastReanchorAttemptLen = currentTotalLen;

    final String rawQuery = currentSegmentAsrText.substring(asrCharAnchor);

    // 1. Try full unconsumed query (up to 64 chars, Myers bit-parallel single-word limit)
    // When reciter continues past an ambiguous refrain, the combined multi-verse query
    // resolves the ambiguity uniquely with 100% precision!
    final int fullLen = min(64, rawQuery.length);
    var result = _probeQueryWindow(rawQuery.substring(0, fullLen), 0);

    // 2. If full query is ambiguous or no match, try standard front window (first 36 chars)
    if (result == null && fullLen > 36) {
      result = _probeQueryWindow(rawQuery.substring(0, 36), 0);
    }

    // 3. If front is ambiguous or no match, and buffer has accumulated more speech,
    // probe the latest tail window (~28 chars) where the reciter is currently speaking!
    if (result == null && rawQuery.length > 28) {
      final int tailLen = min(28, rawQuery.length);
      final int tailOffset = rawQuery.length - tailLen;
      result = _probeQueryWindow(rawQuery.substring(tailOffset), tailOffset);
    }

    if (result == null) return;

    debugLog(
      '⚓ [AUTO RE-ANCHOR] Stalled at word $targetWordCursor -> Re-anchoring to word ${result.wordIndex} (dist: ${result.dist}, offset: ${result.probeOffset})',
    );

    asrCharAnchor += result.probeOffset;
    targetWordCursor = result.wordIndex;
    _pendingTail = null;
    lastMatchedPhoneme = null;
    committedGreenWords.removeWhere((w) => w >= targetWordCursor);
    committedRedWords.removeWhere((w) => w >= targetWordCursor);
  }
  // ─────────────────────────────────────────────────────────────────────────────
  // [AUTO RE-ANCHORING - RECOVERY HELPER: END]
  // ─────────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────────
  // Commit Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void _commitGreen(
    int w,
    WordMatchResult result,
    String slicedAsr,
    List<double> slicedTs,
  ) {
    if (committedGreenWords.contains(w)) return;
    committedGreenWords.add(w);
    committedRedWords.remove(w);

    // Tajweed evaluation
    List<Map<String, dynamic>>? tajweedErrors;
    if (isTajweed && result.trace.isNotEmpty) {
      final List<WordTajweedRule> expectedWordRules =
          (surahWordRules != null && w < surahWordRules!.length)
              ? surahWordRules![w]
              : const [];

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: result.trace,
        fullPhonemes: fullPhonemes,
        wordBoundaries: wordBoundaries,
        currentAsrText: slicedAsr,
        trackingTimestamps: slicedTs,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: w,
        nextWordId: w + 1,
        totalAyahWords: max(1, _wordCount),
        expectedWordRules: expectedWordRules,
        config: config,
      );
      if (errors.containsKey(w)) {
        tajweedErrors = errors[w]!.map((e) => e.toMap()).toList();
      }
    }

    final String refText = _getWordReference(w);
    debugLog(
      '✅ [GREEN] Word $w (Ref: "$refText") -> ASR: "${result.cleanAsr}" (cost=${result.pathCost.toStringAsFixed(2)})',
    );

    onEvent(
      WordMatchedEvent(
        wordId: w,
        score: max(0.0, 1.0 - result.pathCost),
        cleanAsr: result.cleanAsr,
        isRed: false,
        isNeutral: false,
        tajweedErrors: tajweedErrors,
      ).toMap(),
    );

    if (w + 1 < wordBoundaries.length && wordBoundaries[w + 1] - 1 < fullPhonemes.length) {
      lastMatchedPhoneme = fullPhonemes[wordBoundaries[w + 1] - 1];
    }
  }

  void _commitRed(int w, int matchedWordIndex) {
    if (committedRedWords.contains(w) || committedGreenWords.contains(w)) {
      return;
    }
    committedRedWords.add(w);

    final String refText = _getWordReference(w);
    final String matchedRefText = _getWordReference(matchedWordIndex);

    debugLog(
      '❌ [RED] Word $w (Ref: "$refText") skipped because lookahead matched Word $matchedWordIndex (Ref: "$matchedRefText")',
    );

    onEvent(
      WordMatchedEvent(
        wordId: w,
        score: 0.0,
        cleanAsr: '',
        isRed: true,
        isNeutral: false,
      ).toMap(),
    );
  }

  String _getWordReference(int w) {
    if (w < 0 || w >= _wordCount) return "";
    final start = wordBoundaries[w];
    final end = (w + 1 < wordBoundaries.length)
        ? wordBoundaries[w + 1]
        : fullPhonemes.length;
    return fullPhonemes.substring(start, min(end, fullPhonemes.length));
  }

  bool _isValidMerge(
    WordMatchResult result,
    int startW,
    int endW,
    String asrText,
  ) {
    if (startW == endW) return true;

    // The merge feature is specifically for Idgham, Iqlab, Wasl, etc., which happen at the BOUNDARIES.
    for (int w = startW; w <= endW; w++) {
      final int refStart = wordBoundaries[w];
      final int refEnd = (w + 1 < wordBoundaries.length)
          ? wordBoundaries[w + 1]
          : fullPhonemes.length;
      final int wordLen = refEnd - refStart;

      final int forgiveStart = (w > startW) ? min(2, wordLen ~/ 3) : 0;
      final int forgiveEnd = (w < endW) ? min(2, wordLen ~/ 3) : 0;

      final int coreStart = refStart + forgiveStart;
      final int coreEnd = refEnd - forgiveEnd;
      final int coreLen = coreEnd - coreStart;

      if (coreLen <= 0) continue;

      double coreCost = 0.0;

      for (final align in result.trace) {
        if (align.refIdx >= coreStart && align.refIdx < coreEnd) {
          if (align.opType == 'delete') {
            coreCost += config.standardDeletionCost;
          } else if (align.opType == 'replace') {
            if (align.predIdx >= 0 &&
                align.refIdx >= 0 &&
                align.predIdx < asrText.length) {
              final int asrCode = asrText.codeUnitAt(align.predIdx);
              final int refCode = fullPhonemes.codeUnitAt(align.refIdx);
              coreCost += PhoneticCostEngine.getSubstitutionCost(asrCode, refCode);
            } else {
              coreCost += config.standardInsertionCost;
            }
          }
        }
      }

      if ((coreCost / coreLen) > config.defaultMaxPathCost) {
        return false;
      }
    }
    return true;
  }
}
