import 'dart:math' as math;
import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/types.dart';
import '../core/app_state.dart';
import '../engine/sherpa_engine.dart';
import '../engine/segmentation_service.dart';
import '../data/models/quran_data.dart';
import '../data/models/quran_repository.dart';
import '../utils/normalizer.dart';
import '../utils/file_logger.dart';

// The `LiveRecitationController` handles real-time audio recitation matching.
// It acts as the bridge between the Sherpa ASR engine and the Quran UI,
// processing incoming audio chunks, tracking word-by-word progress,
// and emitting state changes to update the interface.
class LiveRecitationController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final SegmentationService _segmenter = SegmentationService();
  final VoidCallback? onAyahChanged;
  final void Function(HardwareTier newTier)? onDowngradeRequired;

  HardwareTier currentTier = HardwareTier.flagship;
  HardwareTier _baselineHardwareTier = HardwareTier.flagship;
  DateTime? _chunkStartTime;
  final List<int> _recentLatencies = [];
  static const int _maxLatenciesToTrack = 4;

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Set<int> _completedAyahs = {};

  final Queue<_PendingHighlight> _highlightQueue = Queue();
  Timer? _highlightTimer;

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
    this.onDowngradeRequired,
  }) : _engine = engine {
    _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  void _startHighlightTimer() {
    if (_highlightTimer?.isActive ?? false) return;

    _highlightTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (_highlightQueue.isEmpty) {
        timer.cancel();
        return;
      }

      int processCount = _highlightQueue.length > 5 ? 2 : 1;

      for (int i = 0; i < processCount; i++) {
        if (_highlightQueue.isEmpty) break;
        final event = _highlightQueue.removeFirst();

        if (event.isAyahCompletion) {
          _completedAyahs.add(event.ayah!);
          _greenWordsByVerse.remove(event.ayah!);
        } else if (event.isRed) {
          _redWordsByVerse[event.ayah!] ??= {};
          _redWordsByVerse[event.ayah!]!.add(event.wordIndex!);
        } else {
          _greenWordsByVerse[event.ayah!] ??= {};
          _greenWordsByVerse[event.ayah!]!.add(event.wordIndex!);
          _redWordsByVerse[event.ayah!]?.remove(event.wordIndex!);
        }
      }
      notifyListeners();
    });
  }

  void setBaselineTier(HardwareTier tier) {
    _baselineHardwareTier = tier;
    currentTier = tier;
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

  // currentWordIndex tracker removed to save CPU and simplify UI

  // ── Session Management API ─────────────────────────────────────────────────

  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    reset();
  }

  void clearHighlights() {
    _highlightQueue.clear();
    _highlightTimer?.cancel();
    _completedAyahs.clear();
    _greenWordsByVerse.clear();
    _redWordsByVerse.clear();
    notifyListeners();
  }

  void clearHighlightsFromAyah(int startAyah) {
    _highlightQueue.removeWhere((e) => e.ayah != null && e.ayah! >= startAyah);
    if (_highlightQueue.isEmpty) _highlightTimer?.cancel();
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

    if (!isFinal) {
      _chunkStartTime = DateTime.now();
    }

    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  void reset() {
    _state = TrackerState.tracking;
    currentTier = _baselineHardwareTier;
    _recentLatencies.clear();

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

  void unloadEngine() {
    _state = TrackerState.discovery;
    _engine.destroy();
    notifyListeners();
  }

  Future<void> reloadEngine() async {
    await _engine.initialize();
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

    if (_chunkStartTime != null) {
      final int processingTimeMs = DateTime.now()
          .difference(_chunkStartTime!)
          .inMilliseconds;
      _chunkStartTime = null;

      _recentLatencies.add(processingTimeMs);
      if (_recentLatencies.length > _maxLatenciesToTrack) {
        _recentLatencies.removeAt(0);
      }

      if (_recentLatencies.length == _maxLatenciesToTrack) {
        double avgLatency =
            _recentLatencies.fold(0, (a, b) => a + b) / _maxLatenciesToTrack;

        // One-way thermal latch
        if (currentTier == HardwareTier.flagship && avgLatency > 200) {
          currentTier = HardwareTier.standard;
          _recentLatencies.clear();
          FileLogger.instance.log(
            '[THERMAL] Warning: Flagship throttling (${avgLatency.toStringAsFixed(1)}ms). Downgrading to Standard tier.',
          );
          onDowngradeRequired?.call(currentTier);
        } else if (currentTier == HardwareTier.standard && avgLatency > 400) {
          currentTier = HardwareTier.budget;
          _recentLatencies.clear();
          FileLogger.instance.log(
            '[THERMAL] Warning: Standard throttling (${avgLatency.toStringAsFixed(1)}ms). Downgrading to Budget tier.',
          );
          onDowngradeRequired?.call(currentTier);
        }
      }
    }

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

    // ── Deduplication via Overlap-Matching (Suffix-Prefix Alignment) ────────
    // Because we now use a strict 1.5s sliding window to achieve ultra-low
    // latency, the ASR drops the oldest audio. This means the start of the
    // transcript changes completely!
    // We cannot use simple commonPrefix anymore. We must find the longest
    // suffix of the PREVIOUS transcript that perfectly matches a prefix of
    // the NEW transcript.
    int overlap = 0;
    int maxK = math.min(_prevSpokenWords.length, spokenWords.length);
    for (int k = maxK; k > 0; k--) {
      bool match = true;
      int prevStart = _prevSpokenWords.length - k;
      for (int i = 0; i < k; i++) {
        if (_prevSpokenWords[prevStart + i] != spokenWords[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        overlap = k;
        break;
      }
    }

    // Save reference before overwriting (for stale word detection in Pass 2)
    final List<String> prevCycleWords = _prevSpokenWords;
    _prevSpokenWords = List<String>.from(spokenWords);

    FileLogger.instance.log(
      '[MATCH] 🔄 Overlap: $overlap | Prev: $prevCycleWords | New: $spokenWords',
    );
    if (overlap == 0 && prevCycleWords.isNotEmpty && spokenWords.isNotEmpty) {
      FileLogger.instance.log(
        '[MATCH] 🚨 CONTINUITY BROKEN - Overlap dropped to 0. ASR dropped prefix!',
      );
    }

    // If the transcript is identical to the previous one, nothing new.
    if (overlap >= spokenWords.length && overlap >= prevCycleWords.length) {
      return;
    }

    // Start processing only the genuinely new words (after the overlap).
    // We allow re-checking one word before the divergence in case the CTC
    // refined a partial word (e.g. "الل" → "الله").
    int spokenPtr = math.max(0, overlap > 0 ? overlap - 1 : 0);

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

          final targetNorm = _cachedExpectedNorm![targetIndex];
          final score = _calculateMatchScore(spoken, targetNorm);

          if (score >= 0.70) {
            FileLogger.instance.log(
              '[MATCH] ✅ MATCHED (Pass 1): "$spoken" == "$targetNorm" (Score: $score)',
            );
            foundAt = targetIndex;
            foundSpokenAt = i;
            break;
          } else {
            FileLogger.instance.log(
              '[MATCH] ❌ FAILED (Pass 1): "$spoken" != "$targetNorm" (Score: $score)',
            );
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
              final expectedNorm = _cachedExpectedNorm![j];

              // ── Common Word / Stop Word Lookahead Penalty ──
              // Short words (1-2 letters like و, من, في, لا) are extremely common.
              // If we aggressively jump lookahead based on these, we cause false
              // reds when the user stutters or ASR hallucinates.
              // We only allow lookahead jumping on "substantial" words (>= 3 letters).
              if (expectedNorm.length <= 2) continue;

              if (expectedNorm.length <= 2) continue;

              final score = _calculateMatchScore(spoken, expectedNorm);
              if (score >= 0.85) {
                FileLogger.instance.log(
                  '[MATCH] ✅ MATCHED (Pass 2): "$spoken" == "$expectedNorm" (Score: $score)',
                );
                foundAt = j;
                foundSpokenAt = i;
                break;
              } else {
                FileLogger.instance.log(
                  '[MATCH] ❌ FAILED (Pass 2): "$spoken" != "$expectedNorm" (Score: $score)',
                );
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
            final expectedNorm = _cachedExpectedNorm![j];
            final score = _calculateMatchScore(spoken, expectedNorm);

            if (score >= threshold) {
              FileLogger.instance.log(
                '[MATCH] ✅ MATCHED (SinglePass): "$spoken" == "$expectedNorm" (Score: $score, Threshold: $threshold)',
              );
              foundAt = j;
              foundSpokenAt = i;
              break;
            } else {
              FileLogger.instance.log(
                '[MATCH] ❌ FAILED (SinglePass): "$spoken" != "$expectedNorm" (Score: $score, Threshold: $threshold)',
              );
            }
          }
          if (foundAt != -1) break;
        }
      }

      if (foundAt == -1) break;

      // Mark skipped expected words as red (skip during grace period)
      if (!_freshAyah) {
        for (int i = targetIndex; i < foundAt; i++) {
          _highlightQueue.add(
            _PendingHighlight.word(currentVerse.ayah, i, isRed: true),
          );
        }
      }

      // Mark matched word as green
      _highlightQueue.add(_PendingHighlight.word(currentVerse.ayah, foundAt));
      _startHighlightTimer();

      _lastCommittedWordIdx = foundAt;
      targetIndex = foundAt + 1;
      spokenPtr = foundSpokenAt + 1;
      anyProgress = true;
    }

    if (anyProgress) {
      _freshAyah = false; // Grace period over after first progress
      if (_lastCommittedWordIdx >= expectedWords.length - 1) {
        _advanceToNextAyah(); // Already calls notifyListeners() internally
      } else {
        notifyListeners(); // Only notify if advance didn't fire
      }
    }
  }

  double _calculateMatchScore(String spoken, String expected) {
    if (spoken == expected) return 1.0;

    // ── Partial Match Recovery (Anti-False-Red) ──────────────
    // When reading fast, the sliding audio window occasionally cuts off
    // the start or end of a long word, causing the offline ASR to output
    // only the surviving prefix or suffix (e.g., "قيم" instead of "المستقيم").
    // If the spoken fragment is at least 3 letters and perfectly matches
    // the start or end of the expected word, we accept it to prevent false reds!
    if (spoken.length >= 3 && expected.length >= 4) {
      if (expected.startsWith(spoken) || expected.endsWith(spoken)) {
        return 0.85; // High enough to pass the threshold cleanly
      }
    }

    // ASR Tajweed Fix: Ignore "ال" differences due to Lam Shamsiyyah blending.
    String w1 = spoken.startsWith("ال") ? spoken.substring(2) : spoken;
    String w2 = expected.startsWith("ال") ? expected.substring(2) : expected;

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
    _highlightQueue.add(_PendingHighlight.completeAyah(current.ayah));
    _startHighlightTimer();

    if (next != null) {
      _currentMatch = VerseMatch(verse: next, score: 1.0);
      // Bug 3 fix: When reciting fast, the sliding
      // window still contains audio from the previous ayah. If we clear
      // _prevSpokenWords, the dedup logic can't filter those residual
      // ASR words, causing them to falsely highlight in the new ayah.
      // We must ALWAYS preserve _prevSpokenWords across ayah boundaries.
      _freshAyah = true; // Suppress false reds on first match of new ayah
      _clearTrackingState(preservePrevWords: true);
      // We DO NOT call onAyahChanged() here anymore.
      // Calling it would force main.dart to wipe the AudioProcessor buffer,
      // completely destroying the continuous stream and dropping the first
      // words of the new ayah!
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

class _PendingHighlight {
  final int? ayah;
  final int? wordIndex;
  final bool isRed;
  final bool isAyahCompletion;

  _PendingHighlight.word(this.ayah, this.wordIndex, {this.isRed = false})
    : isAyahCompletion = false;

  _PendingHighlight.completeAyah(this.ayah)
    : wordIndex = null,
      isRed = false,
      isAyahCompletion = true;
}
