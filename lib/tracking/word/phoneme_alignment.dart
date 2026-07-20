import 'dart:async';

import 'dart:math';

import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'quran_normalizer.dart';
import 'phoneme_matrix.dart';

///
/// FILE ROLE: Orchestrator / Thread Manager / App State
/// ARCHITECTURE: Dart Isolate (Background Thread)
/// DEPENDENCIES: dictation_matcher.dart (Engine), quran_normalizer.dart (Text Prep)
/// RESPONSIBILITY:
/// - Manages the `asrWindow` buffer (raw audio phonetic stream).
/// - Manages the `targetWordCursor` (which word the user is currently reading).
/// - Slices 'lookahead' windows of text to feed into the Matcher.
/// - Routes successful matches through the Tajweed `ErrorExplainer`.
/// - Emits final JSON payloads ('highlight' events) back to the Flutter UI thread.
/// AI NOTE: Do NOT modify the mathematical alignment DP logic here; that belongs in `dictation_matcher.dart`.
/// Do NOT modify penalty logic here; that belongs in `phoneme_matrix.dart`.
///

/// ────────────────────────────────────────────────────────────────────────────
/// [IsolateCommands] - Inter-thread Communication Protocol
/// ────────────────────────────────────────────────────────────────────────────
/// Because phonetic alignment is mathematically intense, running it on the main UI
/// thread would cause the app to freeze and drop frames (jank).
/// Instead, we run it in a background "Isolate" (a separate CPU thread).
///
/// Since Isolates do not share memory, they can only communicate by passing messages.
/// This class defines the integer "commands" the UI uses to tell the background
/// thread what to do.
class IsolateCommands {
  static const int setup = 0;
  static const int feed = 1; // Feed new ASR phonetic stream chunks
  static const int setAyah = 2; // Initialize a new Ayah with expected phonemes
  static const int shutdown = 3; // Terminate the isolate
  static const int replaceTail = 4; // Backtrack and replace unstable ASR tail
  static const int setTajweedMode = 5; // Toggle tajweed mode
  static const int setTrackingStrictness = 6; // Set strictness mode
}

/// ────────────────────────────────────────────────────────────────────────────
/// [PhonemeAlignmentIsolate] - The Isolate Manager (UI Thread Side)
/// ────────────────────────────────────────────────────────────────────────────
/// This class lives on the MAIN UI THREAD.
/// Its only job is to start the background thread, send it messages, and
/// listen for the "highlight" events coming back to update the screen.
class PhonemeAlignmentWeb {
  StreamController<dynamic>? _sendPort;

  /// A stream that emits the final results (which word to highlight, and any
  /// Tajweed errors found in that word). The Flutter UI listens to this stream.
  final StreamController<Map<String, dynamic>> _wordStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wordStream => _wordStreamController.stream;

  final StreamController<Map<String, dynamic>> _ayahCompletedStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get ayahCompletedStream =>
      _ayahCompletedStreamController.stream;

  /// Starts the background isolate.
  Future<void> start() async {
    final receivePort = StreamController<dynamic>();
    _sendPort = StreamController<dynamic>();

    // Run directly on the main event loop
    _alignmentWorker(receivePort.sink, _sendPort!.stream);

    receivePort.stream.listen((message) {
      if (message is Map) {
        if (message['event'] == 'highlight') {
          // A word was successfully matched in the background! Send it to the UI.
          _wordStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'ayah_completed') {
          _ayahCompletedStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'debug') {
          print('[WEB WORKER] ${message['message']}');
        }
      }
    });
  }

  /// Sends the dynamic tokens list to preheat the phoneme matrix.
  void setup(List<String> tokens) {
    _sendPort?.add({
      'cmd': IsolateCommands.setup,
      'tokens': tokens,
    });
  }

