import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../data/qiraat_ayah_mapper.dart';
import '../../data/quran_data.dart';
import '../../engine/sherpa_engine.dart';
import '../tajweed/error_explainer.dart';
import 'phoneme_alignment_isolate.dart';
import 'surah_highlight_store.dart';

export 'phoneme_alignment_isolate.dart';
export 'surah_highlight_store.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKING DOMAIN MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum TrackerState { discovery, tracking }

class VerseMatch {
  final QuranVerse verse;
  final double score;

  const VerseMatch({required this.verse, required this.score});

  dynamic operator [](String key) {
    if (key == 'surah') return verse.surah;
    if (key == 'ayah') return verse.ayah;
    if (key == 'score') return score;
    if (key == 'text' || key == 'text_uthmani') return verse.textUthmani;
    return null;
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// ASR ACOUSTIC TOKEN PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

class ProcessedAudioStream {
  final List<String> tokens;
  final List<double> durations;
  ProcessedAudioStream({required this.tokens, required this.durations});
  bool get isEmpty => tokens.isEmpty;
  bool get isNotEmpty => tokens.isNotEmpty;
}

class AsrTokenProcessor {
  TrackerConfig config;

  AsrTokenProcessor({this.config = const TrackerConfig()});

  double get lookaheadDelay => config.lookaheadDelay;
  double get maxTokenDuration => config.maxTokenDurationAllowed;

  List<String> _lastRawTokens = [];

  final List<String> _filteredTokens = [];
  final List<double> _filteredSpikeTimes = [];
  final List<double> _filteredLastBlanks = [];

  final List<double> _tokenDurations = [];

  void reset() {
    _lastRawTokens.clear();
    _filteredTokens.clear();
    _filteredSpikeTimes.clear();
    _filteredLastBlanks.clear();
    _tokenDurations.clear();
  }

  ProcessedAudioStream process(TranscriptionResult result) {
    final int maxCount = min(result.tokens.length, result.timestamps.length);

    int commonLen = 0;
    final int minLen = min(_lastRawTokens.length, maxCount);
    for (int i = 0; i < minLen; i++) {
      if (_lastRawTokens[i] == result.tokens[i]) {
        commonLen++;
      } else {
        break;
      }
    }

    if (commonLen < _lastRawTokens.length) {
      reset();
      commonLen = 0;
    }

    _lastRawTokens = result.tokens.sublist(0, maxCount);

    if (commonLen == maxCount) {
      return ProcessedAudioStream(
        tokens: _filteredTokens,
        durations: _tokenDurations,
      );
    }

    double lastBlankTs = _filteredLastBlanks.isNotEmpty ? _filteredLastBlanks.last : -1.0;

    for (int i = commonLen; i < maxCount; i++) {
      final String tok = result.tokens[i];
      final double realTs = max(0.0, result.timestamps[i] - lookaheadDelay);

      if (tok.isEmpty ||
          tok == '<blank>' ||
          tok == '<blk>' ||
          tok == '<eps>' ||
          tok == 'eps') {
        lastBlankTs = realTs;
        continue;
      }

      _filteredTokens.add(tok);
      _filteredSpikeTimes.add(realTs);
      _filteredLastBlanks.add(lastBlankTs);

      final int fIdx = _filteredTokens.length - 1;
      final double curSpike = _filteredSpikeTimes[fIdx];
      final double lastBlankBefore = _filteredLastBlanks[fIdx];

      // ── Max(Backward, Forward) Duration Attribution ──
      //
      // CTC spikes mark peak posterior probability, NOT sound onset.
      // The backward interval (prev_spike → cur_spike) partially
      // overlaps with BOTH the previous token's tail AND the current
      // token's onset delay. Neither interval alone captures a token's
      // full acoustic duration:
      //
      //  - Short Madds (2 Harakat): backward interval is larger because
      //    it captures the onset delay before the CTC spike fired.
      //  - Long Madds (4-6 Harakat): forward interval is larger because
      //    the vowel is held long after the spike until the next sound.
      //
      // Using max(backward, forward) per token provides a robust
      // estimate: whichever interval captured more of the token's
      // actual acoustic time wins.

      // 1. Retroactively update PREVIOUS token with its forward interval.
      //    The previous token's duration becomes max(backward, forward).
      if (fIdx > 0) {
        final int prevIdx = fIdx - 1;
        final double prevSpike = _filteredSpikeTimes[prevIdx];

        // If a blank (silence) occurred between spikes, the previous
        // token's voicing ended at the blank, not at the current spike.
        double prevEnd = curSpike;
        if (lastBlankBefore > prevSpike && lastBlankBefore < curSpike) {
          prevEnd = lastBlankBefore;
        }

        final double forwardInterval =
            min(maxTokenDuration, max(0.04, prevEnd - prevSpike));

        // max(backward already stored, forward just computed)
        _tokenDurations[prevIdx] =
            max(_tokenDurations[prevIdx], forwardInterval);
      }

      // 2. Current token: backward interval as initial estimate.
      //    Will be max'd with its forward interval when the next
      //    token arrives (step 1 above on the next iteration).
      double prevSpikeTime = (fIdx == 0)
          ? max(0.0, curSpike - 0.15)
          : _filteredSpikeTimes[fIdx - 1];

      if (lastBlankBefore > prevSpikeTime) {
        prevSpikeTime = lastBlankBefore;
      }

      final double backwardInterval =
          min(maxTokenDuration, max(0.04, curSpike - prevSpikeTime));
      _tokenDurations.add(backwardInterval);
    }

    return ProcessedAudioStream(
      tokens: _filteredTokens,
      durations: _tokenDurations,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI HIGHLIGHTING CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════════

/// Bridges speech recognition engine output to per-word visual highlighting in the UI.
class HighlightingController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final VoidCallback? onAyahChanged;
  bool isTajweed;
  TrackerConfig config;

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;
  final ValueNotifier<int?> activeAyah = ValueNotifier(null);

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  // Per-Surah, Per-Ayah Word Status Bookkeeping. Kept in a separate,
  // surah-keyed store so a mid-session retarget (a boundary-crossing verse
  // group, a continuous reading view, …) can keep the surah it's leaving
  // fully highlighted — see [setTargetSurah]'s preserveOtherSurahStates.
  final SurahHighlightStore _highlights = SurahHighlightStore();

  // Debug State
  final ValueNotifier<String> debugRecognizedText = ValueNotifier('');
  final ValueNotifier<int> globalRevision = ValueNotifier(0);

  // Isolate Pipeline
  final PhonemeAlignmentIsolate _alignmentIsolate = PhonemeAlignmentIsolate();
  bool _isolateStarted = false;

  // ASR State
  late final AsrTokenProcessor _tokenProcessor;

  StreamSubscription? _engineSub;
  StreamSubscription<WordMatchedEvent>? _wordSub;

  int _lastResetTime = 0;
  String _lastProcessedText = '';
  bool _expectingNewSegment = false;
  int? _pendingClearAyah;

  List<ContinuousQuranWord> _currentSurahWords = [];
  List<int> _currentSurahBoundaries = [];

  HighlightingController({
    required this.repository,
    required SherpaEngine engine,
    this.onAyahChanged,
    bool isTajweed = true,
    this.config = const TrackerConfig(),
  })  : _engine = engine,
        isTajweed = repository.isTajweedSupported && isTajweed {
    _tokenProcessor = AsrTokenProcessor(config: config);
    _initIsolate();
    _engineSub = _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  /// Dynamically updates the recitation tracker difficulty or timing at runtime.
  void updateConfig(TrackerConfig newConfig) {
    config = newConfig;
    _tokenProcessor.config = newConfig;
    if (_isolateStarted) {
      _alignmentIsolate.updateConfig(newConfig);
    }
  }

  void setTajweedMode(bool active) {
    final effective = repository.isTajweedSupported && active;
    if (isTajweed == effective) return;
    isTajweed = effective;
    if (_isolateStarted) {
      _alignmentIsolate.setTajweedMode(effective);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _engineSub?.cancel();
    _wordSub?.cancel();
    _alignmentIsolate.stop();
    super.dispose();
  }

  Future<void> _initIsolate() async {
    await _alignmentIsolate.start();
    _isolateStarted = true;

    _wordSub = _alignmentIsolate.wordStream.listen(_onIsolateWordMatched);

    if (_targetSurah != 0) {
      _setSurahReference(forceClear: true, startGlobalWord: 0);
    }
  }

  void _setSurahReference({
    bool forceClear = false,
    int startGlobalWord = 0,
  }) {
    if (_targetSurah == 0 || !_isolateStarted) return;
    _currentSurahWords = repository.getSurahWords(_targetSurah);
    if (_currentSurahWords.isEmpty) return;

    final List<String> phonemeWords =
        _currentSurahWords.map((w) => w.phoneme).toList();
    final List<List<WordTajweedRule>> wordRules =
        _currentSurahWords.map((w) => w.rules).toList();
    _currentSurahBoundaries = _calculateBoundaries(phonemeWords);
    final String fullPhonemes = phonemeWords.join('');

    _alignmentIsolate.setSurahReference(
      fullPhonemes,
      _currentSurahBoundaries,
      isTajweed: isTajweed,
      forceClear: forceClear,
      startGlobalWord: startGlobalWord,
      surahNumber: _targetSurah,
      wordRules: wordRules,
    );
  }

  void _onIsolateWordMatched(WordMatchedEvent event) {
    final int globalWordId = event.wordId;
    final bool isRed = event.isRed;
    final String cleanAsr = event.cleanAsr;

    if (globalWordId < 0 || globalWordId >= _currentSurahWords.length) return;
    final word = _currentSurahWords[globalWordId];
    final ayahNum = word.ayah;
    final wordIdInAyah = word.wordInAyah;
    final surah = _targetSurah;

    if (_highlights.isUnspoken(surah, ayahNum, wordIdInAyah)) {
      if (isRed) {
        _highlights.markRed(surah, ayahNum, wordIdInAyah);
      } else if (event.isNeutral) {
        _highlights.markNeutral(surah, ayahNum, wordIdInAyah);
      } else {
        _highlights.markGreen(surah, ayahNum, wordIdInAyah);
      }

      if (activeAyah.value != ayahNum) {
        if (activeAyah.value != null && ayahNum > activeAyah.value!) {
          for (int a = activeAyah.value!; a < ayahNum; a++) {
            _highlights.markAyahCompleted(surah, a);
          }
        }
        activeAyah.value = ayahNum;
        final v = repository.getVerse(_targetSurah, ayahNum);
        if (v != null) {
          _currentMatch = VerseMatch(verse: v, score: 1.0);
          onAyahChanged?.call();
        }
      }

      if (isTajweed && cleanAsr.isNotEmpty && event.tajweedErrors != null) {
        final List<ReciterError> wordErrors = event.tajweedErrors!
            .map((e) => ReciterError.fromMap(Map<String, dynamic>.from(e)))
            .toList();

        if (wordErrors.isNotEmpty) {
          _highlights.markGreenWordAsYellow(
            surah,
            ayahNum,
            wordIdInAyah,
            wordErrors,
          );
        }
      }

      final verse = repository.getVerse(_targetSurah, ayahNum);
      if (verse != null && wordIdInAyah == verse.phonemeWords.length - 1) {
        _highlights.markAyahCompleted(surah, ayahNum);

        final nextVerse = repository.getNextVerse(_targetSurah, ayahNum);
        if (nextVerse != null) {
          activeAyah.value = nextVerse.ayah;
          _currentMatch = VerseMatch(verse: nextVerse, score: 1.0);
          onAyahChanged?.call();
        }
      }

      if (globalWordId == _currentSurahWords.length - 1) {
        finalize();
      }

      notifyListeners();
    }
  }

  // Public Accessors
  HighlightingController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;

  /// Completed ayahs for the currently targeted surah.
  Set<int> get completedAyahs => _highlights.completedAyahsFor(_targetSurah);

  /// Completed ayahs for any tracked surah — e.g. the surah just left
  /// behind by a [setTargetSurah] retarget with `preserveOtherSurahStates`.
  Set<int> completedAyahsFor(int surah) => _highlights.completedAyahsFor(surah);

  // Word Color Queries
  int _mapToPhonemeIndex(int ayah, int uthmaniIndex, {int? surah}) {
    final s = surah ?? _targetSurah;
    if (s == 0) return uthmaniIndex;
    final verse = repository.getVerse(s, ayah);
    if (verse == null ||
        uthmaniIndex < 0 ||
        uthmaniIndex >= verse.wordMap.length) {
      return uthmaniIndex;
    }
    return verse.wordMap[uthmaniIndex];
  }

  /// [surah] defaults to the currently targeted surah; pass it explicitly to
  /// read another tracked surah's highlights (e.g. after a
  /// `preserveOtherSurahStates` retarget moved tracking past it).
  bool isWordGreen(int ayah, int wordIndex, {int? surah}) {
    if (isWordRed(ayah, wordIndex, surah: surah)) return false;
    final s = surah ?? _targetSurah;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex, surah: s);
    return _highlights.isGreen(s, ayah, pIdx);
  }

  bool isWordRed(int ayah, int wordIndex, {int? surah}) {
    final s = surah ?? _targetSurah;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex, surah: s);
    return _highlights.isRed(s, ayah, pIdx);
  }

  bool isWordYellow(int ayah, int wordIndex, {int? surah}) {
    final s = surah ?? _targetSurah;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex, surah: s);
    return _highlights.isYellow(s, ayah, pIdx);
  }

  bool isWordNeutral(int ayah, int wordIndex, {int? surah}) {
    final s = surah ?? _targetSurah;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex, surah: s);
    return _highlights.isNeutral(s, ayah, pIdx);
  }

  List<ReciterError>? getWordErrors(int ayah, int wordIndex, {int? surah}) {
    final s = surah ?? _targetSurah;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex, surah: s);
    return _highlights.errorsFor(s, ayah, pIdx);
  }

  // Surah / Ayah Management
  /// Sets the actively tracked surah, reloading its phoneme reference.
  ///
  /// By default every other surah's tracked highlights are wiped too (the
  /// pre-existing behavior — appropriate for starting a fresh, unrelated
  /// session). Pass [preserveOtherSurahStates]: true when retargeting
  /// mid-session across a surah boundary (a verse group spanning two
  /// surahs, a continuous reading view, …) so the surah being left keeps
  /// its already-committed highlights — read them back afterwards with
  /// [isWordGreen] etc. and an explicit `surah:` argument, or
  /// [completedAyahsFor].
  Future<void> setTargetSurah(
    int surah, {
    bool preserveOtherSurahStates = false,
  }) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    _highlights.clearForRetarget(
      surah,
      preserveOtherSurahs: preserveOtherSurahStates,
    );
    globalRevision.value++;
    notifyListeners();
    await repository.loadSurahAsync(surah);
    _currentSurahWords = repository.getSurahWords(surah);
    reset();
  }

