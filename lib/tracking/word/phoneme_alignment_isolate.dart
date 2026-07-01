import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'quran_normalizer.dart';

/// Defines the commands sent from the main thread (UI) to the background Isolate.
class IsolateCommands {
  static const int setup = 0;
  static const int feed = 1; // Feed new ASR phonetic stream chunks
  static const int setAyah =
      2; // Initialize a new Ayah with expected phonemes and word boundaries
  static const int shutdown = 3; // Terminate the isolate
  static const int replaceTail = 4; // Backtrack and replace unstable ASR tail
  static const int setTajweedMode = 5; // Toggle tajweed mode
}

/// Represents a single alignment operation between a reference phoneme group
/// (from the correct Uthmani script) and a predicted phoneme group (from the ASR model).
class PhonemeGroupAlignment {
  final String opType; // 'insert', 'delete', 'replace', or 'equal'
  final int refIdx; // Index of the chunk in the reference array (-1 if insert)
  final int predIdx; // Index of the chunk in the predicted array (-1 if delete)

  PhonemeGroupAlignment({
    required this.opType,
    required this.refIdx,
    required this.predIdx,
  });
}

/// This Isolate handles real-time phonetic alignment for the Zipformer CTC ASR.
/// Because the Zipformer CTC outputs a continuous stream of phonemes without spaces,
/// we cannot use simple string splitting. Instead, we use a Wagner-Fischer Levenshtein
/// algorithm to constantly align a sliding window of the incoming ASR phonemes
/// against the expected Uthmani phonemes for the current Ayah.
class PhonemeAlignmentIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;

  // Stream to emit matched word indices back to the UI for highlighting
  final StreamController<Map<String, dynamic>> _wordStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wordStream => _wordStreamController.stream;

  // Stream to emit completed ayah raw ASR back to the UI for Tajweed processing
  final StreamController<String> _ayahCompletedStreamController =
      StreamController<String>.broadcast();
  Stream<String> get ayahCompletedStream =>
      _ayahCompletedStreamController.stream;

  /// Starts the background isolate and sets up the communication ports.
  Future<void> start() async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    _isolate = await Isolate.spawn(_alignmentWorker, receivePort.sendPort);

    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else if (message is Map) {
        if (message['event'] == 'highlight') {
          _wordStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'debug') {
          // Print debug logs coming from the background isolate
          print('[PhonemeAlignmentIsolate] ${message['message']}');
        } else if (message['event'] == 'ayah_completed') {
          _ayahCompletedStreamController.add(message['raw_asr'] as String);
        }
      }
    });

    return completer.future;
  }

  /// Sets the current Ayah to be tracked.
  /// [expectedPhonemes]: The full phonetic representation of the Ayah.
  /// [wordBoundaries]: The character indices in [expectedPhonemes] where each word starts.
  void setAyah(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
  }) {
    _sendPort?.send({
      'cmd': IsolateCommands.setAyah,
      'phonemes': expectedPhonemes,
      'boundaries': wordBoundaries,
      'isTajweed': isTajweed,
      'forceClear': forceClear,
    });
  }

  /// Feeds a new chunk of space-less ASR phonetic output to the isolate.
  void feed(String asrChunk) {
    _sendPort?.send({'cmd': IsolateCommands.feed, 'asr': asrChunk});
  }

  /// Backtracks and replaces the tail of the ASR buffer when the engine corrects itself
  void replaceTail(int backtrack, String newTail) {
    _sendPort?.send({
      'cmd': IsolateCommands.replaceTail,
      'backtrack': backtrack,
      'tail': newTail,
    });
  }

  /// Sets the tajweed mode dynamically.
  void setTajweedMode(bool isTajweed) {
    _sendPort?.send({
      'cmd': IsolateCommands.setTajweedMode,
      'isTajweed': isTajweed,
    });
  }

  /// Shuts down the isolate.
  void stop() {
    _sendPort?.send({'cmd': IsolateCommands.shutdown});
    _wordStreamController.close();
    _ayahCompletedStreamController.close();
    _isolate?.kill();
    _isolate = null;
  }
}

