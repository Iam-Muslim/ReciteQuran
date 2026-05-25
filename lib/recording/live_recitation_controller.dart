library recording.live_recitation_controller;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../core/types.dart';
import '../core/app_state.dart';
import '../engine/sherpa_engine.dart';
import '../engine/segmentation_service.dart';
import '../data/models/quran_data.dart';
import '../data/models/quran_repository.dart';
import '../utils/normalizer.dart';

/// The `LiveRecitationController` handles real-time audio recitation matching.
/// It acts as the bridge between the Sherpa ASR engine and the Quran UI,
/// processing incoming audio chunks, tracking word-by-word progress,
/// and emitting state changes to update the interface.
class LiveRecitationController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final SegmentationService _segmenter = SegmentationService();
  final VoidCallback? onAyahChanged;

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Set<int> _completedAyahs = {};

  final ValueNotifier<String> debugRecognizedText = ValueNotifier("");

  int _lastCommittedWordIdx = -1;

  // Grace flag: suppresses red-marking on the very first match after an
  // ayah transition, preventing false reds when reciting fast (murattal).
  bool _freshAyah = false;

  // Cache for normalized expected words (avoids re-computing in hot loop)
  List<String>? _cachedExpectedNorm;
  int? _cachedVerseAyah;

  // Tracks the previous transcript to detect which words are NEW vs residual.
  // Without this, the sliding window re-sends old audio, and the CTC re-outputs
  // old words that can falsely match future expected words.
  List<String> _prevSpokenWords = [];

  LiveRecitationController({
    required this.repository,
    required SherpaEngine engine,
    this.onAyahChanged,
  }) : _engine = engine {
    _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  // ── Public API Getters ─────────────────────────────────────────────────────

  LiveRecitationController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;
  Set<int> get completedAyahs => _completedAyahs;
  bool get softWarningActive => false;

  bool isWordGreen(int ayah, int wordIndex) {
    if (isWordRed(ayah, wordIndex)) return false;
    if (_completedAyahs.contains(ayah)) return true;
    return _greenWordsByVerse[ayah]?.contains(wordIndex) ?? false;
  }

  bool isWordRed(int ayah, int wordIndex) =>
      _redWordsByVerse[ayah]?.contains(wordIndex) ?? false;

  int get currentWordIndex => math.max(0, _lastCommittedWordIdx + 1);

  // ── Session Management API ─────────────────────────────────────────────────

  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
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
    notifyListeners();
  }

  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      _clearTrackingState();
      _engine.resetBuffer();
      _pendingClearAyah = ayah;
      onAyahChanged?.call();
      notifyListeners();
    }
  }

  /// Directly streams pure delta audio chunks without rolling memory overhead
  void feed(Uint8List audioChunk, {bool isFinal = false}) {
    if (_state != TrackerState.tracking) return;
    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  void reset() {
    _state = TrackerState.tracking;
    if (_currentMatch == null) {
      final verse = repository.getVerse(_targetSurah, 1);
      _currentMatch = verse != null
          ? VerseMatch(verse: verse, score: 1.0)
          : null;
    }
    _clearTrackingState();
    _engine.resetBuffer();
    onAyahChanged?.call();
    notifyListeners();
  }

  void finalize() {
    _state = TrackerState.discovery;

    // Do NOT call reset() here, as it forces the state back to 'tracking'!
    // We just safely clear the engine buffer and notify the UI to stop.
    _engine.resetBuffer();
    notifyListeners();
  }

  int? _pendingClearAyah;

  void resumeTracking() {
    _state = TrackerState.tracking;
    if (_pendingClearAyah != null) {
      clearHighlightsFromAyah(_pendingClearAyah!);
      _pendingClearAyah = null;
    }
    notifyListeners();
  }

  void _clearTrackingState({bool preservePrevWords = false}) {
    _lastCommittedWordIdx = -1;
    _cachedExpectedNorm = null;
    _cachedVerseAyah = null;
    if (!preservePrevWords) {
      _prevSpokenWords = [];
    }
  }

  void _onResult(TranscriptionResult result) {
    if (_state != TrackerState.tracking || _currentMatch == null) return;

    debugRecognizedText.value = result.text.trim();

    if (result.text.trim().isEmpty) return;

    _updateHighlighting(result);
  }

  // ── OPTIMIZED STRING PROCESSING ────────────────────────────────────────────

  String _normalizeArabicText(String text) {
    // 1. Process Muqatta'at first using the optimized Normalizer
    String handledText = Normalizer.processMuqattaat(text);

    // 2. Use your highly optimized Normalizer to strip diacritics & alefs
    return Normalizer.normalizeArabic(handledText);
  }

  String _preprocessASRText(String text) {
    // Only process Muqatta'at for the raw ASR words before segmenting
    return Normalizer.processMuqattaat(text);
  }

  // ───────────────────────────────────────────────────────────────────────────

  void _updateHighlighting(TranscriptionResult result) {
    String processedText = _preprocessASRText(result.text);
    final List<String> spokenWords = _segmenter.parseWords(processedText);

    final currentVerse = _currentMatch!.verse;
    final expectedWords = currentVerse.cleanWords;

    // Pre-compute normalized expected words (cached per verse)
    if (_cachedVerseAyah != currentVerse.ayah || _cachedExpectedNorm == null) {
      _cachedExpectedNorm = expectedWords
          .map((w) => _normalizeArabicText(w))
          .toList();
      _cachedVerseAyah = currentVerse.ayah;
    }

    // ── Deduplication: skip words that are residual from old audio ──────────
    // The sliding window re-transcribes overlapping audio, producing the same
    // words as the previous cycle. Without dedup, those old words can falsely
    // match future expected words (e.g. repeated words across ayahs).
    //
    // Find the longest common prefix between this and the previous transcript.
    // Only process words AFTER the prefix — those are genuinely new.
    final int prevLen = _prevSpokenWords.length;
    int commonPrefix = 0;
    while (commonPrefix < prevLen &&
        commonPrefix < spokenWords.length &&
        spokenWords[commonPrefix] == _prevSpokenWords[commonPrefix]) {
      commonPrefix++;
    }
    // Save reference before overwriting (for stale word detection in Pass 2)
    final List<String> prevCycleWords = _prevSpokenWords;
    _prevSpokenWords = List<String>.from(spokenWords);

    // If the transcript is identical to the previous one, nothing new.
    if (commonPrefix >= spokenWords.length && commonPrefix >= prevLen) {
      return;
    }

    // Start from the first genuinely new/changed spoken word.
    // We allow re-checking one word before divergence in case the CTC
    // refined a partial word (e.g. "الل" → "الله").
    int spokenPtr = math.max(0, commonPrefix > 0 ? commonPrefix - 1 : 0);

    int maxLookahead = AppState.instance.lookahead;
    int targetIndex = math.max(0, _lastCommittedWordIdx + 1);
    bool anyProgress = false;

    // For lookahead > 1: build a set of words from the previous cycle's
    // transcript. Words that already existed there are likely residual from
    // the sliding window (stale audio re-decoded by CTC). They must NOT
    // trigger lookahead jumps, which would falsely skip/red-mark words.
    final Set<String>? staleWordsSet =
        (maxLookahead > 1 && prevCycleWords.isNotEmpty)
            ? prevCycleWords.toSet()
            : null;

    // Forward-only greedy alignment (reference: _align_position in server.py):
    // Scan NEW spoken words left-to-right and match each to the earliest
    // available expected word. _lastCommittedWordIdx is monotonic — it
    // only ever moves forward, preventing re-confirmation of old words.
    while (targetIndex < expectedWords.length &&
        spokenPtr < spokenWords.length) {
      int limit = math.min(targetIndex + maxLookahead, expectedWords.length);
      int foundAt = -1;
      int foundSpokenAt = -1;

      // ── Lookahead > 1 fix: two-pass matching ──────────────────────────
      // Pass 1: Try to match the current expected word ONLY (no jumping).
      //         This prevents the highlight from skipping ahead to a
      //         better-scoring lookahead word when reciting fast.
      // Pass 2: If pass 1 fails, expand search to lookahead positions.
      // When lookahead == 1, limit == targetIndex + 1, so both passes
      // collapse into the original single-pass behavior (no change).
      if (maxLookahead > 1) {
        // Pass 1: current expected word only
        for (int i = spokenPtr; i < spokenWords.length; i++) {
          final String spoken = spokenWords[i];
          if (spoken.isEmpty) continue;
          if (_calculateMatchScore(spoken, _cachedExpectedNorm![targetIndex]) >=
              0.70) {
            foundAt = targetIndex;
            foundSpokenAt = i;
            break;
          }
        }
        // Pass 2: try lookahead positions (skip targetIndex, already tried)
        if (foundAt == -1) {
          for (int i = spokenPtr; i < spokenWords.length; i++) {
            final String spoken = spokenWords[i];
            if (spoken.isEmpty) continue;
            // Skip stale words: if this word existed in the previous
            // cycle's transcript, it's residual from the sliding window
            // and must not trigger a lookahead jump.
            if (staleWordsSet!.contains(spoken)) continue;
            for (int j = targetIndex + 1; j < limit; j++) {
              if (_calculateMatchScore(spoken, _cachedExpectedNorm![j]) >=
                  0.85) {
                foundAt = j;
                foundSpokenAt = i;
                break;
              }
            }
            if (foundAt != -1) break;
          }
        }
      } else {
        // Original single-pass behavior for lookahead == 1
        for (int i = spokenPtr; i < spokenWords.length; i++) {
          final String spoken = spokenWords[i];
          if (spoken.isEmpty) continue;

          for (int j = targetIndex; j < limit; j++) {
            double threshold = (j == targetIndex) ? 0.70 : 0.85;
            if (_calculateMatchScore(spoken, _cachedExpectedNorm![j]) >=
                threshold) {
              foundAt = j;
              foundSpokenAt = i;
              break;
            }
          }
          if (foundAt != -1) break;
        }
      }

      if (foundAt == -1) break;

      // Mark skipped expected words as red (skip during grace period)
      if (!_freshAyah) {
        for (int i = targetIndex; i < foundAt; i++) {
          _redWordsByVerse[currentVerse.ayah] ??= {};
          _redWordsByVerse[currentVerse.ayah]!.add(i);
        }
      }

      // Mark matched word as green
      _greenWordsByVerse[currentVerse.ayah] ??= {};
      _greenWordsByVerse[currentVerse.ayah]!.add(foundAt);
      _redWordsByVerse[currentVerse.ayah]?.remove(foundAt);

      _lastCommittedWordIdx = foundAt;
      targetIndex = foundAt + 1;
      spokenPtr = foundSpokenAt + 1;
      anyProgress = true;
    }

    if (anyProgress) {
      _freshAyah = false; // Grace period over after first progress
      if (_lastCommittedWordIdx >= expectedWords.length - 1) {
        _advanceToNextAyah();
      }
      notifyListeners();
    }
  }

  double _calculateMatchScore(String raw1, String raw2) {
    if (raw1 == raw2) return 1.0;

    // ASR Tajweed Fix: Ignore "ال" differences due to Lam Shamsiyyah blending.
    String w1 = raw1.startsWith("ال") ? raw1.substring(2) : raw1;
    String w2 = raw2.startsWith("ال") ? raw2.substring(2) : raw2;

    int dist = _getLevenshteinDistance(w1, w2);
    int maxLen = math.max(w1.length, w2.length);

    if (maxLen == 0) return 1.0;

    final level = AppState.instance.mistakeLevel;

    if (level == MistakeLevel.hard) {
      return dist == 0 ? 1.0 : 0.0;
    }

    if (level == MistakeLevel.easy) {
      if (maxLen <= 3) return dist <= 1 ? 0.75 : 0.0;
      if (maxLen <= 5) return dist <= 2 ? 0.75 : 0.0;
      return dist <= 3 ? 0.75 : 0.0;
    }

    // Medium (Default)
    // Strict Match Gates: Prevents missing/wrong words from turning green
    if (maxLen <= 3) {
      return dist == 0
          ? 1.0
          : 0.0; // 1 to 3 letter words MUST be 100% exact. No typos allowed.
    }
    if (maxLen <= 5) {
      return dist <= 1 ? 0.75 : 0.0; // 4 to 5 letter words allow 1 typo.
    }

    // 6+ letter words allow 2 typos.
    return dist <= 2 ? 0.75 : 0.0;
  }

  int _getLevenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }

  void _advanceToNextAyah() {
    final QuranVerse current = _currentMatch!.verse;

    final QuranVerse? next = repository.getVerse(
      current.surah,
      current.ayah + 1,
    );

    // Always mark the current Ayah as completed, even if it's the last one
    _completedAyahs.add(current.ayah);

    if (next != null) {
      _currentMatch = VerseMatch(verse: next, score: 1.0);
      // Bug 3 fix: When lookahead > 1 and reciting fast, the sliding
      // window still contains audio from the previous ayah. If we clear
      // _prevSpokenWords, the dedup logic can't filter those residual
      // ASR words, causing them to falsely highlight in the new ayah.
      // Preserving _prevSpokenWords lets the common-prefix dedup catch
      // those stale words. For lookahead == 1 this is not needed because
      // the narrow window already prevents cross-ayah bleed.
      _freshAyah = true; // Suppress false reds on first match of new ayah
      final bool preserve = AppState.instance.lookahead > 1;
      _clearTrackingState(preservePrevWords: preserve);
      onAyahChanged?.call();
    } else {
      // End of Surah reached, shut down the tracker gracefully.
      _currentMatch = null;
      _state = TrackerState.discovery;
    }
    notifyListeners();
  }

  void forceActiveAyah(QuranVerse verse) {
    _state = TrackerState.tracking;
    _currentMatch = VerseMatch(verse: verse, score: 1.0);
    _clearTrackingState();
    notifyListeners();
  }
}
