import 'dart:async';
import 'dart:math';

import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'quran_normalizer.dart';
import 'phoneme_matrix.dart';
import '../../utils/debug_logger.dart';

///
/// FILE ROLE: Orchestrator / Thread Manager / App State (Web Async Stream Version)
/// ARCHITECTURE: StreamController asynchronous message pipeline
/// DEPENDENCIES: dictation_matcher.dart (Engine), quran_normalizer.dart (Text Prep)
/// RESPONSIBILITY:
/// - Manages the `asrWindow` buffer (raw audio phonetic stream).
/// - Manages the `targetWordCursor` (which word the user is currently reading).
/// - Slices 'lookahead' windows of text to feed into the Matcher.
/// - Routes successful matches through the Tajweed `ErrorExplainer`.
/// - Emits final JSON payloads ('highlight' events) back to the Flutter UI thread.
///

/// ────────────────────────────────────────────────────────────────────────────
/// [IsolateCommands] - Communication Protocol
/// ────────────────────────────────────────────────────────────────────────────
class IsolateCommands {
  static const int setup = 0;
  static const int syncStream = 1; // Sync full ASR stream for current segment
  static const int setAyah = 2; // Initialize a new Ayah with expected phonemes
  static const int shutdown = 3; // Terminate the worker
  static const int setTajweedMode = 5; // Toggle tajweed mode
  static const int setTrackingStrictness = 6; // Set strictness mode
}

/// ────────────────────────────────────────────────────────────────────────────
/// [PhonemeAlignmentIsolate] - The Worker Manager
/// ────────────────────────────────────────────────────────────────────────────
class PhonemeAlignmentIsolate {
  StreamController<dynamic>? _commandPort;
  StreamController<dynamic>? _receivePort;

  final StreamController<Map<String, dynamic>> _wordStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wordStream => _wordStreamController.stream;

  Future<void> start() async {
    _commandPort = StreamController<dynamic>();
    _receivePort = StreamController<dynamic>();

    _alignmentWorker(_receivePort!.sink, _commandPort!.stream);

    _receivePort!.stream.listen((message) {
      if (message is Map) {
        if (message['event'] == 'highlight') {
          _wordStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'debug') {
          DebugLogger.updateAsrBuffer(message['asr_buffer'] as String? ?? '');
          DebugLogger.log('DP', message['message'] as String);
        }
      }
    });
  }

  /// Sends the dynamic tokens list to preheat the phoneme matrix.
  void setup(List<String> tokens) {
    _commandPort?.add({'cmd': IsolateCommands.setup, 'tokens': tokens});
  }

  /// Tells the worker to load a new Ayah.
  void setAyah(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
    String trackingStrictness = 'normal',
    int startWordCursor = 0,
    int ayahNumber = 0,
  }) {
    _commandPort?.add({
      'cmd': IsolateCommands.setAyah,
      'phonemes': expectedPhonemes,
      'boundaries': wordBoundaries,
      'isTajweed': isTajweed,
      'forceClear': forceClear,
      'trackingStrictness': trackingStrictness,
      'startWordCursor': startWordCursor,
      'ayahNumber': ayahNumber,
    });
  }

  /// Sends the full unconsumed segment string and its timestamps to the worker.
  void syncStream(
    String fullSegmentAsr,
    List<double> segmentTimestamps, [
    List<double>? segmentYsProbs,
    bool isNewSegment = false,
    int ayahNumber = 0,
  ]) {
    _commandPort?.add({
      'cmd': IsolateCommands.syncStream,
      'asr': fullSegmentAsr,
      'timestamps': segmentTimestamps,
      'ysProbs': segmentYsProbs ?? [],
      'isNewSegment': isNewSegment,
      'ayahNumber': ayahNumber,
    });
  }

  void setTajweedMode(bool isTajweed) {
    _commandPort?.add({
      'cmd': IsolateCommands.setTajweedMode,
      'isTajweed': isTajweed,
    });
  }

  void setTrackingStrictness(String strictness) {
    _commandPort?.add({
      'cmd': IsolateCommands.setTrackingStrictness,
      'strictness': strictness,
    });
  }

  void stop() {
    _commandPort?.add({'cmd': IsolateCommands.shutdown});
    _wordStreamController.close();
    _commandPort?.close();
    _receivePort?.close();
  }
}

typedef PhonemeAlignmentWeb = PhonemeAlignmentIsolate;

