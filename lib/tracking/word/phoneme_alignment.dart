import 'dart:async';

import 'dart:math';
import 'dart:typed_data';

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
class PhonemeAlignmentWeb {
  Sink<dynamic>? _sendPort;
  

  // Stream to emit matched word indices back to the UI for highlighting
  final StreamController<Map<String, dynamic>> _wordStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wordStream => _wordStreamController.stream;

  // Stream to emit completed ayah raw ASR back to the UI for Tajweed processing
  final StreamController<Map<String, dynamic>> _ayahCompletedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ayahCompletedStream =>
      _ayahCompletedStreamController.stream;

  /// Starts the background isolate and sets up the communication ports.
  Future<void> start() async {
    final receiveController = StreamController<dynamic>();
    final completer = Completer<void>();

    // Run in main event loop for web
    _alignmentWorker(receiveController.sink);

    bool isFirstMessage = true;
    receiveController.stream.listen((message) {
      if (isFirstMessage) {
        _sendPort = message as Sink<dynamic>;
        isFirstMessage = false;
        completer.complete();
      } else if (message is Map) {
        if (message['event'] == 'highlight') {
          _wordStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'debug') {
          print('[PhonemeAlignmentWeb] ${message['message']}');
        } else if (message['event'] == 'ayah_completed') {
          _ayahCompletedStreamController.add(message as Map<String, dynamic>);
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
    _sendPort?.add({
      'cmd': IsolateCommands.setAyah,
      'phonemes': expectedPhonemes,
      'boundaries': wordBoundaries,
      'isTajweed': isTajweed,
      'forceClear': forceClear,
    });
  }

  /// Feeds a new chunk of space-less ASR phonetic output to the isolate.
  void feed(String asrChunk, List<double> timestampsChunk) {
    _sendPort?.add({
      'cmd': IsolateCommands.feed,
      'asr': asrChunk,
      'timestamps': timestampsChunk,
    });
  }

  /// Backtracks and replaces the tail of the ASR buffer when the engine corrects itself
  void replaceTail(
    int backtrack,
    String newTail,
    List<double> newTailTimestamps,
  ) {
    _sendPort?.add({
      'cmd': IsolateCommands.replaceTail,
      'backtrack': backtrack,
      'tail': newTail,
      'timestamps': newTailTimestamps,
    });
  }

  /// Sets the tajweed mode dynamically.
  void setTajweedMode(bool isTajweed) {
    _sendPort?.add({
      'cmd': IsolateCommands.setTajweedMode,
      'isTajweed': isTajweed,
    });
  }

  /// Shuts down the isolate.
  void stop() {
    _sendPort?.add({'cmd': IsolateCommands.shutdown});
    _wordStreamController.close();
    _ayahCompletedStreamController.close();
  }
}

// ── Background Worker ────────────────────────────────────────────────────────

// ============================================================================
// The "Zero Cost" Phoneme Mapper
// ============================================================================
// Precomputed O(1) lookup table for specific ASR confusions and Tajweed rules.
// 
// How it works:
// We define groups of characters that are either mathematically equivalent in 
// pronunciation, or represent a relaxed Tajweed rule (e.g. tracking standard 'ن' 
// when the expected word has a Ghunnah 'ں'). 
// 
// By precomputing a bit-shifted integer for every possible pair in a group
// (e.g. 'ذ' with 'د'), the DP matrix can look up the substitution cost in O(1) 
// time during its hot loop instead of doing complex String operations.
final Set<int> _zeroCostPairs = () {
  final set = <int>{};
  const groups = [
    "ذد", // ذ with د
    "ظزذ", // ظ with ز with ذ
    "دضتط", // د with ض with ت with ط
    "جز", // ج with ز
    "ءأإآا", // The Alifs
    "ةه", // Ta Marbuta with Ha (at pauses)
    "ۦي", // Madd Silah/Ya with regular Ya
    "ۥو", // Madd Waw with regular Waw
    "ںن", // Ghunnah/Ikhfa with regular Noon
    "۾م", // Iqlab with regular Meem
  ];
  // Convert groups into bit-shifted integers
  // For example, if c1 = 'ذ' and c2 = 'د', we shift the 16-bit unicode of c1 
  // to the left by 16 spaces, and use bitwise OR to merge it with c2.
  // This creates a unique 32-bit integer for that specific character pair!
  for (final g in groups) {
    for (int i = 0; i < g.length; i++) {
      for (int j = 0; j < g.length; j++) {
        set.add((g.codeUnitAt(i) << 16) | g.codeUnitAt(j));
      }
    }
  }
  return set;
}();

/// Calculates the substitution cost between two characters.
/// Normally, mismatched characters cost 1 (high penalty). However, this checks `_zeroCostPairs`.
/// If the characters are phonetically identical in Tajweed (e.g. Small Ya vs Regular Ya), 
/// it returns a 0 cost, effectively telling the DP matrix they are a perfect match.
int _getCharSubCost(String c1, String c2) {
  if (c1 == c2) return 0;
  if (c1.isEmpty || c2.isEmpty) return 1;

  // Use fast integer hashing for O(1) lookup
  int key1 = (c1.codeUnitAt(0) << 16) | c2.codeUnitAt(0);
  int key2 = (c2.codeUnitAt(0) << 16) | c1.codeUnitAt(0);
  if (_zeroCostPairs.contains(key1) || _zeroCostPairs.contains(key2)) return 0;

  return 1; // High cost
}

// Pre-allocated reusable buffer for the DP matrix to eliminate memory allocation inside the hot loop.
// Max n is ~20, max m is ~30. 10000 is extremely safe and takes only 40KB of RAM.
final Int32List _dpBuffer = Int32List(10000);

/// Main wrapper for the Wagner-Fischer algorithm.
/// 
/// It decides whether to use the pre-allocated fast-memory `_dpBuffer` or, 
/// in extremely rare cases where the tracking window is massive, to dynamically
/// allocate a new `Int32List` array so the app never crashes from index overflow.
List<PhonemeGroupAlignment> _alignPhonemeGroups(
  List<String> refChars,
  List<String> predChars,
) {
  // Required size is (rows * columns) of the matrix
  int requiredSize = (refChars.length + 1) * (predChars.length + 1);
  Int32List dpArray;
  
  if (requiredSize > _dpBuffer.length) {
    // Memory Fallback: Window is > 10,000 cells. We dynamically allocate.
    dpArray = Int32List(requiredSize);
  } else {
    // Fast Path: Use the static 40KB buffer. 0 garbage collection cost!
    dpArray = _dpBuffer;
  }

  return _runWagnerFischer(refChars, predChars, dpArray);
}

/// The core mathematical engine of the tracker.
/// Uses the Wagner-Fischer algorithm to compute the Levenshtein distance between
/// the expected Uthmani phonemes (`refChars`) and the incoming ASR phonemes (`predChars`).
/// 
/// It fills an `(N+1) x (M+1)` dynamic programming matrix, where it calculates
/// the cheapest path (insertions, deletions, substitutions) to align the two arrays.
/// 
/// * Tajweed symbols (e.g., Qalqalah ڇ) are dynamically ignored (Cost 0 for insertion/deletion).
/// * Repeated characters (vowel elongation/Madd) are ignored (Cost 0 for insertion/deletion).
List<PhonemeGroupAlignment> _runWagnerFischer(
  List<String> refChars,
  List<String> predChars,
  Int32List dpArray,
) {
  int n = refChars.length;
  int m = predChars.length;

  int getDp(int i, int j) => dpArray[i * (m + 1) + j];
  void setDp(int i, int j, int val) => dpArray[i * (m + 1) + j] = val;

  setDp(0, 0, 0);
  for (int i = 1; i <= n; i++) {
    int delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;
    if (refChars[i - 1] == 'ڇ' || refChars[i - 1] == 'ۜ' || refChars[i - 1] == '۪') delCost = 0;
    setDp(i, 0, getDp(i - 1, 0) + delCost);
  }
  for (int j = 1; j <= m; j++) {
    int insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
    if (predChars[j - 1] == 'ڇ' || predChars[j - 1] == 'ۜ' || predChars[j - 1] == '۪') insCost = 0;
    setDp(0, j, getDp(0, j - 1) + insCost);
  }

  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      int cost = _getCharSubCost(refChars[i - 1], predChars[j - 1]);

      int delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;
      if (refChars[i - 1] == 'ڇ' || refChars[i - 1] == 'ۜ' || refChars[i - 1] == '۪') delCost = 0;
      int del = getDp(i - 1, j) + delCost; // deletion

      // insertion: 0 cost if it's a repeated character (Madd / Vowel Elongation)
      int insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
      if (predChars[j - 1] == 'ڇ' || predChars[j - 1] == 'ۜ' || predChars[j - 1] == '۪') insCost = 0;
      int ins = getDp(i, j - 1) + insCost; // insertion

      int sub = getDp(i - 1, j - 1) + cost; // substitution / equal

      setDp(i, j, min(del, min(ins, sub)));
    }
  }

  // Traceback to find the optimal alignment operations
  List<PhonemeGroupAlignment> alignments = [];

  // Semi-Global Alignment: Find the best 'i' (reference end) to start traceback from.
  // This prevents the DP matrix from warping the alignment of the first spoken word
  // just to minimize the deletion penalty of the remaining 10+ reference chunks in the window!
  int bestI = n;
  int minCost = getDp(n, m);
  for (int k = 0; k <= n; k++) {
    if (getDp(k, m) < minCost) {
      minCost = getDp(k, m);
      bestI = k;
    }
  }

  // Add standard deletions for the trailing reference chunks that were skipped
  for (int k = n; k > bestI; k--) {
    alignments.add(
      PhonemeGroupAlignment(
        opType: 'delete', // standard delete so it correctly penalizes unfinished words
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
      if (getDp(i, j) == getDp(i - 1, j - 1) + cost) {
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

    int insCost = 1;
    if (j > 0) {
      insCost = (j > 1 && predChars[j - 1] == predChars[j - 2]) ? 0 : 1;
      if (predChars[j - 1] == 'ڇ' || predChars[j - 1] == 'ۜ' || predChars[j - 1] == '۪') insCost = 0;
    }
    
    int delCost = 1;
    if (i > 0) {
      delCost = (i > 1 && refChars[i - 1] == refChars[i - 2]) ? 0 : 1;
      if (refChars[i - 1] == 'ڇ' || refChars[i - 1] == 'ۜ' || refChars[i - 1] == '۪') delCost = 0;
    }

    if (i > 0 && getDp(i, j) == getDp(i - 1, j) + delCost) {
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
    } else if (j > 0 && getDp(i, j) == getDp(i, j - 1) + insCost) {
      alignments.add(
        PhonemeGroupAlignment(
          opType: insCost == 0 ? 'insert_0' : 'insert',
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

/// The main event loop running inside the Isolate.
/// 
/// This worker manages an accumulating sliding window of ASR phonemes (`asrWindow`).
/// Instead of matching the entire Ayah at once (which is computationally impossible
/// in real-time), it extracts a "Target Window" of expected phonemes and uses the 
/// `_runWagnerFischer` DP matrix to scan across the incoming `asrWindow`.
/// 
/// Once a word hits 75% similarity, the `asrConsumedChars` pointer is advanced, 
/// permanently locking in that word and preventing future hallucinated audio 
/// from overwriting the match. It communicates with the UI via message passing.
void _alignmentWorker(Sink<dynamic> mainSendPort) {
  final commandPort = StreamController<dynamic>();
  mainSendPort.add(commandPort.sink);

  // Ayah State
  String expectedPhonemes = '';
  List<int> wordBoundaries = []; // Character index boundaries for each word
  List<String> refChunks = []; // The expected phonemes, chunked into groups
  List<int> chunkToWordMap = []; // Maps chunk index -> word index
  bool isTajweed = false; // Whether tajweed mode is active

  // Tracking State
  String asrWindow = ''; // The FULL raw ASR string for the current Ayah
  List<double> asrTimestamps = []; // The FULL timestamps for the current Ayah
  // --- THE POINTER TRICK ---
  // The 'asrConsumedChars' pointer is the secret to preserving the raw ASR string!
  // Instead of physically deleting matched characters from 'asrWindow' (which would destroy the string),
  // we just advance this integer pointer. The sliding window only reads from 'asrConsumedChars' onwards.
  int asrConsumedChars = 0;

  // Accumulated clean ASR string that only contains characters successfully matched to the Ayah
  // (filters out stutters, false starts, and background noise)
  String cleanAsr = '';
  List<double> cleanTimestamps = [];

  List<String> acceptedWordsAsr = [];
  List<List<double>> acceptedWordsTimestamps = [];

  int targetChunkCursor =
      0; // Where we currently are in the expected refChunks array
  int currentWordId = 0; // The last word ID we highlighted

  // Helper to send debug messages to the main thread
  void debugLog(String message) {
    mainSendPort.add({'event': 'debug', 'message': message});
  }

  commandPort.stream.listen((message) {
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

      // 2. Map every chunk index back to a specific Word index.
      // Because we process phonemes as flattened "chunks" (e.g. بِ, سْ, مِ), we need
      // a way to know which chunk belongs to which word so we can color the words
      // individually later.
      chunkToWordMap = [];
      int charCursor = 0;
      for (var chunk in refChunks) {
        int wIdx = 0;
        
        // Find which word boundary this character cursor falls into
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
      List<double> unconsumedTimestamps =
          asrConsumedChars < asrTimestamps.length
          ? asrTimestamps.sublist(asrConsumedChars)
          : [];

      // (Removed sending ayah_completed here to prevent out-of-sync state with main thread)

      asrWindow = forceClear ? '' : unconsumed;
      asrTimestamps = forceClear ? [] : unconsumedTimestamps;
      cleanAsr = '';
      cleanTimestamps = [];

      int wordCount = wordBoundaries.length - 1;
      acceptedWordsAsr = List.filled(wordCount, '');
      acceptedWordsTimestamps = List.generate(wordCount, (_) => []);

      asrConsumedChars = 0;

      if (asrWindow.length > 500) {
        asrWindow = asrWindow.substring(asrWindow.length - 500);
        if (asrTimestamps.length > 500) {
          asrTimestamps = asrTimestamps.sublist(asrTimestamps.length - 500);
        }
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
      List<double> newTimestamps = message['timestamps'] as List<double>;
      if (newAsr.isNotEmpty) {
        asrWindow += newAsr;
        asrTimestamps.addAll(newTimestamps);
      }
    }

    // --- REPLACE TAIL COMMAND ---
    if (cmd == IsolateCommands.replaceTail) {
      int backtrack = message['backtrack'] as int;
      String newTail = message['tail'] as String;
      List<double> newTailTimestamps = message['timestamps'] as List<double>;

      if (backtrack <= asrWindow.length) {
        int newLength = asrWindow.length - backtrack;
        // CRITICAL: Protect characters that have already been matched and consumed!
        if (newLength < asrConsumedChars) {
          newLength = asrConsumedChars;
        }
        asrWindow = asrWindow.substring(0, newLength) + newTail;
        if (newLength <= asrTimestamps.length) {
          asrTimestamps = asrTimestamps.sublist(0, newLength)
            ..addAll(newTailTimestamps);
        }
      } else {
        // The backtrack is deeper than our current local window memory.
        // We must slice newTail to only include phonemes relevant to our local window,
        // skipping the massive history of previous ayahs that the ASR just rewrote.
        int w = asrWindow.length;
        int offsetIntoNewTail = (backtrack - w) + asrConsumedChars;

        if (offsetIntoNewTail >= 0 && offsetIntoNewTail <= newTail.length) {
          String relevantTail = newTail.substring(offsetIntoNewTail);
          asrWindow = asrWindow.substring(0, asrConsumedChars) + relevantTail;

          if (offsetIntoNewTail <= newTailTimestamps.length &&
              asrConsumedChars <= asrTimestamps.length) {
            asrTimestamps = asrTimestamps.sublist(0, asrConsumedChars)
              ..addAll(newTailTimestamps.sublist(offsetIntoNewTail));
          }
        } else {
          // The new tail is shorter than expected (massive deletions in the past).
          // Just cap the window at the consumed characters.
          asrWindow = asrWindow.substring(0, asrConsumedChars);
          if (asrConsumedChars <= asrTimestamps.length) {
            asrTimestamps = asrTimestamps.sublist(0, asrConsumedChars);
          }
        }
      }
    }

    // --- SET TAJWEED MODE COMMAND ---
    if (cmd == IsolateCommands.setTajweedMode) {
      isTajweed = message['isTajweed'] as bool;
      debugLog('Tajweed Mode is now: $isTajweed');
      return;
    }

    if (cmd == IsolateCommands.feed || cmd == IsolateCommands.replaceTail) {
      bool matchedSomething;
      do {
        matchedSomething = false;

        // If we've already tracked everything, stop checking
        if (targetChunkCursor >= refChunks.length) break;

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
        List<double> trackingTimestamps =
            asrConsumedChars < asrTimestamps.length
            ? asrTimestamps.sublist(asrConsumedChars)
            : [];

        // Safety cap: Prevent thermal throttling / lag by discarding old unconsumed ASR garbage.
        if (trackingAsr.length > 200) {
          int excess = trackingAsr.length - 200;
          asrConsumedChars += excess;
          trackingAsr = trackingAsr.substring(excess);
          if (trackingTimestamps.length > excess) {
            trackingTimestamps = trackingTimestamps.sublist(excess);
          }
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
        List<String> targetWindowChars = List.generate(
          targetWindowChunks.length,
          (i) =>
              targetWindowChunks[i].isNotEmpty ? targetWindowChunks[i][0] : '',
        );

        List<String> currentAsrChars = List.generate(
          currentAsrChunks.length,
          (i) => currentAsrChunks[i].isNotEmpty ? currentAsrChunks[i][0] : '',
        );

        int bestAsrStartIdx = 0;
        double bestSelectionScore = -999.0;
        var alignments = _alignPhonemeGroups(
          targetWindowChars,
          currentAsrChars,
        );
        Map<int, int> wordEqualCounts = {};
        Map<int, int> wordTotalCounts = {};

        int windowSize = targetWindowChunks.length + 10;
        int maxStartIdx = currentAsrChunks.length - targetWindowChunks.length;
        if (maxStartIdx < 0) maxStartIdx = 0;

        int lookahead = isTajweed ? 0 : 2; // Max words to look ahead

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

        // Change stride from 3 to 1: This guarantees we evaluate every possible starting
        // position in the ASR buffer, preventing the window from accidentally stepping OVER
        // the current word (which was causing it to either get stuck or jump to lookahead).
        for (int startIdx = 0; startIdx <= maxStartIdx; startIdx += 1) {
          int endIdx = startIdx + windowSize;
          if (endIdx > currentAsrChunks.length)
            endIdx = currentAsrChunks.length;

          List<String> asrSubWindow = currentAsrChunks.sublist(
            startIdx,
            endIdx,
          );
          List<String> asrSubWindowChars = currentAsrChars.sublist(
            startIdx,
            endIdx,
          );
          var tempAlignments = _alignPhonemeGroups(
            targetWindowChars,
            asrSubWindowChars,
          );

          Map<int, int> tempWordEqualCounts = {};
          Map<int, int> tempWordTotalCounts = Map.from(baseWordTotalCounts);
          // Track pred positions of each word's equal matches for contiguity check
          Map<int, List<int>> tempWordEqualPredPositions = {};

          for (var align in tempAlignments) {
            int wIdx = -1;
            if (align.refIdx >= 0 &&
                targetChunkCursor + align.refIdx < chunkToWordMap.length) {
              wIdx = chunkToWordMap[targetChunkCursor + align.refIdx];
            }
            if (wIdx != -1) {
              if (align.opType == 'equal') {
                tempWordEqualCounts[wIdx] =
                    (tempWordEqualCounts[wIdx] ?? 0) + 1;
                (tempWordEqualPredPositions[wIdx] ??= []).add(align.predIdx);
              } else if (align.opType == 'delete_0') {
                tempWordTotalCounts[wIdx] =
                    (tempWordTotalCounts[wIdx] ?? 1) - 1;
                if (tempWordTotalCounts[wIdx]! < 1)
                  tempWordTotalCounts[wIdx] = 1;
              }
            }
          }

          // --- PER-WORD CONTIGUITY CHECK ---
          // The DP can grab phonemes far apart in the ASR stream and assemble a
          // false word — e.g. picking للَ from "تبارك اللذي" and هِ from "بيده"
          // to falsely match الله. For each word, verify that consecutive equal
          // matches are close together in the pred stream. If any gap > 1 chunks,
          // the matches are scattered from different spoken words → invalidate.
          for (var entry in tempWordEqualPredPositions.entries) {
            var positions = entry.value;
            if (positions.length >= 2) {
              for (int k = 1; k < positions.length; k++) {
                int rawGap = positions[k] - positions[k - 1];
                if (rawGap > 1) {
                  int effectiveGap = 0;
                  String leftBase = asrSubWindow[positions[k - 1]].isNotEmpty
                      ? asrSubWindow[positions[k - 1]][0]
                      : '';
                  String rightBase = asrSubWindow[positions[k]].isNotEmpty
                      ? asrSubWindow[positions[k]][0]
                      : '';
                  for (int p = positions[k - 1] + 1; p < positions[k]; p++) {
                    String midBase = asrSubWindow[p].isNotEmpty
                        ? asrSubWindow[p][0]
                        : '';
                    if (midBase != leftBase && midBase != rightBase) {
                      effectiveGap++;
                    }
                  }
                  if (effectiveGap > 1) {
                    tempWordEqualCounts[entry.key] = 0;
                    break;
                  }
                }
              }
            }
          }

          int currentWordTotal = tempWordTotalCounts[currentWordId] ?? 1;
          int currentWordEqual = tempWordEqualCounts[currentWordId] ?? 0;
          double rawSim = currentWordEqual / currentWordTotal;

          // Give a slight boost if the lookahead word matches perfectly, so the window
          // properly aligns to skipped words instead of misaligning them at startIdx=0.
          double lookaheadBoost = 0.0;
          for (int w = currentWordId + 1; w <= currentWordId + lookahead; w++) {
            int wTotal = tempWordTotalCounts[w] ?? 1;
            int wEqual = tempWordEqualCounts[w] ?? 0;
            if (wTotal > 0 && (wEqual / wTotal) >= 0.85) {
              lookaheadBoost = 0.2; // Small boost to favor this alignment
              break;
            }
          }

          // --- FIXED PENALTY CAP ---
          // Restored to 0.15. This guarantees the engine never permanently
          // freezes after a long string of wrong words/garbage ASR.
          double priorPenalty = startIdx * 0.02;
          if (priorPenalty > 0.15) priorPenalty = 0.15;

          double selectionScore = rawSim + lookaheadBoost - priorPenalty;

          if (selectionScore > bestSelectionScore) {
            bestSelectionScore = selectionScore;
            bestAsrStartIdx = startIdx;
            alignments = tempAlignments;
            wordEqualCounts = tempWordEqualCounts;
            wordTotalCounts = tempWordTotalCounts;
          }

          if (selectionScore >= 0.85)
            break; // Found a strong match — no need to keep sliding since prior penalty makes later positions worse
        }

        int currentWordTotal = wordTotalCounts[currentWordId] ?? 1;
        int currentWordEqual = wordEqualCounts[currentWordId] ?? 0;
        double wordSim = currentWordEqual / currentWordTotal;

        debugLog(
          'Word $currentWordId Similarity: ${(wordSim * 100).toStringAsFixed(1)}% ($currentWordEqual / $currentWordTotal)',
        );

        // --- 3. EVALUATE MATCH (WITH INTEGRATED LOOKAHEAD) ---
        // Try matching current word. If it fails, look ahead up to 3 words
        // using the SAME alignment data (same sliding window, same penalties).
        // This replaces the separate catch-up code that searched the entire ASR.

        int wordsToAdvance = 0;
        int chunksToConsume = 0;
        int maxPredIdxToChop = -1;
        int minPredIdxToStart = -1;

        for (int w = currentWordId; w <= currentWordId + lookahead; w++) {
          if (!wordTotalCounts.containsKey(w)) break;
          int total = wordTotalCounts[w]!;
          int equal = wordEqualCounts[w] ?? 0;

          bool isFirstWord =
              (w == (chunkToWordMap.isNotEmpty ? chunkToWordMap.first : 0));

          // Matching Strictness & Terminal Anchor Rule
          double requiredSimilarity;
          bool mustAnchorTail = isTajweed; // Anchor tail ONLY in Tajweed mode!
          bool isLookahead =
              (w > currentWordId); // Detect if this is a skip attempt

          requiredSimilarity = 0.75;
          if (isFirstWord) {
            requiredSimilarity = 0.60; // CRITICAL: First word boundary clipping
          }
          if (total <= 3) {
            requiredSimilarity = 0.65; // Allows 2/3 to pass
          }

          // --- RESTORED STRICTNESS FOR LOOKAHEAD ---
          // Require much higher confidence to jump ahead and skip words.
          // This prevents the engine from abandoning the current word just because
          // the ASR hallucinated a match for a future word.
          // if (isLookahead) {
          //   requiredSimilarity = 0.80; // Strict for large words
          //   if (total <= 3) {
          //     requiredSimilarity =
          //         1.0; // Must be perfectly spoken if it's a tiny word!
          //   }
          // }

          // Check if the base similarity percentage passes
          bool bodyMatches = (equal / total >= requiredSimilarity);
          bool tailIsReady = true;
          bool gapIsSafe = true; // SCATTERED PHONEME KILLER

          // --- THE GAP CHECK ---
          // If the DP grabs phonemes that are separated by more than 1 ASR chunk,
          // it means it's hallucinating a word from distant sounds. Invalidate it.
          if (bodyMatches) {
            int lastPredIdx = -1;
            for (var align in alignments) {
              if (align.opType == 'equal' && align.refIdx >= 0) {
                int absRefIdx = targetChunkCursor + align.refIdx;
                if (absRefIdx < chunkToWordMap.length &&
                    chunkToWordMap[absRefIdx] == w) {
                  if (lastPredIdx != -1) {
                    int rawGap = align.predIdx - lastPredIdx;
                    if (rawGap > 1) {
                      int effectiveGap = 0;
                      String leftBase =
                          currentAsrChunks[bestAsrStartIdx + lastPredIdx]
                              .isNotEmpty
                          ? currentAsrChunks[bestAsrStartIdx + lastPredIdx][0]
                          : '';
                      String rightBase =
                          currentAsrChunks[bestAsrStartIdx + align.predIdx]
                              .isNotEmpty
                          ? currentAsrChunks[bestAsrStartIdx + align.predIdx][0]
                          : '';
                      for (int p = lastPredIdx + 1; p < align.predIdx; p++) {
                        String midBase =
                            currentAsrChunks[bestAsrStartIdx + p].isNotEmpty
                            ? currentAsrChunks[bestAsrStartIdx + p][0]
                            : '';
                        if (midBase != leftBase && midBase != rightBase) {
                          effectiveGap++;
                        }
                      }
                      if (effectiveGap > 1) {
                        gapIsSafe = false;
                        break;
                      }
                    }
                  }
                  lastPredIdx = align.predIdx;
                }
              }
            }
          }

          if (mustAnchorTail && bodyMatches) {
            // Find the absolute last expected chunk for this specific word
            int wordEndChunk = chunkToWordMap.lastIndexOf(w);
            // Calculate its index relative to our current sliding window
            int relativeLastChunkIdx = wordEndChunk - targetChunkCursor;

            // Check if this exact final chunk was successfully aligned as 'equal'
            bool finalPhonemeMatched = alignments.any(
              (align) =>
                  align.refIdx == relativeLastChunkIdx &&
                  align.opType == 'equal',
            );

            // If the final letter/tashkeel hasn't been spoken correctly yet, hold back
            if (!finalPhonemeMatched) {
              tailIsReady = false;
            }
          }

          // --- THE "PROVE IT" LOOKAHEAD RULE (MULTI-WORD COMMITMENT) ---
          // If the tracker thinks the user skipped a word, it must hold the highlight
          // until it sees that the user has started speaking the *next* word.
          // This makes False Positive skipping mathematically impossible.
          bool lookaheadConfirmed = true;
          if (isLookahead && bodyMatches) {
            int nextW = w + 1;
            // If the next word is inside our target window, require at least 1 phoneme
            // of it to be matched to prove the user actually moved forward.
            if (wordTotalCounts.containsKey(nextW)) {
              int nextEqual = wordEqualCounts[nextW] ?? 0;
              if (nextEqual == 0) {
                lookaheadConfirmed = false;
              }
            }
          }

          if (bodyMatches && tailIsReady && gapIsSafe && lookaheadConfirmed) {
            // This word matches — count all skipped words + this one
            // First, add the chunks for any skipped words
            for (
              int skipW = currentWordId + wordsToAdvance;
              skipW < w;
              skipW++
            ) {
              int skipTotal = wordTotalCounts[skipW] ?? 0;
              chunksToConsume += skipTotal;
            }
            wordsToAdvance = (w - currentWordId) + 1;
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
            // Don't break — continue to see if next words also match
          } else if (wordsToAdvance > 0) {
            break; // Already found a match, stop at next failure
          }
          // If no match found yet, continue lookahead (don't break)
        }

        if (wordsToAdvance > 0) {
          int savedChunkCursor = targetChunkCursor; // save BEFORE advance
          targetChunkCursor += chunksToConsume;
          int startWordId = currentWordId;
          int nextWordId = currentWordId + wordsToAdvance;

          // Build per-word pred strings directly from alignment
          Map<int, String> wordPredStrMap = {};
          Map<int, List<double>> wordPredTsMap = {};

          for (var align in alignments) {
            if (align.refIdx < 0 || align.predIdx < 0) continue;
            int absRefIdx = savedChunkCursor + align.refIdx;
            if (absRefIdx >= chunkToWordMap.length) continue;
            int wId = chunkToWordMap[absRefIdx];
            if (wId < startWordId || wId >= nextWordId) continue;

            int absPredIdx = bestAsrStartIdx + align.predIdx;
            if (absPredIdx >= currentAsrChunks.length) continue;
            String chunk = currentAsrChunks[absPredIdx];
            wordPredStrMap[wId] = (wordPredStrMap[wId] ?? '') + chunk;

            // timestamps: count chars before absPredIdx
            int charStart = 0;
            for (int k = 0; k < absPredIdx; k++)
              charStart += currentAsrChunks[k].length;
            for (int c = 0; c < chunk.length; c++) {
              if (charStart + c < trackingTimestamps.length) {
                wordPredTsMap
                    .putIfAbsent(wId, () => [])
                    .add(trackingTimestamps[charStart + c]);
              }
            }
          }

          // Commit to acceptedWordsAsr
          for (int w = startWordId; w < nextWordId; w++) {
            acceptedWordsAsr[w] = wordPredStrMap[w] ?? '';
            acceptedWordsTimestamps[w] = wordPredTsMap[w] ?? [];
            cleanAsr += acceptedWordsAsr[w];
            cleanTimestamps.addAll(acceptedWordsTimestamps[w]);
          }

          if (maxPredIdxToChop >= 0) {
            int consumedChars = 0;
            for (
              int k = 0;
              k <= maxPredIdxToChop && k < currentAsrChunks.length;
              k++
            ) {
              consumedChars += currentAsrChunks[k].length;
            }
            asrConsumedChars += consumedChars;
          }

          // Highlight skipped words as RED
          for (int w = startWordId; w < nextWordId; w++) {
            // The matched word is always the last word in this batch.
            // Anything before it was a failure that triggered the lookahead.
            bool isSkipped = (w < nextWordId - 1);

            if (isSkipped) {
              debugLog('>>> HIGHLIGHTING SKIPPED WORD $w AS RED');
            }
            mainSendPort.add({
              'event': 'highlight',
              'word_id': w,
              'is_red': isSkipped,
              'clean_asr': acceptedWordsAsr[w],
              'timestamps': acceptedWordsTimestamps[w].toList(),
              'word_asr': acceptedWordsAsr.toList(),
              'word_timestamps': acceptedWordsTimestamps.map((e) => e.toList()).toList(),
            });
          }

          bool isLastWordOfAyah =
              (nextWordId - 1) ==
              (chunkToWordMap.isNotEmpty ? chunkToWordMap.last : -1);
          if (isLastWordOfAyah && isTajweed) {
            mainSendPort.add({
              'event': 'ayah_completed',
              'raw_asr': cleanAsr,
              'timestamps': cleanTimestamps.toList(),
              'word_asr': acceptedWordsAsr.toList(),
              'word_timestamps': acceptedWordsTimestamps.map((e) => e.toList()).toList(),
            });
          }

          currentWordId = nextWordId;
          matchedSomething =
              true; // We advanced, loop again to consume remaining ASR!
        }
      } while (matchedSomething);
    }
  });
}