// ── Background Worker ────────────────────────────────────────────────────────

int _getCharSubCost(String c1, String c2) {
  if (c1 == c2) return 0;

  // Common ASR confusion groups for phonetic Arabic output.
  // We treat these substitutions as 0-cost ONLY for word-tracking progression.
  // The ErrorExplainer will later catch this as a real mistake.
  const groups = [
    ['ن', 'م'], // Nasals
    ['ق', 'ك'], // Velar/Uvular stops
    ['ذ', 'ظ', 'ز'], // Sibilants / Interdentals / D
    ['س', 'ص', 'ث'], // S/Th/Sh sounds
    ['ت', 'ط', 'د', 'ض'], // T/D sounds
    //['ه', 'ح', 'خ', 'ع', 'ء', 'أ', 'إ', 'آ', 'ا'], // Throat / Hamza / Alif
    //['ب', 'ف', 'و'], // Labials
    //['ي', 'ى', 'ئ', 'ؤ', 'ء'], // Ya / Hamza variants
  ];

  for (var group in groups) {
    if (group.contains(c1) && group.contains(c2)) {
      return 0; // Low/Zero cost substitution
    }
  }

  return 1; // High cost
}

/// Performs Wagner-Fischer Levenshtein alignment on arrays of phoneme groups.
/// This is much more accurate than aligning raw characters because Arabic
/// phonemes consist of a base consonant plus harakat (e.g. "بِ" is one unit, not two).
List<PhonemeGroupAlignment> _alignPhonemeGroups(
  List<String> refGroups,
  List<String> predGroups,
) {
  int n = refGroups.length;
  int m = predGroups.length;

  // We only compare the first character (the base consonant) for the basic distance matrix.
  // Harakat mismatches will be caught later as "Tajweed/Tashkeel" errors if needed.
  List<String> refChars = List.generate(
    n,
    (i) => refGroups[i].isNotEmpty ? refGroups[i][0] : '',
  );
  List<String> predChars = List.generate(
    m,
    (i) => predGroups[i].isNotEmpty ? predGroups[i][0] : '',
  );

  // dp[i][j] stores the minimum edit distance between first i ref chars and first j pred chars
  List<List<int>> dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));

  dp[0][0] = 0;
  for (int i = 1; i <= n; i++) {
    int delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;
    dp[i][0] = dp[i - 1][0] + delCost;
  }
  for (int j = 1; j <= m; j++) {
    int insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
    dp[0][j] = dp[0][j - 1] + insCost;
  }

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      int cost = _getCharSubCost(refChars[i - 1], predChars[j - 1]);

      int delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;
      int del = dp[i - 1][j] + delCost; // deletion

      // insertion: 0 cost if it's a repeated character (Madd / Vowel Elongation)
      int insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
      int ins = dp[i][j - 1] + insCost; // insertion

      int sub = dp[i - 1][j - 1] + cost; // substitution / equal

      dp[i][j] = min(del, min(ins, sub));
    }
  }

  // Traceback to find the optimal alignment operations
  List<PhonemeGroupAlignment> alignments = [];

  // Semi-Global Alignment: Find the best 'i' (reference end) to start traceback from.
  // This prevents the DP matrix from warping the alignment of the first spoken word
  // just to minimize the deletion penalty of the remaining 10+ reference chunks in the window!
  int bestI = n;
  int minCost = dp[n][m];
  for (int k = 0; k <= n; k++) {
    if (dp[k][m] < minCost) {
      minCost = dp[k][m];
      bestI = k;
    }
  }

  // Add standard deletions for the trailing reference chunks that were skipped
  for (int k = n; k > bestI; k--) {
    alignments.add(
      PhonemeGroupAlignment(
        opType:
            'delete', // standard delete so it correctly penalizes unfinished words
        refIdx: k - 1,
        predIdx: m > 0 ? m - 1 : -1,
      ),
    );
  }

  int i = bestI;
  int j = m;

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0) {
      int cost = _getCharSubCost(refChars[i - 1], predChars[j - 1]);
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

    int insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
    int delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;

    if (i > 0 && dp[i][j] == dp[i - 1][j] + delCost) {
      alignments.add(
        PhonemeGroupAlignment(
          // If delCost == 0 (e.g. repeated character due to Madd), we mark it as 'delete_0'.
          // Why? If we marked it as 'equal', it would artificially inflate the matched character count,
          // causing the similarity score to exceed 100%. By marking it as 'delete_0', we mathematically subtract
          // it from the total expected characters, ensuring the final percentage is perfectly bound to 100%.
          opType: delCost == 0 ? 'delete_0' : 'delete',
          refIdx: i - 1,
          predIdx: j > 0 ? j - 1 : -1,
        ),
      );
      i--;
    } else if (j > 0 && dp[i][j] == dp[i][j - 1] + insCost) {
      alignments.add(
        PhonemeGroupAlignment(
          opType: 'insert',
          refIdx: i > 0 ? i - 1 : -1,
          predIdx: j - 1,
        ),
      );
      j--;
    }
  }

  // Traceback goes backwards, so we reverse it to get chronological order
  return alignments.reversed.toList();
}

