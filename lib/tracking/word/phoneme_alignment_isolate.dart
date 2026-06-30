import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'quran_normalizer.dart';

/// Defines the commands sent from the main thread (UI) to the background Isolate.
class IsolateCommands {
  static const int setup = 0;
  static const int feed = 1;     // Feed new ASR phonetic stream chunks
  static const int setAyah = 2;  // Initialize a new Ayah with expected phonemes and word boundaries
  static const int shutdown = 3; // Terminate the isolate
  static const int replaceTail = 4; // Backtrack and replace unstable ASR tail
}

/// Represents a single alignment operation between a reference phoneme group
/// (from the correct Uthmani script) and a predicted phoneme group (from the ASR model).
class PhonemeGroupAlignment {
  final String opType; // 'insert', 'delete', 'replace', or 'equal'
  final int refIdx;    // Index of the chunk in the reference array (-1 if insert)
  final int predIdx;   // Index of the chunk in the predicted array (-1 if delete)

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
  final StreamController<int> _wordStreamController = StreamController<int>.broadcast();
  Stream<int> get wordStream => _wordStreamController.stream;

  // Stream to emit completed ayah raw ASR back to the UI for Tajweed processing
  final StreamController<String> _ayahCompletedStreamController = StreamController<String>.broadcast();
  Stream<String> get ayahCompletedStream => _ayahCompletedStreamController.stream;

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
          _wordStreamController.add(message['word_id'] as int);
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
  void setAyah(String expectedPhonemes, List<int> wordBoundaries, {bool isTajweed = false, bool forceClear = false}) {
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
    _sendPort?.send({
      'cmd': IsolateCommands.feed,
      'asr': asrChunk,
    });
  }