/// ────────────────────────────────────────────────────────────────────────────
/// [DictationSequencer] - The App Logic Orchestrator
/// ────────────────────────────────────────────────────────────────────────────
class DictationSequencer {
  final Sink<dynamic> mainSendPort;

  // ---------------------------------------------------------------------------
  // Reference State (The perfect text)
  // ---------------------------------------------------------------------------
  List<int> wordBoundaries = [];
  List<String> refChunks = [];
  List<int> chunkToWordMap = [];
  List<bool> startBd = [];
  List<bool> endBd = [];

  bool isTajweed = false;
  String trackingStrictness = 'normal';

  // ---------------------------------------------------------------------------
  // ASR State (The messy audio)
  // ---------------------------------------------------------------------------
  /// The full string of phonetic sounds the microphone has heard in the current segment.
  String currentSegmentAsr = '';

  /// The timestamps corresponding to every character in the `currentSegmentAsr`.
  List<double> currentSegmentTimestamps = [];

  /// The acoustic confidence (log probability) corresponding to every character.
  List<double> currentSegmentYsProbs = [];

  /// The number of valid phoneme tokens the DP engine has successfully consumed
  /// from the `currentSegmentAsr` stream.
  int asrConsumedTokenCount = 0;

  // ---------------------------------------------------------------------------
  // Output State
  // ---------------------------------------------------------------------------
  List<String> acceptedWordsAsr = [];
  List<List<double>> acceptedWordsTimestamps = [];

  /// The most important variable in the orchestrator.
  /// This points to the Word ID that we are actively trying to highlight next.
  int targetWordCursor = 0;

  /// [Tajweed] Stores the very last phoneme of the previously matched word.
  String? lastMatchedPhoneme;

  /// Current Ayah number being tracked
  int currentAyahNumber = 0;

  /// The purely mathematical engine.
  final ForwardDictationMatcher _matcher = ForwardDictationMatcher();

  DictationSequencer(this.mainSendPort);

  void debugLog(String message) {
    mainSendPort.add({
      'event': 'debug',
      'message': message,
      'asr_buffer': currentSegmentAsr,
    });
  }

