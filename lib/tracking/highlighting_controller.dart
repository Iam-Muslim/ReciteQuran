// lib/tracking/highlighting_controller.dart
//
// HighlightingController — bridges ASR engine output to per-word highlighting.
//
// Architecture:
//   SherpaEngine → transcriptionStream → HighlightingController → UI
//
// Matching system:
//   Uses PhoneticWordTracker (ported from quran-transcript/src/quran_transcript/
//   tasmeea.py + utils.py) to match the accumulating ASR phonetic stream
//   against the expected Uthmani words of the current ayah word-by-word.
//
//   The ASR model outputs phonetic Arabic (e.g. "بِسمِللَااهِ") that accumulates
//   over time. PhoneticWordTracker normalizes both sides (QuranNormalizer,
//   ported from normalize_aya()) and uses Levenshtein distance to commit
//   words as correct/wrong one at a time.
//
// Word-order constraint (Tarteel-style):
//   - Words must match IN ORDER. A wrong/skipped word turns red immediately.
//   - Advancing to the next ayah is automatic when all words are resolved.
//   - The user selects the start surah+ayah; tracker proceeds sequentially.

import 'package:flutter/foundation.dart';
import '../state/app_state.dart';
import '../engine/sherpa_engine.dart';
import '../data/quran_data.dart';
import 'phonetic_word_tracker.dart';
import 'matchers/error_explainer.dart';
import 'highlighting_mode.dart';

// ── State machine ────────────────────────────────────────────────────────────

/// The three states the live recitation tracker can be in.
///
/// [discovery] — engine is idle / stopped.
/// [tracking]  — actively listening and matching words.
enum TrackerState { discovery, tracking }

// ── Verse match result ───────────────────────────────────────────────────────

/// A matched verse together with its confidence score (0.0 – 1.0).
class VerseMatch {
  /// The matched [QuranVerse].
  final QuranVerse verse;

  /// Match score — always 1.0 for manual/sequential selection.
  final double score;

  VerseMatch({required this.verse, required this.score});

  /// Subscript access for legacy widget code.
  dynamic operator [](String key) {
    if (key == 'surah') return verse.surah;
    if (key == 'ayah') return verse.ayah;
    if (key == 'score') return score;
    if (key == 'text' || key == 'text_uthmani') return verse.textUthmani;
    return null;
  }
}

// ── Verse span match result ──────────────────────────────────────────────────

/// A matched span of verses (kept for voice-search compat).
class VerseSpanMatch {
  final int surah;
  final int startAyah;
  final int endAyah;
  final String textClean;
  final String textUthmani;
  final double score;

  VerseSpanMatch({
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.textClean,
    required this.textUthmani,
    required this.score,
  });
}

// ── Main controller ──────────────────────────────────────────────────────────