  /// Backtracks and replaces the tail of the ASR buffer when the engine corrects itself
  void replaceTail(int backtrack, String newTail) {
    _sendPort?.send({
      'cmd': IsolateCommands.replaceTail,
      'backtrack': backtrack,
      'tail': newTail,
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
    ['ذ', 'ظ', 'ز', 'ض'], // Sibilants / Interdentals
    ['س', 'ص', 'ث'], // S/Th sounds
    ['ت', 'ط', 'د'], // T/D sounds
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
  List<String> refChars = List.generate(n, (i) => refGroups[i].isNotEmpty ? refGroups[i][0] : '');
  List<String> predChars = List.generate(m, (i) => predGroups[i].isNotEmpty ? predGroups[i][0] : '');

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
  int i = n;
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
      alignments.add(PhonemeGroupAlignment(
        opType: delCost == 0 ? 'delete_0' : 'delete', // Mark as delete_0 so we can subtract from total instead of inflating equals
        refIdx: i - 1, 
        predIdx: j > 0 ? j - 1 : -1
      ));
      i--;
    } else if (j > 0 && dp[i][j] == dp[i][j - 1] + insCost) {
      alignments.add(PhonemeGroupAlignment(
        opType: 'insert', 
        refIdx: i > 0 ? i - 1 : -1, 
        predIdx: j - 1
      ));
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
  List<String> refChunks = [];   // The expected phonemes, chunked into groups
  List<int> chunkToWordMap = []; // Maps chunk index -> word index
  bool isTajweed = false;        // Whether tajweed mode is active
  
  // Tracking State
  String asrWindow = '';     // The FULL raw ASR string for the current Ayah
  int asrConsumedChars = 0;  // How many characters have been chopped by the word tracker
  int targetChunkCursor = 0; // Where we currently are in the expected refChunks array
  int currentWordId = 0;     // The last word ID we highlighted

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
          if (charCursor >= wordBoundaries[i] && charCursor < wordBoundaries[i+1]) {
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
      asrConsumedChars = 0;
      
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
         asrWindow = asrWindow.substring(0, asrWindow.length - backtrack) + newTail;
      } else {
         asrWindow = newTail;
      }
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
      List<String> targetWindowChunks = refChunks.sublist(targetChunkCursor, targetWindowEnd);
      
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
      List<String> currentAsrChunks = QuranNormalizer.chunkPhonemes(currentAsrWindow);
      

      debugLog('\n--- Alignment Tick ---');
      debugLog('Target Window: ${targetWindowChunks.join(" ")}');
      debugLog('ASR Window: ${currentAsrChunks.join(" ")}');

      // --- 2. PERFORM ALIGNMENT (SLIDING WINDOW) ---
      // Instead of global alignment, slide a window across the ASR buffer to find the best match.
      // This flawlessly ignores hallucinated garbage and stutters!
      int bestAsrStartIdx = 0;
      double bestCurrentWordSim = -1.0;
      var alignments = _alignPhonemeGroups(targetWindowChunks, currentAsrChunks);
      Map<int, int> wordEqualCounts = {};
      Map<int, int> wordTotalCounts = {};
      
      int windowSize = targetWindowChunks.length + 10;
      int maxStartIdx = currentAsrChunks.length - targetWindowChunks.length;
      if (maxStartIdx < 0) maxStartIdx = 0;
      
      for (int startIdx = 0; startIdx <= maxStartIdx; startIdx += 3) {
         int endIdx = startIdx + windowSize;
         if (endIdx > currentAsrChunks.length) endIdx = currentAsrChunks.length;
         
         List<String> asrSubWindow = currentAsrChunks.sublist(startIdx, endIdx);
         var tempAlignments = _alignPhonemeGroups(targetWindowChunks, asrSubWindow);
         
         Map<int, int> tempWordEqualCounts = {};
         Map<int, int> tempWordTotalCounts = {};
         
         for (int i = 0; i < targetWindowChunks.length; i++) {
           int wIdx = -1;
           if (targetChunkCursor + i < chunkToWordMap.length) {
             wIdx = chunkToWordMap[targetChunkCursor + i];
           }
           if (wIdx != -1) {
             tempWordTotalCounts[wIdx] = (tempWordTotalCounts[wIdx] ?? 0) + 1;
           }
         }
         
         for (var align in tempAlignments) {
           int wIdx = -1;
           if (align.refIdx >= 0 && targetChunkCursor + align.refIdx < chunkToWordMap.length) {
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
         double wordSim = currentWordEqual / currentWordTotal;
         
         if (wordSim > bestCurrentWordSim) {
             bestCurrentWordSim = wordSim;
             bestAsrStartIdx = startIdx;
             alignments = tempAlignments;
             wordEqualCounts = tempWordEqualCounts;
             wordTotalCounts = tempWordTotalCounts;
         }
         
         if (wordSim >= 1.0) break; // Found a perfect match, no need to search further!
      }

      int currentWordTotal = wordTotalCounts[currentWordId] ?? 1;
      int currentWordEqual = wordEqualCounts[currentWordId] ?? 0;
      double wordSim = currentWordEqual / currentWordTotal;

      debugLog('Word $currentWordId Similarity: ${(wordSim * 100).toStringAsFixed(1)}% ($currentWordEqual / $currentWordTotal)');

      // --- 3. EVALUATE MATCH ---
      int wordsToAdvance = 0;
      int chunksToConsume = 0;
      int maxPredIdxToChop = -1;
      int minPredIdxToStart = -1;
      
      for (int w = currentWordId; w <= currentWordId + 10; w++) {
        if (!wordTotalCounts.containsKey(w)) break;
        int total = wordTotalCounts[w]!;
        int equal = wordEqualCounts[w] ?? 0;
        
        bool isLastWord = (w == (chunkToWordMap.isNotEmpty ? chunkToWordMap.last : -1));
        double requiredSimilarity = (isTajweed && isLastWord) ? 0.95 : 0.70;
        
        if (equal / total >= requiredSimilarity) {
          wordsToAdvance++;
          chunksToConsume += total;
          
          for (var align in alignments) {
             int alignWordId = -1;
             if (align.refIdx >= 0 && targetChunkCursor + align.refIdx < chunkToWordMap.length) {
                alignWordId = chunkToWordMap[targetChunkCursor + align.refIdx];
             }
             if (alignWordId == w && align.predIdx >= 0) {
                int absolutePredIdx = bestAsrStartIdx + align.predIdx;
                // Track the very first chunk that aligned to this word
                if (minPredIdxToStart == -1 || absolutePredIdx < minPredIdxToStart) {
                   minPredIdxToStart = absolutePredIdx;
                }
                // Track the very last chunk that aligned (must be 'equal' to ensure it's a solid boundary)
                if (align.opType == 'equal' && absolutePredIdx > maxPredIdxToChop) {
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
        debugLog('>>> HIGHLIGHTING WORDS [$currentWordId to ${nextWordId - 1}]');
        for (int w = currentWordId; w < nextWordId; w++) {
           mainSendPort.send({'event': 'highlight', 'word_id': w});
        }
        
        bool isLastWordOfAyah = (nextWordId - 1) == (chunkToWordMap.isNotEmpty ? chunkToWordMap.last : -1);
        if (isLastWordOfAyah) {
           mainSendPort.send({'event': 'ayah_completed', 'raw_asr': asrWindow});
        }
        
        currentWordId = nextWordId;
        
        if (maxPredIdxToChop >= 0) {
          int consumedChars = 0;
          for (int k = 0; k <= maxPredIdxToChop && k < currentAsrChunks.length; k++) {
            consumedChars += currentAsrChunks[k].length;
          }
          // Chop ONLY from the tracking system by advancing the consumed pointer!
          int charsToChop = consumedChars;
          asrConsumedChars += charsToChop;
        }
      
      } else if (currentAsrChunks.length > 20) {
        
        // --- 4. CATCH-UP (LOOKAHEAD) SEARCH ---
        // If similarity is low, the user might have skipped a word or the ASR hallucinated.
        // We look ahead up to 30 chunks to see if the user is actually reciting further down the Ayah.
        debugLog('Similarity too low. Attempting catch-up search...');
        
        int lookaheadEnd = targetChunkCursor + 30;
        if (lookaheadEnd > refChunks.length) lookaheadEnd = refChunks.length;
        List<String> lookaheadWindow = refChunks.sublist(targetChunkCursor, lookaheadEnd);
        
        // Try jumping forward in small blocks (size 10) to find a solid match
        for (int i = 0; i < lookaheadWindow.length - 5; i += 3) {
           int end = i + 10;
           if (end > lookaheadWindow.length) end = lookaheadWindow.length;
           List<String> chunk = lookaheadWindow.sublist(i, end);
           
           var catchupAlignments = _alignPhonemeGroups(chunk, currentAsrChunks);
           int catchupEqual = catchupAlignments.where((a) => a.opType == 'equal').length;
           int catchupDelete0 = catchupAlignments.where((a) => a.opType == 'delete_0').length;
           
           int adjustedLength = chunk.length - catchupDelete0;
           if (adjustedLength < 1) adjustedLength = 1;
           
           if (catchupEqual / adjustedLength > 0.70) {
               debugLog('!!! CATCH-UP MATCH FOUND !!! Jumping forward by ${i + chunk.length} chunks.');
               
               targetChunkCursor += i + chunk.length;
               
               int nextWordId = currentWordId;
               if (targetChunkCursor < chunkToWordMap.length) {
                  nextWordId = chunkToWordMap[targetChunkCursor];
               } else if (chunkToWordMap.isNotEmpty) {
                  nextWordId = chunkToWordMap.last + 1;
               }

               if (nextWordId > currentWordId) {
                   debugLog('>>> HIGHLIGHTING SKIPPED WORDS [$currentWordId to ${nextWordId - 1}]');
                   for (int w = currentWordId; w < nextWordId; w++) {
                      mainSendPort.send({'event': 'highlight', 'word_id': w});
                   }
                   currentWordId = nextWordId;
               }
               
               // Find how many ASR characters to safely consume during catchup
               int maxPredIdx = -1;
               for (var align in catchupAlignments) {
                 if (align.predIdx > maxPredIdx) {
                   maxPredIdx = align.predIdx;
                 }
               }
               
               if (maxPredIdx >= 0) {
                 int consumedChars = 0;
                 for (int k = 0; k <= maxPredIdx && k < currentAsrChunks.length; k++) {
                   consumedChars += currentAsrChunks[k].length;
                 }
                 int charsToChop = consumedChars;
                 asrConsumedChars += charsToChop;
               }
               break; // Exit catch-up loop
           }
        }
        
      }
    }
  });
}