  /// --------------------------------------------------------------------------
  /// Ayah Initialization
  /// --------------------------------------------------------------------------
  void setAyah(Map message) {
    currentAyahNumber = message['ayahNumber'] as int? ?? 0;
    String expectedPhonemes = (message['phonemes'] as String).replaceAll(
      ' ',
      '',
    );
    wordBoundaries = message['boundaries'] as List<int>;
    isTajweed = message['isTajweed'] as bool? ?? false;
    trackingStrictness =
        message['trackingStrictness'] as String? ?? trackingStrictness;
    bool forceClear = message['forceClear'] as bool? ?? false;

    refChunks = QuranNormalizer.chunkPhonemes(expectedPhonemes);
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

    int n = refChunks.length;
    startBd = List.filled(n + 1, false);
    endBd = List.filled(n + 1, false);

    if (n > 0) {
      startBd[0] = true;
      for (int j = 1; j < n; j++) {
        if (chunkToWordMap[j] != chunkToWordMap[j - 1]) {
          startBd[j] = true;
          endBd[j] = true;
        }
      }
      startBd[n] = false;
      endBd[n] = true;
    }

    int wordCount = wordBoundaries.length - 1;

    if (forceClear) {
      currentSegmentAsr = '';
      currentSegmentTimestamps = [];
      currentSegmentYsProbs = [];
      asrConsumedTokenCount = 0;
      targetWordCursor = 0;
    } else {
      int startCursor = message['startWordCursor'] as int? ?? 0;
      targetWordCursor = startCursor.clamp(0, wordCount);
    }

    acceptedWordsAsr = List.filled(wordCount, '');
    acceptedWordsTimestamps = List.generate(wordCount, (_) => []);
    lastMatchedPhoneme = null;

    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );
    debugLog(
      '📖 [AYAH SET] Ayah: $currentAyahNumber | Words: ${wordBoundaries.length - 1} | Tajweed: $isTajweed | Strict: $trackingStrictness | Ref Chunks: ${refChunks.length} | Consumed: $asrConsumedTokenCount',
    );
    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );

    if (!forceClear && currentSegmentAsr.isNotEmpty) {
      _processSequence();
    }
  }

  /// --------------------------------------------------------------------------
  /// ASR Data Ingestion
  /// --------------------------------------------------------------------------
  void syncStream(Map message) {
    int msgAyahNumber = message['ayahNumber'] as int? ?? 0;
    if (msgAyahNumber != 0 && currentAyahNumber != 0 && msgAyahNumber != currentAyahNumber) {
      debugLog('🚫 [WORKER] Dropping syncStream for mismatched ayah $msgAyahNumber (current is $currentAyahNumber)');
      return;
    }

    String newAsr = message['asr'];
    List<double> newTimestamps = List<double>.from(message['timestamps']);
    List<double> newYsProbs = List<double>.from(message['ysProbs'] ?? []);
    bool isNewSegment = message['isNewSegment'] ?? false;

    if (isNewSegment) {
      asrConsumedTokenCount = 0;
      debugLog('🔄 [SYNC] New ASR segment started. Consumed tokens reset to 0.');
    }

    currentSegmentAsr = newAsr;
    currentSegmentTimestamps = newTimestamps;
    currentSegmentYsProbs = newYsProbs;

    _processSequence();
  }

  /// --------------------------------------------------------------------------
  /// The Core Orchestration Loop
  /// --------------------------------------------------------------------------
  void _processSequence() {
    bool matchedSomething;
    do {
      matchedSomething = false;

      if (targetWordCursor >= wordBoundaries.length - 1) break;

      List<PhonemeToken> rawTokens = QuranNormalizer.chunkPhonemesWithIndices(currentSegmentAsr);
      List<PhonemeToken> cleanTokens = rawTokens
          .where((t) => t.text.trim().isNotEmpty && t.text != '<blank>' && t.text != 'ؙ')
          .toList();

      if (cleanTokens.length < asrConsumedTokenCount) {
        asrConsumedTokenCount = cleanTokens.length;
      }

      List<PhonemeToken> unconsumedTokens = cleanTokens.sublist(asrConsumedTokenCount);

      if (unconsumedTokens.isEmpty) break;

      int m = unconsumedTokens.length;

      // Buffer Management (Garbage Collection)
      int maxAsrChunks = 150;
      if (m > maxAsrChunks) {
         int chunksToDrop = m - maxAsrChunks;
         asrConsumedTokenCount += chunksToDrop;
         unconsumedTokens = unconsumedTokens.sublist(chunksToDrop);
         m = unconsumedTokens.length;
         debugLog(
          '🗑️ [BUFFER GC] Dropped $chunksToDrop oldest tokens to prevent lag (Max $maxAsrChunks reached)',
        );
      }

      int winStartChunk = -1;
      int winEndChunk = refChunks.length;

      // Dynamic Lookahead Windowing
      int currentRefPhonemes = 0;
      int endWordLimit = targetWordCursor;

      for (int i = 0; i < refChunks.length; i++) {
        if (chunkToWordMap[i] == targetWordCursor && winStartChunk == -1) {
          winStartChunk = i;
          break;
        }
      }

      if (winStartChunk != -1) {
        for (int i = winStartChunk; i < refChunks.length; i++) {
          currentRefPhonemes++;
          endWordLimit = chunkToWordMap[i];
          if (currentRefPhonemes >= m) {
            break;
          }
        }
      }

      int lookaheadWords = trackingStrictness == 'easy' ? 0 : 2;
      endWordLimit += lookaheadWords;

      if (trackingStrictness == 'easy') {
        endWordLimit = targetWordCursor;
      }
      if (endWordLimit > wordBoundaries.length - 1) {
        endWordLimit = wordBoundaries.length - 1;
      }

      for (int i = 0; i < refChunks.length; i++) {
        if (chunkToWordMap[i] == targetWordCursor && winStartChunk == -1) {
          winStartChunk = i;
        }
        if (winStartChunk != -1 && chunkToWordMap[i] > endWordLimit) {
          winEndChunk = i;
          break;
        }
      }

      if (winStartChunk == -1) break;

      debugLog(
        '🔍 [WINDOW] Analyzing reference chunks [$winStartChunk..${winEndChunk - 1}] (Words $targetWordCursor..$endWordLimit). ASR buffer size: $m chunks.',
      );

      List<String> targetWindow = refChunks.sublist(winStartChunk, winEndChunk);
      List<int> targetWordIds = chunkToWordMap.sublist(
        winStartChunk,
        winEndChunk,
      );
      List<bool> targetStartBd = startBd.sublist(
        winStartChunk,
        winEndChunk + 1,
      );
      List<bool> targetEndBd = endBd.sublist(winStartChunk, winEndChunk + 1);

      double threshold = trackingStrictness == 'easy'
          ? 0.35
          : (trackingStrictness == 'strict' ? 0.15 : 0.25);

      double dynamicCostDel = trackingStrictness == 'easy' ? 0.65 : 1.0;
      double dynamicCostIns = trackingStrictness == 'easy' ? 0.65 : 1.0;

      // [HADR MODE] Dynamic Strictness for Fast Readers
      double averagePhonemeDuration = 0.15;
      int unconsumedCharStart = _getCharIndexForToken(cleanTokens, asrConsumedTokenCount);
      if (unconsumedCharStart < currentSegmentTimestamps.length) {
          double totalDur = 0;
          int durCount = 0;
          for (int c = unconsumedCharStart; c < currentSegmentTimestamps.length; c++) {
              totalDur += currentSegmentTimestamps[c];
              durCount++;
          }
          if (durCount > 0) {
              averagePhonemeDuration = totalDur / durCount;
          }
      }

      if (averagePhonemeDuration < 0.08 && trackingStrictness != 'easy') {
          dynamicCostDel = 0.75;
      }

      final stopwatch = Stopwatch()..start();

      List<String> unconsumedStrings = unconsumedTokens.map((t) => t.text).toList();

      AlignmentResult? result = _matcher.align(
        currentAsrChunks: unconsumedStrings,
        targetWindow: targetWindow,
        targetStartBd: targetStartBd,
        targetEndBd: targetEndBd,
        targetWordIds: targetWordIds,
        expectedWord: targetWordCursor,
        asrYsProbs: _getUnconsumedYsProbs(cleanTokens, asrConsumedTokenCount),
        threshold: threshold,
        costDel: dynamicCostDel,
        costIns: dynamicCostIns,
        requireStableTail: isTajweed,
        debugLog: debugLog,
      );

      stopwatch.stop();
      if (result != null || stopwatch.elapsedMilliseconds > 2) {
        debugLog(
          '⏱️ [WORKER] DP Matrix calculated in ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (result != null) {
        _commitMatch(
          result,
          unconsumedTokens,
          cleanTokens,
          targetWindow,
          targetWordIds,
          winStartChunk,
        );
        matchedSomething = true;
      }
    } while (matchedSomething);
  }

  /// --------------------------------------------------------------------------
  /// Match Finalization & Tajweed Routing
  /// --------------------------------------------------------------------------
  void _commitMatch(
    AlignmentResult result,
    List<PhonemeToken> unconsumedTokens,
    List<PhonemeToken> fullCleanTokens,
    List<String> targetWindow,
    List<int> targetWordIds,
    int winStartChunk,
  ) {
    int n = targetWindow.length;

    int matchedWordStart =
        targetWordIds[result.bestStartJ < n ? result.bestStartJ : n - 1];
    int matchedWordEnd = targetWordIds[result.bestJ - 1];

    List<String> matchedAsrSlice = unconsumedTokens.sublist(
      result.bestStartI,
      result.bestI,
    ).map((t) => t.text).toList();
    List<String> matchedRefSlice = targetWindow.sublist(
      result.bestStartJ,
      result.bestJ,
    );

    List<PhonemeGroupAlignment> localAlignments = result.trace;

    List<PhonemeGroupAlignment> globalAlignments = localAlignments.map((a) {
      return PhonemeGroupAlignment(
        opType: a.opType,
        refIdx: a.refIdx >= 0
            ? winStartChunk + result.bestStartJ + a.refIdx
            : -1,
        predIdx: a.predIdx >= 0 ? a.predIdx : -1,
      );
    }).toList();

    Map<int, String> wordPredStrMap = {};
    Map<int, List<double>> wordPredTsMap = {};

    for (var align in localAlignments) {
      if (align.refIdx < 0 || align.predIdx < 0) continue;
      int absRefIdx = winStartChunk + result.bestStartJ + align.refIdx;
      if (absRefIdx >= chunkToWordMap.length) continue;

      int wId = chunkToWordMap[absRefIdx];
      if (wId < matchedWordStart || wId > matchedWordEnd) continue;

      int absPredIdx = result.bestStartI + align.predIdx;
      String chunk = unconsumedTokens[absPredIdx].text;
      wordPredStrMap[wId] = (wordPredStrMap[wId] ?? '') + chunk;

      int globalTokenIdx = asrConsumedTokenCount + absPredIdx;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalTokenIdx);
      
      for (int c = 0; c < chunk.length; c++) {
        if (charStart + c < currentSegmentTimestamps.length) {
          wordPredTsMap
              .putIfAbsent(wId, () => [])
              .add(currentSegmentTimestamps[charStart + c]);
        }
      }
    }

    for (int w = matchedWordStart; w <= matchedWordEnd; w++) {
      acceptedWordsAsr[w] = wordPredStrMap[w] ?? '';
      acceptedWordsTimestamps[w] = wordPredTsMap[w] ?? [];
    }

    // [Tajweed] Primary Evaluation Block
    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      int globalStartIdx = asrConsumedTokenCount + result.bestStartI;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalStartIdx);
      int safeStartIdx = min(charStart, currentSegmentTimestamps.length);

      tajweedErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: globalAlignments,
        globalRefChunks: refChunks,
        refChunkToWordMap: chunkToWordMap,
        currentAsrChunks: matchedAsrSlice,
        trackingTimestamps: currentSegmentTimestamps.sublist(safeStartIdx),
        bestAsrStartIdx: 0,
        targetChunkCursor: 0,
        startWordId: matchedWordStart,
        nextWordId: matchedWordEnd + 1,
        totalAyahWords: wordBoundaries.length - 1,
        matchScore: result.pureAcousticScore,
        previousWordTail: lastMatchedPhoneme,
        trackingStrictness: trackingStrictness,
      );
    }

    for (int w = targetWordCursor; w <= matchedWordEnd; w++) {
      bool isSkipped =
          (w < matchedWordStart) ||
          !result.words.any((match) => match.wordId == w);

      // [ASR FAULT DETECTION "THE SHIELD"]
      if (isSkipped && result.shieldedWords.contains(w)) {
        continue;
      }

      if (isSkipped) {
        String skippedWordStr = '';
        for (int i = 0; i < refChunks.length; i++) {
          if (chunkToWordMap[i] == w) skippedWordStr += refChunks[i];
        }
        debugLog('🩸 [HIGHLIGHT] Word "$skippedWordStr" ($w) skipped -> RED');
      }

      List<Map<String, dynamic>> serializedErrors = [];
      if (!isSkipped && tajweedErrors != null && tajweedErrors.containsKey(w)) {
        serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
      }

      mainSendPort.add({
        'event': 'highlight',
        'word_id': w,
        'is_red': isSkipped,
        'clean_asr': isSkipped ? '' : acceptedWordsAsr[w],
        'word_asr': acceptedWordsAsr,
        'tajweed_errors': serializedErrors,
      });
    }

    targetWordCursor = matchedWordEnd + 1;
    asrConsumedTokenCount += result.bestI;

    if (matchedRefSlice.isNotEmpty) {
      lastMatchedPhoneme = matchedRefSlice.last;
    }
  }

  // ---------------------------------------------------------------------------
  // Helper Math
  // ---------------------------------------------------------------------------
  
  int _getCharIndexForToken(List<PhonemeToken> tokens, int tokenIndex) {
     if (tokenIndex >= tokens.length) return currentSegmentAsr.length;
     return tokens[tokenIndex].originalIndex;
  }

  List<double> _getUnconsumedYsProbs(List<PhonemeToken> cleanTokens, int consumedCount) {
     int charStart = _getCharIndexForToken(cleanTokens, consumedCount);
     if (charStart < currentSegmentYsProbs.length) {
        return currentSegmentYsProbs.sublist(charStart);
     }
     return [];
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// Worker Entrypoint
/// ────────────────────────────────────────────────────────────────────────────
void _alignmentWorker(Sink<dynamic> mainSendPort, Stream<dynamic> commandStream) {
  final sequencer = DictationSequencer(mainSendPort);

  commandStream.listen((message) {
    if (message is! Map) return;
    int cmd = message['cmd'];

    switch (cmd) {
      case IsolateCommands.setup:
        List<String> tokens = (message['tokens'] as List).cast<String>();
        PhonemeMatrix.preheat(tokens);
        break;
      case IsolateCommands.syncStream:
        sequencer.syncStream(message);
        break;
      case IsolateCommands.setAyah:
        sequencer.setAyah(message);
        break;
      case IsolateCommands.setTajweedMode:
        sequencer.isTajweed = message['isTajweed'];
        break;
      case IsolateCommands.setTrackingStrictness:
        sequencer.trackingStrictness = message['strictness'];
        break;
      case IsolateCommands.shutdown:
        break;
    }
  });
}
