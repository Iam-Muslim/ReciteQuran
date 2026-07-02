// lib/tracking/word/highlighting_controller.dart
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

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../engine/sherpa_engine.dart';
import '../../data/quran_data.dart';
import '../tajweed/error_explainer.dart';
import 'phoneme_alignment_isolate.dart';

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
  bool isTajweed;

  void setTajweedMode(bool active) {
    if (isTajweed == active) return;
    isTajweed = active;
    if (_isolateStarted) {
      _alignmentIsolate.setTajweedMode(active);
    }
    notifyListeners();
  }

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
  final Map<int, Map<int, List<ReciterError>>> _errorsByVerse = {};
  final Set<int> _completedAyahs = {};

  // ── Debug ─────────────────────────────────────────────────────────────────
  final ValueNotifier<String> debugRecognizedText = ValueNotifier('');

  final ValueNotifier<int> globalRevision = ValueNotifier(0);

  final PhonemeAlignmentIsolate _alignmentIsolate = PhonemeAlignmentIsolate();
  bool _isolateStarted = false;

  int _lastResetTime = 0;
  String _lastProcessedText = '';
  bool _expectingNewSegment = false;
  int? _pendingClearAyah;

  HighlightingController({
    required this.repository,
    required SherpaEngine engine,
    this.onAyahChanged,
    this.isTajweed = true,
  }) : _engine = engine {
    _initIsolate();
    _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  Future<void> _initIsolate() async {
    await _alignmentIsolate.start();
    _isolateStarted = true;
    _alignmentIsolate.wordStream.listen(_onIsolateWordMatched);
    _alignmentIsolate.ayahCompletedStream.listen(_onAyahCompleted);
    
    if (_currentMatch != null) {
      _alignmentIsolate.setAyah(
        _currentMatch!.verse.textPhoneme, 
        _calculateBoundaries(_currentMatch!.verse.phonemeWords),
        isTajweed: isTajweed,
      );
    }
  }

  void _onIsolateWordMatched(Map<String, dynamic> event) {
    if (_currentMatch == null) return;
    final targetAyah = _currentMatch!.verse;
    final ayahNum = targetAyah.ayah;

    int wordId = event['word_id'] as int;
    bool isRed = event['is_red'] as bool? ?? false;
    String cleanAsr = event['clean_asr'] as String? ?? '';
    List<double> cleanTimestamps = [];
    if (event['timestamps'] != null) {
      cleanTimestamps = (event['timestamps'] as List).cast<double>();
    }

    if (!(_greenWordsByVerse[ayahNum]?.contains(wordId) ?? false) &&
        !(_redWordsByVerse[ayahNum]?.contains(wordId) ?? false) &&
        !(_yellowWordsByVerse[ayahNum]?.contains(wordId) ?? false)) {
      
      if (isRed) {
        (_redWordsByVerse[ayahNum] ??= {}).add(wordId);
      } else {
        (_greenWordsByVerse[ayahNum] ??= {}).add(wordId);
      }
      
      // Real-time Tajweed Evaluation (Deferred Commitment)
      // Since wordId is now fully matched, any boundary rules (Idgham) for wordId - 1
      // can be accurately evaluated because cleanAsr contains the boundary!
      if (isTajweed && cleanAsr.isNotEmpty) {
        final errors = ErrorExplainer.explainAyahError(
          targetAyah.textPhoneme,
          cleanAsr,
          targetAyah.phonemeWords,
          cleanTimestamps,
        );
        
        // Only apply errors for words strictly less than the currently matched wordId
        // This ensures boundary rules (like Idgham with the next word) are fully evaluated
        // before we lock in the Tajweed status.
        bool changed = false;
        errors.forEach((errWordId, errList) {
          if (errWordId < wordId) {
             if (_greenWordsByVerse[ayahNum]?.contains(errWordId) ?? false) {
               _greenWordsByVerse[ayahNum]?.remove(errWordId);
               (_yellowWordsByVerse[ayahNum] ??= {}).add(errWordId);
               (_errorsByVerse[ayahNum] ??= {})[errWordId] = errList;
               changed = true;
             }
          }
        });
        
        if (changed) {
          notifyListeners();
        }
      }
      
      // If this was the last word of the Ayah, automatically advance to the next Ayah!
      if (wordId == targetAyah.phonemeWords.length - 1) {
        _completedAyahs.add(ayahNum);
        
        final nextVerse = repository.getNextVerse(targetAyah.surah, targetAyah.ayah);
        if (nextVerse != null) {
          // Delay very slightly to let the UI paint the last word green before jumping
          Future.delayed(const Duration(milliseconds: 50), () {
             forceActiveAyah(nextVerse);
          });
        } else {
          finalize();
        }
      }
      
      notifyListeners();
    }
  }

  void _onAyahCompleted(Map<String, dynamic> event) {
    if (_currentMatch == null) return;
    String rawAsr = event['raw_asr'] as String;
    List<double> timestamps = (event['timestamps'] as List).cast<double>();
    print('[HighlightingController] Ayah completed with raw ASR: $rawAsr');
    
    if (isTajweed) {
      final targetAyah = _currentMatch!.verse;
      final errors = ErrorExplainer.explainAyahError(
        targetAyah.textPhoneme,
        rawAsr,
        targetAyah.phonemeWords,
        timestamps,
      );
      
      if (errors.isNotEmpty) {
        _errorsByVerse[targetAyah.ayah] = errors;
        
        for (int wordId in errors.keys) {
           _greenWordsByVerse[targetAyah.ayah]?.remove(wordId);
           (_yellowWordsByVerse[targetAyah.ayah] ??= {}).add(wordId);
        }
        
        notifyListeners();
      }
    }
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  HighlightingController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;
  Set<int> get completedAyahs => _completedAyahs;
  bool get softWarningActive => false;

  int? get activeWordIndex {
    return null; // Tracking is now fully async in isolate
  }

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

    // Fallback to persisted errors (from post-ayah processing or baseline copy)
    return _errorsByVerse[ayah]?[pIdx];
  }

  // ── Surah / ayah management ───────────────────────────────────────────────

  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    reset();
  }

  void clearHighlights() {
    _completedAyahs.clear();
    _greenWordsByVerse.clear();
    _redWordsByVerse.clear();
    _yellowWordsByVerse.clear();
    _errorsByVerse.clear();
    globalRevision.value++;
    notifyListeners();
  }

  void clearHighlightsFromAyah(int startAyah) {
    _completedAyahs.removeWhere((ayah) => ayah >= startAyah);
    _greenWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _redWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _yellowWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _errorsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    globalRevision.value++;
    notifyListeners();
  }

  /// Jump to a specific ayah manually (user taps a verse row).
  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      activeAyah.value = ayah;
      
      if (_isolateStarted) {
        _alignmentIsolate.setAyah(verse.textPhoneme, _calculateBoundaries(verse.phonemeWords), isTajweed: isTajweed, forceClear: true);
      }

      _engine.resetBuffer();
      _lastResetTime = DateTime.now().millisecondsSinceEpoch;
      _pendingClearAyah = ayah;
      onAyahChanged?.call();
      notifyListeners();
    }
  }

  List<int> _calculateBoundaries(List<String> words) {
    List<int> bounds = [];
    int cursor = 0;
    for (String w in words) {
      bounds.add(cursor);
      cursor += w.replaceAll(' ', '').length;
    }
    bounds.add(cursor); // The end boundary
    return bounds;
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
    if (_currentMatch != null && _isolateStarted) {
      _alignmentIsolate.setAyah(_currentMatch!.verse.textPhoneme, _calculateBoundaries(_currentMatch!.verse.phonemeWords), isTajweed: isTajweed, forceClear: true);
    }
    _engine.resetBuffer();
    _lastProcessedText = '';
    _expectingNewSegment = false;
    _lastResetTime = DateTime.now().millisecondsSinceEpoch;
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
    } else if (activeAyah.value != null) {
      clearHighlightsFromAyah(activeAyah.value!);
    }
    
    // CRITICAL: Synchronize Isolate state! Since we cleared the UI highlights,
    // the isolate must also reset its word cursor back to 0 for this Ayah.
    if (_currentMatch != null && _isolateStarted) {
      _alignmentIsolate.setAyah(_currentMatch!.verse.textPhoneme, _calculateBoundaries(_currentMatch!.verse.phonemeWords), isTajweed: isTajweed, forceClear: true);
    }
    
    _engine.resetBuffer();
    _lastProcessedText = '';
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
    
    if (_isolateStarted) {
      _alignmentIsolate.setAyah(verse.textPhoneme, _calculateBoundaries(verse.phonemeWords), isTajweed: isTajweed);
    }

    // We intentionally DO NOT reset the ASR engine here.
    // This allows seamless continuous recitation across ayahs without boundary clipping.
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────



  void _onResult(TranscriptionResult result) {
    if (_state == TrackerState.discovery) return;
    if (_currentMatch == null) return;

    if (result.startTime < _lastResetTime) {
      return;
    }

    List<double> charDurations = [];
    StringBuffer asrTextBuffer = StringBuffer();
    
    double currentAudioTime = (DateTime.now().millisecondsSinceEpoch - _lastResetTime) / 1000.0;
    
    for (int i = 0; i < result.tokens.length; i++) {
      String token = result.tokens[i].replaceAll(' ', '');
      if (token.isEmpty) continue; // Safely skip space-only tokens
      
      double tokenDur = 0.15;
      if (i < result.timestamps.length - 1) {
         tokenDur = result.timestamps[i+1] - result.timestamps[i];
      } else if (i < result.timestamps.length) {
         // Trailing token: calculate duration dynamically using elapsed audio time!
         tokenDur = currentAudioTime - result.timestamps[i];
      }
      
      // Safety clamps
      if (tokenDur <= 0.15) tokenDur = 0.15;
      if (tokenDur > 3.0) tokenDur = 3.0; 
      
      double charDur = tokenDur / token.length;
      
      for (int j = 0; j < token.length; j++) {
        asrTextBuffer.write(token[j]);
        charDurations.add(charDur);
      }
    }
    
    final String asrText = asrTextBuffer.toString();
    debugRecognizedText.value = asrText;

    if (asrText.length > 800) {
      _engine.resetBuffer();
      _lastProcessedText = '';
      return;
    }

    if (asrText.isEmpty) {
      _lastProcessedText = '';
      if (result.isFinal) {
        _expectingNewSegment = true;
      }
      return;
    }
    
    if (_expectingNewSegment) {
      _lastProcessedText = '';
      _expectingNewSegment = false;
    }
    
    // Detect if the ASR engine started a completely new segment (e.g. after final=true)
    if (!asrText.startsWith(_lastProcessedText)) {
       int commonLen = 0;
       int minLen = min(_lastProcessedText.length, asrText.length);
       for (int i = 0; i < minLen; i++) {
         if (_lastProcessedText[i] == asrText[i]) {
           commonLen++;
         } else {
           break;
         }
       }
       
       // If it shares almost nothing with the old text, it's a new segment, not a tail correction.
       if (commonLen == 0 || (commonLen < 5 && _lastProcessedText.length > 20)) {
          _lastProcessedText = '';
       }
    }

    // charDurations is now calculated earlier in the method.

    String newText = asrText;
    List<double> newTimestamps = charDurations;
    if (newText.startsWith(_lastProcessedText)) {
      newText = newText.substring(_lastProcessedText.length);
      if (charDurations.length >= _lastProcessedText.length) {
         newTimestamps = charDurations.sublist(_lastProcessedText.length);
      } else {
         newTimestamps = [];
      }
      if (newText.isNotEmpty && _isolateStarted) {
        _alignmentIsolate.feed(newText, newTimestamps);
      }
    } else {
      // The ASR rewrote the past (corrected itself).
      // Find the longest common prefix to know where the rewrite started.
      int commonLen = 0;
      int minLen = min(_lastProcessedText.length, asrText.length);
      for (int i = 0; i < minLen; i++) {
        if (_lastProcessedText[i] == asrText[i]) {
          commonLen++;
        } else {
          break;
        }
      }
      
      int backtrackChars = _lastProcessedText.length - commonLen;
      String newTail = asrText.substring(commonLen);
      List<double> newTailTimestamps = [];
      if (charDurations.length >= commonLen) {
         newTailTimestamps = charDurations.sublist(commonLen);
      }
      
      if (_isolateStarted) {
        _alignmentIsolate.replaceTail(backtrackChars, newTail, newTailTimestamps);
      }
    }
    
    _lastProcessedText = asrText;
    
    if (result.isFinal) {
      _expectingNewSegment = true;
    }
  }
}