  /// Tells the background thread to load a new Ayah.
  void setAyah(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
    String trackingStrictness = 'normal',
  }) {
    _sendPort?.add({
      'cmd': IsolateCommands.setAyah,
      'phonemes': expectedPhonemes,
      'boundaries': wordBoundaries,
      'isTajweed': isTajweed,
      'forceClear': forceClear,
      'trackingStrictness': trackingStrictness,
    });
  }

  /// Sends raw, messy audio chunks from the microphone to the background thread.
  void feed(String asrChunk, List<double> timestampsChunk) {
    _sendPort?.add({
      'cmd': IsolateCommands.feed,
      'asr': asrChunk,
      'timestamps': timestampsChunk,
    });
  }

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

  void setTajweedMode(bool isTajweed) {
    _sendPort?.add({
      'cmd': IsolateCommands.setTajweedMode,
      'isTajweed': isTajweed,
    });
  }

  void setTrackingStrictness(String strictness) {
    _sendPort?.add({
      'cmd': IsolateCommands.setTrackingStrictness,
      'strictness': strictness,
    });
  }

  void stop() {
    _sendPort?.add({'cmd': IsolateCommands.shutdown});
    _wordStreamController.close();
    _ayahCompletedStreamController.close();
    _sendPort?.close();
    _sendPort = null;
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// [DictationSequencer] - The App Logic Orchestrator (Background Thread Side)
/// ────────────────────────────────────────────────────────────────────────────
/// This class lives entirely in the BACKGROUND THREAD.
///
/// It acts as the "Traffic Controller" between the incoming raw audio (ASR)
/// and the purely mathematical `ForwardDictationMatcher`.
///
/// It maintains state:
/// - What word are we currently waiting for the user to say? (`targetWordCursor`)
/// - How much "garbage" audio is currently buffered? (`asrWindow`)
/// - What was the last phoneme matched? (`lastMatchedPhoneme` for Tajweed bridging)
///
/// It constructs the "Lookahead Window" (a small slice of the Ayah) and feeds it
/// to the Matcher. If the Matcher finds a match, the Sequencer cuts out the
/// matched audio, advances the cursor, and sends a highlight event to the UI.
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
  /// The accumulated string of phonetic sounds the microphone has heard.
  String asrWindow = '';

  /// The timestamps corresponding to every character in the `asrWindow`.
  List<double> asrTimestamps = [];

  // ---------------------------------------------------------------------------
  // Output State
  // ---------------------------------------------------------------------------
  List<String> acceptedWordsAsr = [];
  List<List<double>> acceptedWordsTimestamps = [];

  /// The most important variable in the orchestrator.
  /// This points to the Word ID that we are actively trying to highlight next.
  int targetWordCursor = 0;

  /// [Tajweed] Stores the very last phoneme of the previously matched word.
  /// If Word 1 ends in a Nun Sakinah, and Word 2 begins with a Waw, the Tajweed
  /// engine needs to know what the end of Word 1 sounded like to verify an Idgham.
  String? lastMatchedPhoneme;

  /// The purely mathematical engine.
  final ForwardDictationMatcher _matcher = ForwardDictationMatcher();

  DictationSequencer(this.mainSendPort);

  void debugLog(String message) {
    mainSendPort.add({'event': 'debug', 'message': message});
  }

  /// --------------------------------------------------------------------------
  /// Ayah Initialization
  /// --------------------------------------------------------------------------
  /// Parses the raw string of the entire Ayah into individual phoneme chunks,
  /// maps them to specific Word IDs, and builds the boolean boundary arrays.
  void setAyah(Map message) {
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

    if (forceClear) {
      asrWindow = '';
      asrTimestamps = [];
    }

    int wordCount = wordBoundaries.length - 1;
    acceptedWordsAsr = List.filled(wordCount, '');
    acceptedWordsTimestamps = List.generate(wordCount, (_) => []);

    targetWordCursor = 0;
    lastMatchedPhoneme = null;

    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );
    debugLog(
      '📖 [AYAH SET] Words: ${wordBoundaries.length - 1} | Tajweed: $isTajweed | Strict: $trackingStrictness | Ref Chunks: ${refChunks.length}',
    );
    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );
  }

  /// --------------------------------------------------------------------------
  /// ASR Data Ingestion
  /// --------------------------------------------------------------------------
  /// Whenever the microphone hears a new sound, it is appended to the buffer here.
  /// Then, we instantly kick off a processing loop to see if those new sounds
  /// are enough to complete the word we are waiting for.
  void feed(String newAsr, List<double> newTimestamps) {
    asrWindow += newAsr;
    asrTimestamps.addAll(newTimestamps);
    _processSequence(); // <--- Trigger the engine!
  }

  void replaceTail(
    int backtrack,
    String newTail,
    List<double> newTailTimestamps,
  ) {
    if (backtrack <= asrWindow.length) {
      int newLength = asrWindow.length - backtrack;
      asrWindow = asrWindow.substring(0, newLength) + newTail;
      if (newLength <= asrTimestamps.length) {
        asrTimestamps = asrTimestamps.sublist(0, newLength)
          ..addAll(newTailTimestamps);
      }
    } else {
      asrWindow = newTail;
      asrTimestamps = newTailTimestamps;
    }
    debugLog(
      '⏪ [ASR REWRITE] Backtrack $backtrack chars | New Tail: "$newTail" | Buffer: "$asrWindow"',
    );
    _processSequence();
  }

  /// --------------------------------------------------------------------------
  /// The Core Orchestration Loop
  /// --------------------------------------------------------------------------
  /// This loop is where the magic happens. It takes the giant buffer of messy
  /// audio, slices a smart "Lookahead Window" out of the Reference Ayah, and
  /// asks the Math Engine if there's a match.
  ///
  /// If there IS a match, it commits the match, slices the garbage out of the
  /// audio buffer, and loops again immediately (in case the user read really fast
  /// and there are 2 words hiding inside the audio buffer!).
  void _processSequence() {
    bool matchedSomething;
    do {
      matchedSomething = false;

      // If we finished the Ayah, do nothing.
      if (targetWordCursor >= wordBoundaries.length - 1) break;

      List<String> asrChunks = QuranNormalizer.chunkPhonemes(asrWindow);
      if (asrChunks.isEmpty) break;

      int m = asrChunks.length;

      // -----------------------------------------------------------------------
      // Buffer Management (Garbage Collection)
      // -----------------------------------------------------------------------
      // If the user sat there coughing or talking to their friend for 10 seconds,
      // the audio buffer will fill up with garbage. If it gets too large, the
      // DP Engine will lag. We aggressively truncate the buffer to a max size.
      int maxAsrChunks = 50;
      if (m > maxAsrChunks) {
        int chunksToDrop = m - maxAsrChunks;
        int charsToDrop = 0;
        for (int k = 0; k < chunksToDrop; k++) {
          charsToDrop += asrChunks[k].length;
        }

        asrWindow = asrWindow.substring(charsToDrop);
        if (charsToDrop <= asrTimestamps.length) {
          asrTimestamps = asrTimestamps.sublist(charsToDrop);
        } else {
          asrTimestamps = [];
        }

        asrChunks = asrChunks.sublist(chunksToDrop);
        m = asrChunks.length;
        debugLog(
          '🗑️ [BUFFER GC] Dropped $chunksToDrop oldest chunks to prevent lag (Max $maxAsrChunks reached)',
        );
      }

      int winStartChunk = -1;
      int winEndChunk = refChunks.length;

      // -----------------------------------------------------------------------
      // Dynamic Lookahead Windowing
      // -----------------------------------------------------------------------
      // We don't want to compare the tiny audio buffer against the ENTIRE AYAH.
      // That is mathematically expensive. Instead, we estimate how many words
      // the user could have possibly spoken based on the size of the audio buffer.
      // We assume ~5 phonemes per word on average.
      int estWords = max(1, (m / 5.0).round());
      int lookaheadWords = 2; // Extra buffer just to be safe

      int endWordLimit = targetWordCursor + estWords + lookaheadWords;
      if (endWordLimit > wordBoundaries.length - 1) {
        endWordLimit = wordBoundaries.length - 1;
      }

      // We slice the Reference text starting precisely at the word we are expecting,
      // and ending at our dynamic lookahead limit.
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

      // Strictness determines the acceptable penalty threshold.
      double threshold = trackingStrictness == 'easy'
          ? 0.35
          : (trackingStrictness == 'strict' ? 0.15 : 0.25);

      // -----------------------------------------------------------------------
      // The Engine Call
      // -----------------------------------------------------------------------
      // We ask the purely mathematical ForwardDictationMatcher to find a path.
      AlignmentResult? result = _matcher.align(
        currentAsrChunks: asrChunks,
        targetWindow: targetWindow,
        targetStartBd: targetStartBd,
        targetEndBd: targetEndBd,
        targetWordIds: targetWordIds,
        expectedWord: targetWordCursor,
        threshold: threshold,
        // EDGE-BOUND TAIL STABILITY RULE:
        // Only active during Tajweed mode. If true, the DP engine refuses to commit
        // to a match if the word is pushed against the leading edge of the audio stream
        // and ends in a deletion, because the user might just be holding a long vowel (Madd).
        // It forces the engine to wait for the final consonant to arrive.
        requireStableTail: isTajweed,
        debugLog: debugLog,
      );

      // If a path was successfully found below the penalty threshold...
      if (result != null) {
        // ...we finalize the match and clean out the used audio buffer.
        _commitMatch(
          result,
          asrChunks,
          targetWindow,
          targetWordIds,
          winStartChunk,
        );
        // We set this to true so the loop runs AGAIN instantly!
        // This allows multi-word highlights if the buffer was full.
        matchedSomething = true;
      }
    } while (matchedSomething);
  }

  /// --------------------------------------------------------------------------
  /// Match Finalization & Tajweed Routing
  /// --------------------------------------------------------------------------
  /// A match was successful!
  /// This method slices the exact subset of the audio that matched, maps it
  /// to the exact words, routes it through the Tajweed ErrorExplainer if needed,
  /// and fires the highlight message to the UI.
  void _commitMatch(
    AlignmentResult result,
    List<String> asrChunks,
    List<String> targetWindow,
    List<int> targetWordIds,
    int winStartChunk,
  ) {
    int n = targetWindow.length;

    // Determine exactly which word(s) this match belonged to.
    int matchedWordStart =
        targetWordIds[result.bestStartJ < n ? result.bestStartJ : n - 1];
    int matchedWordEnd = targetWordIds[result.bestJ - 1];

    List<String> matchedAsrSlice = asrChunks.sublist(
      result.bestStartI,
      result.bestI,
    );
    List<String> matchedRefSlice = targetWindow.sublist(
      result.bestStartJ,
      result.bestJ,
    );

    List<PhonemeGroupAlignment> localAlignments = result.trace;

    // Convert the local window indices into global Ayah indices for the ErrorExplainer.
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

    // Group the ASR sounds and timestamps strictly into their respective word bins.
    for (var align in localAlignments) {
      if (align.refIdx < 0 || align.predIdx < 0) continue;
      int absRefIdx = winStartChunk + result.bestStartJ + align.refIdx;
      if (absRefIdx >= chunkToWordMap.length) continue;

      int wId = chunkToWordMap[absRefIdx];
      if (wId < matchedWordStart || wId > matchedWordEnd) continue;

      int absPredIdx = result.bestStartI + align.predIdx;
      String chunk = asrChunks[absPredIdx];
      wordPredStrMap[wId] = (wordPredStrMap[wId] ?? '') + chunk;

      int charStart = 0;
      for (int k = 0; k < absPredIdx; k++) charStart += asrChunks[k].length;
      for (int c = 0; c < chunk.length; c++) {
        if (charStart + c < asrTimestamps.length) {
          wordPredTsMap
              .putIfAbsent(wId, () => [])
              .add(asrTimestamps[charStart + c]);
        }
      }
    }

    for (int w = matchedWordStart; w <= matchedWordEnd; w++) {
      acceptedWordsAsr[w] = wordPredStrMap[w] ?? '';
      acceptedWordsTimestamps[w] = wordPredTsMap[w] ?? [];
    }

    // -------------------------------------------------------------------------
    // [Tajweed] Primary Evaluation Block
    // -------------------------------------------------------------------------
    // If Tajweed mode is on, we send the perfectly aligned paths directly to the
    // professional ErrorExplainer rules engine.
    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      tajweedErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments:
            globalAlignments, // The exact operations (equal, replace, insert, delete)
        globalRefChunks: refChunks, // Full reference text
        refChunkToWordMap: chunkToWordMap, // Mapping chunks to word IDs
        currentAsrChunks: matchedAsrSlice, // The actual sounds the user spoke
        // Pass only the raw timestamps that belong to the user's spoken string slice
        trackingTimestamps: asrTimestamps.sublist(
          asrChunks
              .sublist(0, result.bestStartI)
              .fold(0, (sum, c) => sum + c.length),
        ),

        bestAsrStartIdx: 0,
        targetChunkCursor: 0,
        startWordId: matchedWordStart,
        nextWordId: matchedWordEnd + 1,
        totalAyahWords: wordBoundaries.length - 1,

        // [Tajweed] Confidence-Gating Parameter
        // Protects the UI from spamming false-positive red errors if the
        // microphone quality or acoustic match was poor.
        // We strictly use the `pureAcousticScore` here so Tajweed is not artificially
        // suppressed when the user simply skips a word (which inflates the global score).
        matchScore: result.pureAcousticScore,

        // [Tajweed] Cross-Word Context Parameter
        // Passes the final sound of the previous word so the explainer can
        // verify rules like Idgham that occur across word spaces.
        previousWordTail: lastMatchedPhoneme,

        // Pass the strictness setting to filter output errors based on user preference
        trackingStrictness: trackingStrictness,
      );
    }

    // -------------------------------------------------------------------------
    // Event Emission to UI
    // -------------------------------------------------------------------------

    // If the user skipped a word (e.g., they read Word 3, but the cursor was at Word 1),
    // the system correctly identifies it. We loop over all skipped words and explicitly
    // send them to the UI flagged as `is_red` (skipped/missed).
    for (int w = targetWordCursor; w <= matchedWordEnd; w++) {
      // A word is skipped if it was before the matched path, OR if the DP engine
      // dropped it for failing the strictness threshold (poorly pronounced/hallucinated).
      bool isSkipped = (w < matchedWordStart) || !result.words.any((match) => match.wordId == w);

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

      // This is the message the UI listens to!
      mainSendPort.add({
        'event': 'highlight',
        'word_id': w,
        'is_red': isSkipped,
        'clean_asr': isSkipped ? '' : acceptedWordsAsr[w],
        'word_asr': acceptedWordsAsr,
        'tajweed_errors': serializedErrors,
      });
    }

    // Move the cursor forward past the words we just successfully processed.
    targetWordCursor = matchedWordEnd + 1;

    // -------------------------------------------------------------------------
    // Buffer Slicing
    // -------------------------------------------------------------------------
    // We chop off all the garbage audio + the successfully matched audio from the buffer.
    // The next loop iteration will start perfectly fresh.
    int charSliceIdx = 0;
    for (int k = 0; k < result.bestI; k++) charSliceIdx += asrChunks[k].length;

    asrWindow = asrWindow.substring(charSliceIdx);
    if (charSliceIdx <= asrTimestamps.length) {
      asrTimestamps = asrTimestamps.sublist(charSliceIdx);
    } else {
      asrTimestamps = [];
    }

    // [Tajweed] Save the very last phoneme of this successful match to bridge to the next word
    if (matchedRefSlice.isNotEmpty) {
      lastMatchedPhoneme = matchedRefSlice.last;
    }
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// Worker Entrypoint
/// ────────────────────────────────────────────────────────────────────────────
/// This is the raw C-level entrypoint for the background Isolate thread.
/// It establishes the reverse communication port back to the UI thread, and
/// creates the Sequencer to start handling commands.
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
      case IsolateCommands.feed:
        sequencer.feed(
          message['asr'],
          (message['timestamps'] as List).cast<double>(),
        );
        break;
      case IsolateCommands.setAyah:
        sequencer.setAyah(message);
        break;
      case IsolateCommands.replaceTail:
        sequencer.replaceTail(
          message['backtrack'],
          message['tail'],
          (message['timestamps'] as List).cast<double>(),
        );
        break;
      case IsolateCommands.setTajweedMode:
        sequencer.isTajweed = message['isTajweed'];
        break;
      case IsolateCommands.setTrackingStrictness:
        sequencer.trackingStrictness = message['strictness'];
        break;
      case IsolateCommands.shutdown:
        // Streams close automatically
        break;
    }
  });
}