class HighlightingController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final VoidCallback? onAyahChanged;

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;
  final ValueNotifier<int?> activeAyah = ValueNotifier(null);

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  // ── Per-ayah word status maps ─────────────────────────────────────────────
  // Keyed by ayah number (1-based). Sets contain 0-based word indices.
  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Map<int, Set<int>> _yellowWordsByVerse = {};
  final Set<int> _completedAyahs = {};

  // ── Debug ─────────────────────────────────────────────────────────────────
  final ValueNotifier<String> debugRecognizedText = ValueNotifier('');

  // ── Per-ayah word tracker (quran-transcript PhoneticWordTracker) ──────────
  PhoneticWordTracker? _wordTracker;

  bool isTajweedEnabled = false;
  HighlightingMode mode = HighlightingMode.lookahead;

  bool _ignoreUntilBufferReset = false;
  int? _pendingClearAyah;

  HighlightingController({
    required this.repository,
    required SherpaEngine engine,
    this.onAyahChanged,
  }) : _engine = engine {
    _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  HighlightingController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;
  Set<int> get completedAyahs => _completedAyahs;
  bool get softWarningActive => false;

  // ── Word color queries ────────────────────────────────────────────────────

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
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _greenWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordRed(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _redWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  /// Yellow not used in base mode — kept for Tajweed mode extension.
  bool isWordYellow(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _yellowWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  /// Get errors for a word if any
  List<ReciterError>? getWordErrors(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    if (_wordTracker == null || activeAyah.value != ayah) return null;
    if (pIdx < 0 || pIdx >= _wordTracker!.errors.length) return null;
    return _wordTracker!.errors[pIdx];
  }

  // ── Surah / ayah management ───────────────────────────────────────────────

  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    _wordTracker = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    reset();
  }

  void clearHighlights() {
    _completedAyahs.clear();
    _greenWordsByVerse.clear();
    _redWordsByVerse.clear();
    notifyListeners();
  }

  void clearHighlightsFromAyah(int startAyah) {
    _completedAyahs.removeWhere((ayah) => ayah >= startAyah);
    _greenWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _redWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _yellowWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    notifyListeners();
  }

  /// Jump to a specific ayah manually (user taps a verse row).
  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      activeAyah.value = ayah;
      _ignoreUntilBufferReset = true;
      _resetWordTracker(verse);
      _engine.resetBuffer();
      _pendingClearAyah = ayah;
      onAyahChanged?.call();
      notifyListeners();
    }
  }

  // ── Audio pipeline ────────────────────────────────────────────────────────

  void feed(Uint8List audioChunk, {bool isFinal = false}) {
    if (_state == TrackerState.discovery) return;
    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void reset() {
    _state = TrackerState.tracking;
    if (_currentMatch == null) {
      final verse = repository.getVerse(_targetSurah, 1);
      _currentMatch = verse != null
          ? VerseMatch(verse: verse, score: 1.0)
          : null;
    }
    activeAyah.value = _currentMatch?.verse.ayah;
    if (_currentMatch != null) {
      _resetWordTracker(_currentMatch!.verse);
    }
    _engine.resetBuffer();
    onAyahChanged?.call();
    notifyListeners();
  }

  void finalize() {
    _state = TrackerState.discovery;
    _engine.resetBuffer();
    notifyListeners();
  }

  void resumeTracking() {
    _state = TrackerState.tracking;
    if (_pendingClearAyah != null) {
      clearHighlightsFromAyah(_pendingClearAyah!);
      _pendingClearAyah = null;
    }
    notifyListeners();
  }

  void startRecordingSession() {
    resumeTracking();
  }

  void unloadEngine() {
    _state = TrackerState.discovery;
    _engine.destroy();
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
    _ignoreUntilBufferReset = true;
    _resetWordTracker(verse);
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Create/reset the PhoneticWordTracker for [verse].
  void _resetWordTracker(QuranVerse verse) {
    _wordTracker = PhoneticWordTracker(
      expectedPhonemes: verse.phonemeWords,
      isTajweedEnabled: isTajweedEnabled,
      strictTracking: mode == HighlightingMode.strict,
      matchThreshold: 0.5, // quran-transcript default acceptance_ratio
      lookAheadWords: 4,
      isLookaheadEnabled: AppState.instance.isLookaheadEnabled,
    );
  }

  /// Called on every ASR emission from SherpaEngine.
  ///
  /// The [result.text] is the ACCUMULATING phonetic stream — e.g.:
  ///   "بِسمِللَ" → "بِسمِللَااهِ" → "بِسمِللَااهِررَحمَاا"
  void _onResult(TranscriptionResult result) {
    if (_state == TrackerState.discovery) return;
    if (_currentMatch == null || _wordTracker == null) return;

    final String asrText = result.text.trim();
    debugRecognizedText.value = asrText;

    if (_ignoreUntilBufferReset) {
      // If the engine hasn't processed the resetBuffer() call yet, ignore old long streams
      if (asrText.length < 5 || asrText.isEmpty) {
        _ignoreUntilBufferReset = false;
      } else {
        return;
      }
    }

    if (asrText.isEmpty) return;

    // Safety: prevent unbounded accumulation crashing the Levenshtein calc
    if (asrText.length > 400) {
      _engine.resetBuffer();
      return;
    }

    final tracker = _wordTracker!;
    final targetAyah = _currentMatch!.verse;

    // Feed the accumulated stream to the word tracker
    final changed = tracker.feed(asrText, isEndpoint: result.isFinal);

    if (!changed) return;

    // Sync tracker statuses → highlight maps
    bool anyUpdate = false;
    for (int i = 0; i < tracker.statuses.length; i++) {
      final status = tracker.statuses[i];
      final ayahNum = targetAyah.ayah;

      switch (status) {
        case WordMatchStatus.correct:
          if (!(_greenWordsByVerse[ayahNum]?.contains(i) ?? false)) {
            (_greenWordsByVerse[ayahNum] ??= {}).add(i);
            _redWordsByVerse[ayahNum]?.remove(i);
            _yellowWordsByVerse[ayahNum]?.remove(i);
            anyUpdate = true;
          }
        case WordMatchStatus.wrong:
        case WordMatchStatus.skipped:
          if (!(_redWordsByVerse[ayahNum]?.contains(i) ?? false)) {
            (_redWordsByVerse[ayahNum] ??= {}).add(i);
            _greenWordsByVerse[ayahNum]?.remove(i);
            _yellowWordsByVerse[ayahNum]?.remove(i);
            anyUpdate = true;
          }
        case WordMatchStatus.pending:
          break;
      }
    }

    if (!anyUpdate && !tracker.isComplete) return;

    // Check if the ayah is fully resolved (all words matched/wrong)
    if (tracker.isComplete) {
      if (isTajweedEnabled) {
        // 1. Post-Ayah Global Tajweed Checking
        print('[Tajweed] Ayah complete. Running global explainAyahError.');
        final errorsByWord = ErrorExplainer.explainAyahError(
          targetAyah.textPhoneme,
          tracker.accumulatedNormText,
          targetAyah.phonemeWords,
        );

        // 2. Flip green words to yellow if they have errors
        errorsByWord.forEach((wIdx, errors) {
          if (errors.isNotEmpty) {
            tracker.errors[wIdx] = errors;
            if (_greenWordsByVerse[targetAyah.ayah]?.contains(wIdx) ?? false) {
              (_yellowWordsByVerse[targetAyah.ayah] ??= {}).add(wIdx);
              _greenWordsByVerse[targetAyah.ayah]?.remove(wIdx);
              print('[Tajweed] Word $wIdx turned YELLOW due to errors: $errors');
            }
          }
        });
      }

      _completedAyahs.add(targetAyah.ayah);

      // Advance to next ayah
      final nextVerse = repository.getNextVerse(_targetSurah, targetAyah.ayah);
      if (nextVerse != null) {
        forceActiveAyah(nextVerse);
        // Reset ASR buffer so the next ayah starts fresh
        _engine.resetBuffer();
      } else {
        // End of surah
        finalize();
      }
    } else {
      notifyListeners();
    }
  }
}