/// The main loop running inside the Isolate.
void _alignmentWorker(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  // Ayah State
  String expectedPhonemes = '';
  List<int> wordBoundaries = []; // Character index boundaries for each word
  List<String> refChunks = []; // The expected phonemes, chunked into groups
  List<int> chunkToWordMap = []; // Maps chunk index -> word index
  bool isTajweed = false; // Whether tajweed mode is active

  // Tracking State
  String asrWindow = ''; // The FULL raw ASR string for the current Ayah
  // --- THE POINTER TRICK ---
  // The 'asrConsumedChars' pointer is the secret to preserving the raw ASR string!
  // Instead of physically deleting matched characters from 'asrWindow' (which would destroy the string),
  // we just advance this integer pointer. The sliding window only reads from 'asrConsumedChars' onwards.
  int asrConsumedChars = 0;
  
  // Accumulated clean ASR string that only contains characters successfully matched to the Ayah
  // (filters out stutters, false starts, and background noise)
  String cleanAsr = '';

  int targetChunkCursor =
      0; // Where we currently are in the expected refChunks array
  int currentWordId = 0; // The last word ID we highlighted
  int consecutiveFailures = 0; // How many consecutive ticks with no match

  // Helper to send debug messages to the main thread
  void debugLog(String message) {
    mainSendPort.send({'event': 'debug', 'message': message});
  }

  commandPort.listen((message) {
    if (message is! Map) return;
    int cmd = message['cmd'];

    if (cmd == IsolateCommands.shutdown) {
      commandPort.close();
      return;
    }

    // --- SET AYAH COMMAND ---
    if (cmd == IsolateCommands.setAyah) {
      expectedPhonemes = (message['phonemes'] as String).replaceAll(' ', '');
      wordBoundaries = message['boundaries'] as List<int>;
      isTajweed = message['isTajweed'] as bool? ?? false;

      // 1. Chunk the expected phonemes into consonant+harakat groups
      refChunks = QuranNormalizer.chunkPhonemes(expectedPhonemes);

      // 2. Map every chunk index back to a specific Word index using the character boundaries
      chunkToWordMap = [];
      int charCursor = 0;
      for (var chunk in refChunks) {
        int wIdx = 0;
        for (int i = 0; i < wordBoundaries.length - 1; i++) {
          if (charCursor >= wordBoundaries[i] &&
              charCursor < wordBoundaries[i + 1]) {
            wIdx = i;
            break;
          }
        }
        chunkToWordMap.add(wIdx);
        charCursor += chunk.length;
      }

      bool forceClear = message['forceClear'] as bool? ?? false;

      // To prevent parts from previous ayahs leaking into the new ayah's raw string,
      // we only carry over the UNCONSUMED tail (which belongs to the new ayah).
      String unconsumed = asrConsumedChars < asrWindow.length
          ? asrWindow.substring(asrConsumedChars)
          : '';

      // (Removed sending ayah_completed here to prevent out-of-sync state with main thread)

      asrWindow = forceClear ? '' : unconsumed;
      cleanAsr = '';
      asrConsumedChars = 0;
      consecutiveFailures = 0;

      if (asrWindow.length > 50) {
        asrWindow = asrWindow.substring(asrWindow.length - 50);
      }
      targetChunkCursor = 0;
      currentWordId = 0;

      debugLog('=== NEW AYAH SET ===');
      debugLog('Expected Phonemes: $expectedPhonemes');
      debugLog('Total Ref Chunks: ${refChunks.length}');
      debugLog('Word Boundaries: $wordBoundaries');
    }

    // --- FEED ASR COMMAND ---
    if (cmd == IsolateCommands.feed) {
      String newAsr = message['asr'] as String;
      if (newAsr.isNotEmpty) {
        asrWindow += newAsr;
      }
    }

    // --- REPLACE TAIL COMMAND ---
    if (cmd == IsolateCommands.replaceTail) {
      int backtrack = message['backtrack'] as int;
      String newTail = message['tail'] as String;

      if (backtrack <= asrWindow.length) {
        int newLength = asrWindow.length - backtrack;
        // CRITICAL: Protect characters that have already been matched and consumed!
        if (newLength < asrConsumedChars) {
          newLength = asrConsumedChars;
        }
        asrWindow = asrWindow.substring(0, newLength) + newTail;
      } else {
        asrWindow = asrWindow.substring(0, asrConsumedChars) + newTail;
      }
    }

    // --- SET TAJWEED MODE COMMAND ---
    if (cmd == IsolateCommands.setTajweedMode) {
      isTajweed = message['isTajweed'] as bool;
      debugLog('Tajweed Mode is now: $isTajweed');
      return;
    }

    if (cmd == IsolateCommands.feed || cmd == IsolateCommands.replaceTail) {
      // If we've already tracked everything, stop checking
      if (targetChunkCursor >= refChunks.length) return;
      // --- 1. SLIDING WINDOW SETUP ---
      // We take a small "window" of the expected text (e.g. next 15 chunks)
      int targetWindowEnd = targetChunkCursor + 15;
      if (targetWindowEnd > refChunks.length) {
        targetWindowEnd = refChunks.length;
      }
      List<String> targetWindowChunks = refChunks.sublist(
        targetChunkCursor,
        targetWindowEnd,
      );

      // The word-tracking system only sees the unconsumed portion
      String trackingAsr = asrConsumedChars < asrWindow.length
          ? asrWindow.substring(asrConsumedChars)
          : '';

      // Safety cap: Only search the last 2000 characters to prevent CPU hangs if left on for hours.
      if (trackingAsr.length > 2000) {
        int excess = trackingAsr.length - 2000;
        asrConsumedChars += excess;
        trackingAsr = trackingAsr.substring(excess);
      }

      String currentAsrWindow = trackingAsr;
      List<String> currentAsrChunks = QuranNormalizer.chunkPhonemes(
        currentAsrWindow,
      );

      debugLog('\n--- Alignment Tick ---');
      debugLog('Target Window: ${targetWindowChunks.join(" ")}');
      debugLog('ASR Window: ${currentAsrChunks.join(" ")}');

      // --- 2. PERFORM ALIGNMENT (SLIDING WINDOW) ---
      // Instead of global alignment, slide a window across the ASR buffer to find the best match.
      // This flawlessly ignores hallucinated garbage and stutters!
      int bestAsrStartIdx = 0;
      double bestCurrentWordSim = -1.0;
      double bestSelectionScore = -999.0;
      var alignments = _alignPhonemeGroups(
        targetWindowChunks,
        currentAsrChunks,
      );
      Map<int, int> wordEqualCounts = {};
      Map<int, int> wordTotalCounts = {};

      int windowSize = targetWindowChunks.length + 10;
      int maxStartIdx = currentAsrChunks.length - targetWindowChunks.length;
      if (maxStartIdx < 0) maxStartIdx = 0;

      // Calculate the base total chunks for each word in the target window once,
      // instead of re-calculating it redundantly on every slide!
      Map<int, int> baseWordTotalCounts = {};
      for (int i = 0; i < targetWindowChunks.length; i++) {
        int wIdx = -1;
        if (targetChunkCursor + i < chunkToWordMap.length) {
          wIdx = chunkToWordMap[targetChunkCursor + i];
        }
        if (wIdx != -1) {
          baseWordTotalCounts[wIdx] = (baseWordTotalCounts[wIdx] ?? 0) + 1;
        }
      }

      for (int startIdx = 0; startIdx <= maxStartIdx; startIdx += 3) {
        int endIdx = startIdx + windowSize;
        if (endIdx > currentAsrChunks.length) endIdx = currentAsrChunks.length;

        List<String> asrSubWindow = currentAsrChunks.sublist(startIdx, endIdx);
        var tempAlignments = _alignPhonemeGroups(
          targetWindowChunks,
          asrSubWindow,
        );

        Map<int, int> tempWordEqualCounts = {};
        Map<int, int> tempWordTotalCounts = Map.from(baseWordTotalCounts);

        for (var align in tempAlignments) {
          int wIdx = -1;
          if (align.refIdx >= 0 &&
              targetChunkCursor + align.refIdx < chunkToWordMap.length) {
            wIdx = chunkToWordMap[targetChunkCursor + align.refIdx];
          }
          if (wIdx != -1) {
            if (align.opType == 'equal') {
              tempWordEqualCounts[wIdx] = (tempWordEqualCounts[wIdx] ?? 0) + 1;
            } else if (align.opType == 'delete_0') {
              tempWordTotalCounts[wIdx] = (tempWordTotalCounts[wIdx] ?? 1) - 1;
              if (tempWordTotalCounts[wIdx]! < 1) tempWordTotalCounts[wIdx] = 1;
            }
          }
        }

        int currentWordTotal = tempWordTotalCounts[currentWordId] ?? 1;
        int currentWordEqual = tempWordEqualCounts[currentWordId] ?? 0;
        double rawSim = currentWordEqual / currentWordTotal;

        // --- PRIOR PENALTY (CHRONOLOGICAL ENFORCEMENT) ---
        // If the ASR buffer has 100 chunks of garbage followed by the correct word, the DP matrix might
        // find the perfect word at the very end (startIdx = 80).
        // However, we want to force the tracker to read chronologically. We apply a 2% penalty for every chunk
        // it skips over to find the match.
        // We CAP this penalty at 15%. Why? Because if the true match is at the end (100% rawSim - 15% = 85%),
        // it should still mathematically beat a false garbage match at the front (e.g., 40% rawSim - 0% = 40%).
        double priorPenalty = startIdx * 0.02;
        if (priorPenalty > 0.15) priorPenalty = 0.15;

        double selectionScore = rawSim - priorPenalty;

        if (selectionScore > bestSelectionScore) {
          bestSelectionScore = selectionScore;
          bestCurrentWordSim = rawSim;
          bestAsrStartIdx = startIdx;
          alignments = tempAlignments;
          wordEqualCounts = tempWordEqualCounts;
          wordTotalCounts = tempWordTotalCounts;
        }

        if (selectionScore >= 1.0)
          break; // Found a perfect, zero-penalty match!
      }

      int currentWordTotal = wordTotalCounts[currentWordId] ?? 1;
      int currentWordEqual = wordEqualCounts[currentWordId] ?? 0;
      double wordSim = currentWordEqual / currentWordTotal;

      debugLog(
        'Word $currentWordId Similarity: ${(wordSim * 100).toStringAsFixed(1)}% ($currentWordEqual / $currentWordTotal)',
      );

      // --- 3. EVALUATE MATCH ---
      int wordsToAdvance = 0;
      int chunksToConsume = 0;
      int maxPredIdxToChop = -1;
      int minPredIdxToStart = -1;

      for (int w = currentWordId; w <= currentWordId + 10; w++) {
        if (!wordTotalCounts.containsKey(w)) break;
        int total = wordTotalCounts[w]!;
        int equal = wordEqualCounts[w] ?? 0;

        bool isLastWord =
            (w == (chunkToWordMap.isNotEmpty ? chunkToWordMap.last : -1));
        bool isFirstWord =
            (w == (chunkToWordMap.isNotEmpty ? chunkToWordMap.first : 0));

        double requiredSimilarity = (isTajweed && isLastWord) ? 0.95 : 0.70;

        if (isFirstWord) {
          requiredSimilarity =
              0.50; // Drop required match to 50% just for word 0
        } else if (total <= 3 && requiredSimilarity > 0.65) {
          requiredSimilarity =
              0.65; // Allow 1 mistake in a 3-character word (e.g. 2/3 = 66.7%)
        }

        if (equal / total >= requiredSimilarity) {
          wordsToAdvance++;
          chunksToConsume += total;

          for (var align in alignments) {
            int alignWordId = -1;
            if (align.refIdx >= 0 &&
                targetChunkCursor + align.refIdx < chunkToWordMap.length) {
              alignWordId = chunkToWordMap[targetChunkCursor + align.refIdx];
            }
            if (alignWordId == w && align.predIdx >= 0) {
              int absolutePredIdx = bestAsrStartIdx + align.predIdx;
              // Track the very first chunk that aligned to this word
              if (minPredIdxToStart == -1 ||
                  absolutePredIdx < minPredIdxToStart) {
                minPredIdxToStart = absolutePredIdx;
              }
              // Track the very last chunk that aligned (must be 'equal' to ensure it's a solid boundary)
              if (align.opType == 'equal' &&
                  absolutePredIdx > maxPredIdxToChop) {
                maxPredIdxToChop = absolutePredIdx;
              }
            }
          }
        } else {
          break; // Stop at the first word that hasn't reached 70%
        }
      }

      if (wordsToAdvance > 0) {
        targetChunkCursor += chunksToConsume;

        int nextWordId = currentWordId + wordsToAdvance;
        debugLog(
          '>>> HIGHLIGHTING WORDS [$currentWordId to ${nextWordId - 1}]',
        );
        for (int w = currentWordId; w < nextWordId; w++) {
          mainSendPort.send({'event': 'highlight', 'word_id': w, 'is_red': false});
        }

        if (maxPredIdxToChop >= 0) {
          int startClean = minPredIdxToStart >= 0 ? minPredIdxToStart : bestAsrStartIdx;
          if (startClean <= maxPredIdxToChop && maxPredIdxToChop < currentAsrChunks.length) {
            for (int k = startClean; k <= maxPredIdxToChop; k++) {
              cleanAsr += currentAsrChunks[k];
            }
          }

          int consumedChars = 0;
          for (
            int k = 0;
            k <= maxPredIdxToChop && k < currentAsrChunks.length;
            k++
          ) {
            consumedChars += currentAsrChunks[k].length;
          }
          // Chop ONLY from the tracking system by advancing the consumed pointer!
          int charsToChop = consumedChars;
          asrConsumedChars += charsToChop;
        }

        bool isLastWordOfAyah =
            (nextWordId - 1) ==
            (chunkToWordMap.isNotEmpty ? chunkToWordMap.last : -1);
        if (isLastWordOfAyah && isTajweed) {
          mainSendPort.send({'event': 'ayah_completed', 'raw_asr': cleanAsr});
        }

        currentWordId = nextWordId;
        consecutiveFailures = 0; // Reset failures on successful match
      } else {
        consecutiveFailures++;

        if (currentAsrChunks.length > 10 && consecutiveFailures >= 3 && !isTajweed) {
          // --- 4. CATCH-UP (LOOKAHEAD) SEARCH ---
          // If similarity is low, the user might have skipped a word or the ASR hallucinated.
          // We look ahead up to 3 words to see if the user is actually reciting further down the Ayah.
          debugLog('Similarity too low. Attempting catch-up search...');

          // Try jumping forward by checking whole words ahead
          int targetWordLimit = currentWordId + 3;
          
          for (int w = currentWordId + 1; w <= targetWordLimit; w++) {
            if (chunkToWordMap.isEmpty || w > chunkToWordMap.last) break;

            int startChunk = chunkToWordMap.indexOf(w);
            int endChunk = chunkToWordMap.lastIndexOf(w);
            if (startChunk == -1 || endChunk == -1) continue;

            List<String> wordChunks = refChunks.sublist(startChunk, endChunk + 1);

            var catchupAlignments = _alignPhonemeGroups(
              wordChunks,
              currentAsrChunks,
            );
            
            int catchupEqual = catchupAlignments
                .where((a) => a.opType == 'equal')
                .length;
            int catchupDelete0 = catchupAlignments
                .where((a) => a.opType == 'delete_0')
                .length;

            int adjustedLength = wordChunks.length - catchupDelete0;
            if (adjustedLength < 1) adjustedLength = 1;

            double rawSim = catchupEqual / adjustedLength;

            int wordsSkipped = w - currentWordId;
            double jumpPenalty = wordsSkipped * 0.15;
            if (jumpPenalty > 0.30) jumpPenalty = 0.30;
            
            // Require a much stronger match for short words in catch-up to avoid coincidences
            double requiredSim = 0.75;
            if (wordChunks.length <= 4) requiredSim = 0.95; 
            if (wordChunks.length <= 2) requiredSim = 1.0; // Demand perfection for tiny words

            double catchupScore = rawSim - jumpPenalty;

            if (catchupScore > requiredSim) {
              debugLog(
                '!!! CATCH-UP MATCH FOUND !!! Jumping forward to Word $w.',
              );

              // 1. Highlight the skipped words as RED
              if (w > currentWordId) {
                debugLog(
                  '>>> HIGHLIGHTING SKIPPED WORDS [$currentWordId to ${w - 1}] AS RED',
                );
                for (int skipW = currentWordId; skipW < w; skipW++) {
                  mainSendPort.send({'event': 'highlight', 'word_id': skipW, 'is_red': true});
                }
              }

              // 2. Highlight the matched word W as GREEN
              mainSendPort.send({'event': 'highlight', 'word_id': w, 'is_red': false});

              // 3. Safely consume characters
              int maxPredIdx = -1;
              int minPredIdx = -1;
              for (var align in catchupAlignments) {
                if (align.predIdx > maxPredIdx) {
                  maxPredIdx = align.predIdx;
                }
                if (align.predIdx >= 0 && (minPredIdx == -1 || align.predIdx < minPredIdx)) {
                  minPredIdx = align.predIdx;
                }
              }

              if (maxPredIdx >= 0) {
                if (minPredIdx >= 0 && minPredIdx <= maxPredIdx && maxPredIdx < currentAsrChunks.length) {
                  for (int k = minPredIdx; k <= maxPredIdx; k++) {
                    cleanAsr += currentAsrChunks[k];
                  }
                }

                int consumedChars = 0;
                for (
                  int k = 0;
                  k <= maxPredIdx && k < currentAsrChunks.length;
                  k++
                ) {
                  consumedChars += currentAsrChunks[k].length;
                }
                int charsToChop = consumedChars;
                asrConsumedChars += charsToChop;
              }

              // 4. Update cursors to move PAST word w
              targetChunkCursor = endChunk + 1;
              currentWordId = w + 1;
              consecutiveFailures = 0;

              // 5. Check if Ayah completed
              bool isLastWordOfAyah = (w == chunkToWordMap.last);
              if (isLastWordOfAyah && isTajweed) {
                mainSendPort.send({'event': 'ayah_completed', 'raw_asr': cleanAsr});
              }

              break; // Exit catch-up loop
            }
          }
        }
      }
    }
  });
}
