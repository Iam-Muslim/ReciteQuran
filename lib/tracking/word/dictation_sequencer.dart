import 'dart:math';

import '../../data/quran_data.dart';
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

  // ── Tracking ──
  int targetWordCursor = 0;
  final Set<int> committedGreenWords = {};
  final Set<int> committedRedWords = {};
  String? lastMatchedPhoneme;

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
    lastMatchedPhoneme = null;
    committedGreenWords.removeWhere((w) => w >= targetWordCursor);
    committedRedWords.removeWhere((w) => w >= targetWordCursor);
    debugLog('🎯 Jumped to word $targetWordCursor');
  }

  void syncStream(SyncStreamCommand cmd) {
    if (cmd.isNewSegment) {
      currentSegmentAsrText = '';
      currentSegmentTimestamps = [];
      asrCharAnchor = 0;
      debugLog('🔄 New segment');
    }
    currentSegmentAsrText = cmd.asrText;
    currentSegmentTimestamps = cmd.timestamps;
    _processSequence();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Core Tracking Loop
  // ─────────────────────────────────────────────────────────────────────────────

  void _processSequence() {
    final int wordCount = _wordCount;

    while (asrCharAnchor < currentSegmentAsrText.length &&
        targetWordCursor < wordCount) {
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
              // Lookahead Guard: Never allow a tiny 1-2 character leftover fragment from early break to skip words!
              if (skip > 0 && result.tokensConsumed < 3) {
                continue;
              }

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
              break;
            }
          }
        }

        if (matched || waitingForPartial) break;
      }

      if (!matched) break; // Wait for more ASR text
    }
  }

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
            coreCost += config.costDel;
          } else if (align.opType == 'replace') {
            if (align.predIdx >= 0 &&
                align.refIdx >= 0 &&
                align.predIdx < asrText.length) {
              final int asrCode = asrText.codeUnitAt(align.predIdx);
              final int refCode = fullPhonemes.codeUnitAt(align.refIdx);
              coreCost += PhoneticCostEngine.getSubstitutionCost(asrCode, refCode);
            } else {
              coreCost += config.costIns;
            }
          }
        }
      }

      if ((coreCost / coreLen) > config.maxPathCost) {
        return false;
      }
    }
    return true;
  }
}
