// lib/recite_quran.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'data/quran_data.dart';
import 'engine/sherpa_engine.dart';
import 'data/model_loader.dart';
import 'tracking/word/highlighting_controller.dart';

export 'audio/audio_processor.dart';
export 'data/model_loader.dart';
export 'data/quran_data.dart';
export 'engine/sherpa_engine.dart' show SherpaEngine, TranscriptionResult;
export 'tracking/ayah_search/voice_search_controller.dart';
export 'tracking/tajweed/error_explainer.dart' show ErrorCategory, SpeechErrorType, ReciterError;
export 'tracking/tajweed/tajweed_rules.dart' show TajweedDurationStatus;
export 'tracking/tracker_config.dart';
export 'tracking/word/dictation_matcher.dart' show WordMatchResult;
export 'tracking/word/highlighting_controller.dart';
export 'tracking/word/phoneme_alignment_isolate.dart' show WordMatchedEvent, DebugLogEvent;
export 'utils/debug_logger.dart';

/// Type alias for QuranRepository.
typedef QuranDataRepository = QuranRepository;

/// Type alias for backwards compatibility.
typedef QuranVoiceTracker = ReciteQuran;

// ═══════════════════════════════════════════════════════════════════════════════
// RECITE QURAN SDK (MAIN PUBLIC FACADE)
// ═══════════════════════════════════════════════════════════════════════════════

/// The primary entry point for integrating real-time Quran recitation tracking
/// and deterministic Tajweed verification into any Flutter application.
class ReciteQuran {
  final QuranRepository repository;
  final SherpaEngine _engine;
  final PhonemeAlignmentIsolate _isolate = PhonemeAlignmentIsolate();
  late final AsrTokenProcessor _tokenProcessor;

  TrackerConfig _config;
  bool _isTajweed;
  bool _isInitialized = false;
  int _targetSurah = 0;

  StreamSubscription? _engineSub;
  StreamSubscription<WordMatchedEvent>? _wordSub;

  final StreamController<WordMatchedEvent> _wordEventController =
      StreamController<WordMatchedEvent>.broadcast();
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  // ── Public Streams ──

  /// Stream of matched word events (Green matches, Red errors, Neutral skips).
  Stream<WordMatchedEvent> get onWordMatched => _wordEventController.stream;

  /// Real-time live speech-to-text phonetic transcript from the ASR model.
  Stream<String> get onTranscript => _transcriptController.stream;

  /// Current active configuration.
  TrackerConfig get config => _config;

  /// Current target Surah number.
  int get targetSurah => _targetSurah;

  /// Indicates if Tajweed duration and closure evaluation is enabled.
  bool get isTajweed => _isTajweed;

  /// Whether the engine and background isolate have been initialized.
  bool get isInitialized => _isInitialized;

  ReciteQuran({
    required this.repository,
    SherpaEngine? engine,
    TrackerConfig config = const TrackerConfig(),
    bool isTajweed = true,
  })  : _engine = engine ?? SherpaEngine(),
        _config = config,
        _isTajweed = isTajweed {
    _tokenProcessor = AsrTokenProcessor(config: _config);
  }

  // ── 1. Initialization ──

  /// Initializes the ASR engine, acoustic models, and background isolate pipeline.
  ///
  /// If the ONNX model is not present, it will automatically download or extract it.
  Future<void> initialize({
    String? onnxModelPath,
    String? bundledAssetPath,
    String downloadUrl = ModelLoader.defaultRemoteModelUrl,
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (_isInitialized) return;

    // 1. Resolve ONNX Model Path
    await ModelLoader.prepareModelPath(
      customFilePath: onnxModelPath,
      bundledAssetPath: bundledAssetPath,
      downloadUrl: downloadUrl,
      onDownloadProgress: onDownloadProgress,
    );

    // 2. Initialize Sherpa Engine
    await _engine.initialize();

    // 3. Start Background Alignment Isolate
    await _isolate.start();
    _isolate.updateConfig(_config);
    _isolate.setTajweedMode(_isTajweed);

    // 4. Subscribe to Streams
    _wordSub = _isolate.wordStream.listen(_wordEventController.add);
    _engineSub = _engine.transcriptionStream.listen(_onTranscriptionResult);

    _isInitialized = true;
  }

  // ── 2. Surah & Ayah Target Setup ──

  /// Sets the active Surah reference for recitation tracking.
  void setTargetSurah(
    int surahNumber, {
    int startGlobalWord = 0,
    bool forceClear = true,
  }) {
    _targetSurah = surahNumber;
    final words = repository.getSurahWords(surahNumber);
    if (words.isEmpty) return;

    final List<String> phonemeWords = words.map((w) => w.phoneme).toList();
    final List<List<WordTajweedRule>> wordRules = words.map((w) => w.rules).toList();
    final List<int> boundaries = _calculateBoundaries(phonemeWords);
    final String fullPhonemes = phonemeWords.join('');

    _isolate.setSurahReference(
      fullPhonemes,
      boundaries,
      isTajweed: _isTajweed,
      forceClear: forceClear,
      startGlobalWord: startGlobalWord,
      surahNumber: surahNumber,
      wordRules: wordRules,
    );
  }

  /// Jumps the tracking cursor to a specific word index.
  void jumpToWord(int globalWordIndex) {
    _isolate.jumpToWord(globalWordIndex);
  }

  // ── 3. Audio & Tracking Control ──

  /// Feeds a normalized float audio chunk [-1.0, 1.0] (16 kHz mono) into the ASR recognizer.
  bool feedAudioChunk(Float32List chunk, {bool isFinal = false}) {
    return _engine.transcribe(chunk, isFinal: isFinal);
  }

  /// Resets the internal recognition buffer.
  void resetBuffer() {
    _engine.resetBuffer();
  }

  /// Toggles Tajweed evaluation on/off.
  void setTajweedMode(bool active) {
    _isTajweed = active;
    _isolate.setTajweedMode(active);
  }

  /// Updates difficulty and math thresholds dynamically at runtime.
  void updateConfig(TrackerConfig newConfig) {
    _config = newConfig;
    _tokenProcessor.config = newConfig;
    _isolate.updateConfig(newConfig);
  }

  // ── 4. Internal Message Pump ──

  void _onTranscriptionResult(TranscriptionResult result) {
    if (result.text.isNotEmpty) {
      _transcriptController.add(result.text);
    }

    final processed = _tokenProcessor.process(result);
    if (processed.isEmpty) return;

    final String asrString = processed.tokens.join('');
    final List<double> asrTimestamps = processed.durations;

    _isolate.syncStream(asrString, asrTimestamps);
  }

  List<int> _calculateBoundaries(List<String> phonemeWords) {
    final List<int> boundaries = [0];
    int currentOffset = 0;
    for (final w in phonemeWords) {
      currentOffset += w.length;
      boundaries.add(currentOffset);
    }
    return boundaries;
  }

  // ── 5. Cleanup ──

  void dispose() {
    _engineSub?.cancel();
    _wordSub?.cancel();
    _engine.destroy();
    _isolate.stop();
    _wordEventController.close();
    _transcriptController.close();
  }
}