  /// Wipes every tracked surah's highlights.
  void clearHighlights() {
    _highlights.clearAll();
    globalRevision.value++;
    notifyListeners();
  }

  /// Wipes only [surah]'s highlights, leaving every other tracked surah
  /// untouched.
  void clearHighlightsForSurah(int surah) {
    _highlights.clearSurah(surah);
    globalRevision.value++;
    notifyListeners();
  }

  void clearHighlightsFromAyah(int startAyah) {
    _highlights.clearSurahFromAyah(_targetSurah, startAyah);
    globalRevision.value++;
    notifyListeners();
  }

  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      activeAyah.value = ayah;

      final int startWord =
          repository.getAyahStartGlobalIndex(surah, ayah);

      if (_isolateStarted) {
        _alignmentIsolate.jumpToWord(startWord);
      }

      _engine.resetBuffer();
      _lastProcessedText = '';
      _lastResetTime = DateTime.now().millisecondsSinceEpoch;
      _pendingClearAyah = ayah;
      onAyahChanged?.call();
      notifyListeners();
    }
  }

  List<int> _calculateBoundaries(List<String> words) {
    final List<int> bounds = [];
    int cursor = 0;
    for (final w in words) {
      bounds.add(cursor);
      cursor += w.replaceAll(' ', '').length;
    }
    bounds.add(cursor);
    return bounds;
  }

  void feed(Float32List audioChunk, {bool isFinal = false}) {
    if (_state == TrackerState.discovery) return;
    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  // Lifecycle
  void reset() {
    _state = TrackerState.tracking;
    _currentSurahWords = repository.getSurahWords(_targetSurah);
    if (_currentMatch == null) {
      final verse = repository.getVerse(_targetSurah, 1);
      _currentMatch =
          verse != null ? VerseMatch(verse: verse, score: 1.0) : null;
    }
    activeAyah.value = _currentMatch?.verse.ayah ?? 1;
    if (_isolateStarted) {
      _setSurahReference(forceClear: true, startGlobalWord: 0);
    }
    _engine.resetBuffer();
    _tokenProcessor.reset();
    _lastProcessedText = '';
    _expectingNewSegment = false;
    _lastResetTime = DateTime.now().millisecondsSinceEpoch;
    onAyahChanged?.call();
    notifyListeners();
  }

  void finalize() {
    _state = TrackerState.discovery;
    _engine.resetBuffer();
    _tokenProcessor.reset();
    notifyListeners();
  }

  void resumeTracking() {
    _state = TrackerState.tracking;
    int resumeAyah = 1;
    if (_pendingClearAyah != null) {
      resumeAyah = _pendingClearAyah!;
      clearHighlightsFromAyah(_pendingClearAyah!);
      _pendingClearAyah = null;
    } else if (activeAyah.value != null) {
      resumeAyah = activeAyah.value!;
      clearHighlightsFromAyah(activeAyah.value!);
    }

    final int startGlobalWord =
        repository.getAyahStartGlobalIndex(_targetSurah, resumeAyah);
    if (_isolateStarted) {
      _alignmentIsolate.jumpToWord(startGlobalWord);
    }

    _engine.resetBuffer();
    _tokenProcessor.reset();
    _lastProcessedText = '';
    _expectingNewSegment = true;
    _lastResetTime = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void startRecordingSession() {
    resumeTracking();
  }

  void unloadEngine() {
    _state = TrackerState.discovery;
    _engine.destroy();
    _alignmentIsolate.stop();
    notifyListeners();
  }

  Future<void> reloadEngine() async {
    await _engine.initialize();
    notifyListeners();
  }

  void forceActiveAyah(QuranVerse verse) {
    _state = TrackerState.tracking;
    _currentMatch = VerseMatch(verse: verse, score: 1.0);
    activeAyah.value = verse.ayah;
    _lastProcessedText = '';
    notifyListeners();
  }

  void flushAndResetForNextAyah() {}

  // ASR Ingestion
  void _onResult(TranscriptionResult result) {
    if (_state == TrackerState.discovery) return;
    if (_currentMatch == null) return;

    if (result.startTime < _lastResetTime ||
        result.streamEpoch != _engine.currentStreamEpoch) {
      return;
    }

    final ProcessedAudioStream stream = _tokenProcessor.process(result);
    final String asrText = stream.tokens.join('');
    debugRecognizedText.value = asrText;

    if (stream.tokens.length > 8000) {
      _engine.resetBuffer();
      _tokenProcessor.reset();
      _lastProcessedText = '';
      return;
    }

    if (stream.tokens.isEmpty) {
      _lastProcessedText = '';
      return;
    }

    bool isNewSegment = false;
    if (_expectingNewSegment) {
      isNewSegment = true;
      _expectingNewSegment = false;
    }

    if (stream.tokens.isNotEmpty && _isolateStarted) {
      if (!isNewSegment && asrText == _lastProcessedText) {
        return;
      }
      _lastProcessedText = asrText;

      final List<double> charDurations = [];
      for (int i = 0; i < stream.tokens.length; i++) {
        final tok = stream.tokens[i];
        final dur = stream.durations[i] / max(1, tok.length);
        for (int c = 0; c < tok.length; c++) {
          charDurations.add(dur);
        }
      }

      _alignmentIsolate.syncStream(
        asrText,
        charDurations,
        isNewSegment,
        _currentMatch?.verse.ayah ?? 0,
      );
    }

    _lastProcessedText = asrText;
  }
}
