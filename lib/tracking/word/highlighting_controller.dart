import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../data/quran_data.dart';
import '../../engine/sherpa_engine.dart';
import '../tajweed/error_explainer.dart';
import 'phoneme_alignment_isolate.dart';

export 'phoneme_alignment_isolate.dart';

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

  // Per-Ayah Word Status Maps
  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Map<int, Set<int>> _yellowWordsByVerse = {};
  final Map<int, Set<int>> _neutralWordsByVerse = {};
  final Map<int, Map<int, List<ReciterError>>> _errorsByVerse = {};
  final Set<int> _completedAyahs = {};

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
    this.isTajweed = true,
    this.config = const TrackerConfig(),
  }) : _engine = engine {
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
    if (isTajweed == active) return;
    isTajweed = active;
    if (_isolateStarted) {
      _alignmentIsolate.setTajweedMode(active);
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

    if (!(_greenWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) &&
        !(_redWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) &&
        !(_yellowWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) &&
        !(_neutralWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false)) {
      if (isRed) {
        (_redWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
      } else if (event.isNeutral) {
        (_neutralWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
      } else {
        (_greenWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
      }

      if (activeAyah.value != ayahNum) {
        if (activeAyah.value != null && ayahNum > activeAyah.value!) {
          for (int a = activeAyah.value!; a < ayahNum; a++) {
            _completedAyahs.add(a);
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
          if (_greenWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) {
            _greenWordsByVerse[ayahNum]?.remove(wordIdInAyah);
            (_yellowWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
            (_errorsByVerse[ayahNum] ??= {})[wordIdInAyah] = wordErrors;
          }
        }
      }

      final verse = repository.getVerse(_targetSurah, ayahNum);
      if (verse != null && wordIdInAyah == verse.phonemeWords.length - 1) {
        _completedAyahs.add(ayahNum);

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
  Set<int> get completedAyahs => _completedAyahs;

  // Word Color Queries
  int _mapToPhonemeIndex(int ayah, int uthmaniIndex) {
    if (_targetSurah == 0) return uthmaniIndex;
    final verse = repository.getVerse(_targetSurah, ayah);
    if (verse == null ||
        uthmaniIndex < 0 ||
        uthmaniIndex >= verse.wordMap.length) {
      return uthmaniIndex;
    }
    return verse.wordMap[uthmaniIndex];
  }

  bool isWordGreen(int ayah, int wordIndex) {
    if (isWordRed(ayah, wordIndex)) return false;
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _greenWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordRed(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _redWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordYellow(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _yellowWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordNeutral(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _neutralWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  List<ReciterError>? getWordErrors(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _errorsByVerse[ayah]?[pIdx];
  }

  // Surah / Ayah Management
  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    _currentSurahWords = repository.getSurahWords(surah);
    reset();
  }

  void clearHighlights() {
    _completedAyahs.clear();
    _greenWordsByVerse.clear();
    _redWordsByVerse.clear();
    _yellowWordsByVerse.clear();
    _neutralWordsByVerse.clear();
    _errorsByVerse.clear();
    globalRevision.value++;
    notifyListeners();
  }


  void clearHighlightsFromAyah(int startAyah) {
    _completedAyahs.removeWhere((ayah) => ayah >= startAyah);
    _greenWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _redWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _yellowWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _neutralWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _errorsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
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

    // The engine resets its decoder on an endpoint, so the NEXT result restarts
    // from an empty hypothesis instead of extending this one. The sequencer must
    // drop `asrCharAnchor` with it, otherwise the anchor still points past the
    // end of the restarted text and no word can ever match again.
    // `isNewSegment` for THIS result was already latched just above, so arming
    // the flag here only affects the next one. targetWordCursor is untouched, so
    // tracking resumes exactly where this utterance left off.
    // Armed before the unchanged-text early return below on purpose: an endpoint
    // fires during silence, when the text usually has NOT changed.
    if (result.isFinal) {
      _expectingNewSegment = true;
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
