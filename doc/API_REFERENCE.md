# ⚡ ReciteQuran — API Quick Reference & Cheat Sheet

A concise, high-density API reference for developers and AI agents building applications with **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Core Engine (`ReciteQuran`)](#1-core-engine-recitequran)
2. [Configuration (`TrackerConfig`)](#2-configuration-trackerconfig)
3. [Event Protocol (`WordMatchedEvent`)](#3-event-protocol-wordmatchedevent)
4. [Audio Pipeline (`AudioProcessor`)](#4-audio-pipeline-audioprocessor)
5. [Voice Navigation (`VoiceSearchController`)](#5-voice-navigation-voicesearchcontroller)
6. [Tajweed Verification (`ErrorExplainer` & `TajweedErrorSheet`)](#6-tajweed-verification-errorexplainer--tajweederrorsheet)
7. [Memorization & Omission Detection (`LcsOmissionDetector`)](#7-memorization--omission-detection-lcsomissiondetector)
8. [Multi-Riwayah Mapping (`QiraatAyahMapper`)](#8-multi-riwayah-mapping-qiraatayahmapper)
9. [Neural Model Streaming (`ModelDownloader`)](#9-neural-model-streaming-modeldownloader)
10. [Quran Data Repository (`QuranRepository`)](#10-quran-data-repository-quranrepository)

---

## 1. Core Engine (`ReciteQuran`)

Main public facade located in [`lib/recite_quran.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/recite_quran.dart).

```dart
class ReciteQuran {
  /// Instantiates tracking engine.
  ReciteQuran({
    required QuranRepository repository,
    SherpaEngine? engine,
    TrackerConfig config = const TrackerConfig(),
    bool isTajweed = true,
  });

  // ── Lifecycle ──
  Future<void> initialize();
  void dispose();
  bool get isInitialized;
  bool get isDisposed;

  // ── Navigation & Targets ──
  void setTargetSurah(int surahNumber, {int startGlobalWord = 0, bool forceClear = true});
  void jumpToWord(int globalWordIndex);
  int get targetSurah;

  // ── Audio Feeding ──
  /// Feeds 16kHz Mono Float32 chunk [-1.0, 1.0] into recognizer.
  bool feedAudioChunk(Float32List chunk, {bool isFinal = false});
  void resetBuffer();

  // ── Runtime Mode & Config ──
  void setTajweedMode(bool active);
  void updateConfig(TrackerConfig newConfig);
  bool get isTajweed;
  TrackerConfig get config;

  // ── Streams ──
  Stream<WordMatchedEvent> get onWordMatched;
  Stream<String> get onTranscript;
}
```

---

## 2. Configuration (`TrackerConfig`)

Immutable configuration class located in [`lib/tracking/tracker_config.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/tracking/tracker_config.dart).

```dart
class TrackerConfig {
  final RecitationSpeed recitationSpeed;    // fast, normal, slow
  final MatchingStrictness matchingStrictness; // easy, normal, hard
  final bool enableEarlyMatching;           // default: true
  final bool enableAutoReanchor;            // default: false (STRONGLY RECOMMENDED: set true for Tilawah & Quran reading apps!)
  final int reanchorStallThreshold;          // default: 24 phonemes (3-5 words)

  const TrackerConfig({
    this.recitationSpeed = RecitationSpeed.normal,
    this.matchingStrictness = MatchingStrictness.normal,
    this.enableEarlyMatching = true,
    this.enableAutoReanchor = false,
    this.reanchorStallThreshold = 24,
  });

  // Factory presets:
  factory TrackerConfig.normal({
    RecitationSpeed speed, 
    bool enableEarlyMatching, 
    bool enableAutoReanchor, 
    int reanchorStallThreshold,
  });
  factory TrackerConfig.easy({
    RecitationSpeed speed, 
    bool enableEarlyMatching, 
    bool enableAutoReanchor, 
    int reanchorStallThreshold,
  });
  factory TrackerConfig.strict({
    RecitationSpeed speed, 
    bool enableEarlyMatching, 
    bool enableAutoReanchor, 
    int reanchorStallThreshold,
  });
}
```

> [!TIP]
> **💡 Recommendation on `enableAutoReanchor`:**
> Although `enableAutoReanchor` defaults to `false` out of conservative author caution (to protect strict Hifdh exam apps and untested edge cases), **developers building consumer Quran readers, Tilawah, or Mus'haf apps are strongly encouraged to pass `enableAutoReanchor: true`.** The engine's built-in Anti-Ambiguity Guard ($\Delta\text{dist} < 3$) ensures false jumps are suppressed even across repeated verses like Surah Ar-Rahman.

---

## 3. Event Protocol (`WordMatchedEvent`)

Emitted on `tracker.onWordMatched` for every word alignment event.

```dart
class WordMatchedEvent {
  /// 0-indexed global word offset within the active Surah.
  final int wordId;

  /// Dynamic Programming similarity score (0.0 to 1.0).
  final double score;

  /// Normalized ASR phonetic tokens matched to this word.
  final String cleanAsr;

  /// Detected Tajweed violations (null or empty if recitation was valid).
  final List<Map<String, dynamic>>? tajweedErrors;

  /// True if word was skipped by reciter or omitted.
  final bool isRed;

  /// True if word is neutral / unreached.
  final bool isNeutral;

  /// Helper getters:
  bool get isGreen => !isRed && (tajweedErrors == null || tajweedErrors!.isEmpty);
  bool get isYellow => !isRed && tajweedErrors != null && tajweedErrors!.isNotEmpty;
}
```

---

## 4. Audio Pipeline (`AudioProcessor`)

Cross-platform raw audio capture located in [`lib/audio/audio_processor.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/audio/audio_processor.dart).

```dart
class AudioProcessor {
  static const int recordSampleRate = 16000;
  static const int numChannels = 1;
  static const int chunkMs = 480;

  Future<bool> hasPermission();
  Future<void> start({
    required void Function(Float32List chunk, bool isFinal) onChunk,
  });
  Future<void> stop();
  void dispose();
}
```

---

## 5. Voice Navigation (`VoiceSearchController`)

Tarteel-style "Recite to Navigate" search across all 6,236 Ayahs.

```dart
class VoiceSearchController {
  VoiceSearchController({
    required SherpaEngine engine,
    QuranRepository? repository,
  });

  /// Pre-computes 64-bit Myers bit-parallel index in background isolate.
  Future<void> preloadIndex();

  /// Starts listening to microphone and streaming live candidate Ayahs.
  Future<void> startListening();
  Future<void> stopListening();

  /// Reactive state of current search results:
  ValueNotifier<AyahSearchResult?> get currentResult;

  void dispose();
}

class AyahSearchResult {
  final List<AyahSearchMatch> candidates;
  final bool isUnique;
  AyahSearchMatch? get topMatch;
}

class AyahSearchMatch {
  final int surah;
  final int ayah;
  final double score;
  final int distance;
  final String? surahNameAr;
  final String? surahNameEn;
  final String? textUthmani;
}
```

---

## 6. Tajweed Verification (`ErrorExplainer` & `TajweedErrorSheet`)

Bilingual explanations and modal bottom sheet located in [`lib/tracking/tajweed/`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/tracking/tajweed).

```dart
class ErrorExplainer {
  /// Generates human-readable pedagogical explanation in Arabic or English.
  static TajweedErrorInfo explain(
    Map<String, dynamic> errorMap, {
    bool isArabic = true,
  });
}

class TajweedErrorInfo {
  final String title;       // e.g. "نقص في مقدار المد المنفصل"
  final String description; // Scholarly explanation of the rule
  final String remedy;      // Corrective instruction for the learner
}

// Pre-built modal dialog:
TajweedErrorSheet.show(
  context,
  wordUthmani: 'الضَّالِّينَ',
  errors: event.tajweedErrors!,
  isArabic: true,
);
```

---

## 7. Memorization & Omission Detection (`LcsOmissionDetector`)

Best-Drop LCS algorithm located in [`lib/utils/omission_detector.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/utils/omission_detector.dart).

```dart
class LcsOmissionDetector {
  static OmissionResult detectOmission({
    required List<String> phonemesPerWord,
    required String emittedPhonemes,
  });
}

class OmissionResult {
  final bool isOmissionDetected;
  final int? omittedWordIndex;
  final int shortfall;
  final int confidenceGap;
  final double scoreRatio;
}
```

---

## 8. Multi-Riwayah Mapping (`QiraatAyahMapper`)

Canonical cross-Riwayah alignment located in [`lib/data/qiraat_ayah_mapper.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/qiraat_ayah_mapper.dart).

```dart
class QiraatAyahMapper {
  Future<void> initialize();

  /// Converts an Ayah index from source Riwayah to target Riwayah.
  MappedAyahResult? mapAyah({
    required int surah,
    required int ayah,
    required QuranRiwayah fromRiwayah,
    required QuranRiwayah toRiwayah,
  });
}

enum QuranRiwayah { hafs, warsh, qalun, dori, sousi, shubah, bazi, qunbul, ... }
enum QuranCountingSystem { kufi, madaniLast, madaniFirst, makki, basri, dimashqi }
```

---

## 9. Neural Model Streaming (`ModelDownloader`)

On-demand download located in [`lib/data/model_downloader.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/model_downloader.dart).

```dart
class ModelDownloader {
  Future<bool> isModelReady();
  Future<String> getModelPath();
  Future<void> downloadModel({
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });
}
```

---

## 10. Quran Data Repository (`QuranRepository`)

Data access located in [`lib/data/quran_data.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/quran_data.dart).

```dart
class QuranRepository {
  QuranRepository(QuranMetadataService metadataService);

  Future<void> loadSurahAsync(int surahNumber);
  List<ContinuousQuranWord> getSurahWords(int surahNumber);
  bool get isTajweedSupported;
}

class ContinuousQuranWord {
  final int globalWordIndex;
  final int ayahNumber;
  final String textUthmani;
  final String phoneme;
  final List<WordTajweedRule> rules;
}
```
