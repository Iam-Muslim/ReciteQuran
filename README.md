<div align="center">

# وما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ

# ReciteQuran — اتلو القران
### Real-Time On-Device Quran Recitation Tracking & Deterministic Tajweed Verification

[![pub package](https://img.shields.io/badge/pub.dev-recite__quran%20v1.0.0-blue.svg)](https://pub.dev/packages/recite_quran)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-green.svg)](https://pub.dev/packages/recite_quran)
[![Offline](https://img.shields.io/badge/Offline-100%25%20On--Device-orange.svg)](https://pub.dev/packages/recite_quran)
[![License](https://img.shields.io/badge/License-Non--Commercial%20%2F%20Free%20for%20Allah-purple.svg)](#-sacred-covenant--license-لوجه-الله-تعالى)

</div>

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Architecture & Data Pipeline](#-architecture--data-pipeline)
- [Platform Prerequisites (Microphone Setup)](#-platform-prerequisites-microphone-setup)
- [Installation & Model Setup](#-installation--model-setup)
- [Quick Start Guide](#-quick-start-guide)
- [Core Features & Guides](#-core-features--guides)
  - [1. Real-Time Word Tracking](#1-real-time-word-tracking-green--red-matching)
  - [2. Deterministic Tajweed Verification](#2-deterministic-tajweed-verification)
  - [3. Voice Navigation & Ayah Search (6,236 Ayahs)](#3-voice-navigation--ayah-search-6236-ayahs)
  - [4. Difficulty Presets & Config Tuning](#4-difficulty-presets--config-tuning)
- [Complete API Reference](#-complete-api-reference)
- [Interactive Sample App](#-interactive-sample-app)
- [Troubleshooting & FAQ](#-troubleshooting--faq)
- [Sacred Covenant & License (لوجه الله تعالى)](#-sacred-covenant--license-لوجه-الله-تعالى)
- [Acknowledgments](#-acknowledgments)

---

## 🌟 Overview

**`recite_quran`** is a high-performance, real-time on-device speech-to-text alignment and Tajweed evaluation engine for Flutter.

* 🎙️ **Continuous Word Tracking**: Zero-lag real-time word alignment powered by semi-global Dynamic Time Warping (DTW) and causal Zipformer CTC acoustic models.
* 📏 **Deterministic Tajweed Rules**:
  * **Madd Rules (1–7)**: Validates elongation duration (2, 4, 6 Harakat) against acoustic timestamps.
  * **Mushaddad Ghunnah (10)**: Verifies 2-Harakah nasal holding on Mushaddad Noon (`نّ`) & Meem (`مّ`).
  * **Shaddah (9)**: Inspects consonant closure duration (~1.5 Harakat) and doubling.
* 🔎 **Instant Voice Navigation**: Recite any verse or phrase to instantly search across all 6,236 Ayahs via phonetic N-gram indexing.
* 🔒 **100% Private & Offline**: All audio processing and neural network inference occur on-device. No cloud APIs, no network latency, and no user data transmission.
* ⚡ **Cross-Platform Multi-Threading**: Heavy acoustic decoding and DTW matching run on background Dart Isolates (Native) and Web Workers/WASM (Web) to keep the UI at a buttery 60/120 FPS.

---

## 🏗️ Architecture & Data Pipeline

```
┌─────────────────────────┐
│     Microphone (16kHz)  │
└────────────┬────────────┘
             │ Raw PCM Chunks
             ▼
┌─────────────────────────┐
│     AudioProcessor      │ ──► Configures AVAudioSession / Android Audio (Disables DSP noise filter)
└────────────┬────────────┘
             │ 480ms Float32 Chunks (TransferableTypedData zero-copy)
             ▼
┌─────────────────────────┐
│  SherpaEngine (Isolate) │ ──► Zipformer2 CTC ONNX Acoustic Neural Model (250 Phoneme Units)
└────────────┬────────────┘
             │ Phoneme Tokens + Spike Timestamps
             ▼
┌─────────────────────────┐
│ Alignment (Isolate)     │ ──► Semi-Global Dynamic Time Warping (DTW) + Phonetic Confusion Matrix
└────────────┬────────────┘
             │
      ┌──────┴───────────────────────────┐
      ▼                                  ▼
┌───────────────────────────┐      ┌───────────────────────────┐
│ WordMatchedEvent (UI)     │      │ Tajweed Duration Checks   │
│ Green / Red / Neutral     │      │ Madd, Ghunnah, Shaddah    │
└───────────────────────────┘      └───────────────────────────┘
```

---

## 📱 Platform Prerequisites (Microphone Setup)

### Android
Add the microphone permission to `android/app/src/main/AndroidManifest.xml`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
</manifest>
```

### iOS / macOS
Add the microphone usage description to `ios/Runner/Info.plist` and `macos/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to listen to your Quran recitation and track words in real time.</string>
```

For macOS, also enable audio input in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

---

## 📦 Installation & Model Setup

### 1. Add Dependency
Add `recite_quran` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  recite_quran: ^1.0.0
```

### 2. Download the Neural Model
The neural acoustic model (`zipformer_p_arabic_v3.int8.onnx`, ~72MB) is hosted on GitHub Releases to keep the initial pub download lightweight.

Run this single setup command from your Flutter project root:

```bash
dart run recite_quran:model_loader
```

This command automatically:
1. Downloads the INT8 ONNX acoustic model to `assets/model/zipformer_p_arabic_v3.int8.onnx`.
2. Adds `assets/model/zipformer_p_arabic_v3.int8.onnx` to your `pubspec.yaml`.

*(All other Quran phoneme metadata and search indices are already bundled internally in the package!)*

---

## 💻 Quick Start Guide

Here is a minimal, complete example showing audio capture, recitation tracking, and Tajweed diagnostics:

```dart
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Quran Metadata
  final metadataService = QuranMetadataService();
  final repository = QuranRepository(metadataService);
  await repository.loadSurahAsync(1); // Pre-load Surah Al-Fatihah (Surah #1)

  // 2. Instantiate ReciteQuran Tracker
  final tracker = ReciteQuran(
    repository: repository,
    config: TrackerConfig.normal(), // Presets: .easy(), .normal(), .strict()
    isTajweed: true,                // Enable Tajweed verification
  );

  // 3. Initialize background Isolates and ASR Engine
  await tracker.initialize();

  // 4. Set Surah Al-Fatihah as active reference
  tracker.setTargetSurah(1);

  // 5. Listen to real-time word match events
  tracker.onWordMatched.listen((WordMatchedEvent event) {
    if (event.isRed) {
      print('❌ Word #${event.wordId} skipped or mispronounced');
    } else {
      print('✅ Matched Word #${event.wordId} (Score: ${(event.score * 100).toInt()}%)');
      
      // Inspect Tajweed duration diagnostics (if any)
      if (event.tajweedErrors != null && event.tajweedErrors!.isNotEmpty) {
        for (final errorMap in event.tajweedErrors!) {
          final error = ReciterError.fromMap(errorMap);
          print('⚠️ Tajweed rule: ${error.expectedRule?.name.ar} | Status: ${error.durationStatus}');
        }
      }
    }
  });

  // 6. Listen to live ASR phoneme stream
  tracker.onTranscript.listen((String transcript) {
    print('Live ASR Transcript: $transcript');
  });

  // 7. Start microphone audio stream
  final audioProcessor = AudioProcessor();
  await audioProcessor.start(
    onChunk: (Float32List chunk, bool isFinal) {
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    },
  );
}
```

---

## 🎯 Core Features & Guides

### 1. Real-Time Word Tracking (Green / Red Matching)

The tracking engine processes the user's recitation sequentially using semi-global DTW:
* **Green Match (`event.isRed == false`)**: The spoken word matched the reference within the configured threshold.
* **Red Match (`event.isRed == true`)**: The user skipped one or more words or made a substantial phonetic mistake.
* **Anchor Advancement**: When a match occurs, the alignment window automatically advances to the next word.
* **Partial Words**: If a user is currently pronouncing a long word, the engine holds state until the full word is articulated.

```dart
tracker.onWordMatched.listen((event) {
  final int wordIndex = event.wordId;
  final bool isError = event.isRed;
  final double similarity = event.score; // 0.0 to 1.0
  final String cleanAsr = event.cleanAsr;
});
```

---

### 2. Deterministic Tajweed Verification

When `isTajweed: true` is enabled, each matched word evaluates acoustic duration timestamps against canonical Tajweed rules:

```dart
tracker.onWordMatched.listen((event) {
  if (event.tajweedErrors != null) {
    for (final map in event.tajweedErrors!) {
      final ReciterError error = ReciterError.fromMap(map);
      
      print('Rule Name (Arabic): ${error.expectedRule?.name.ar}');
      print('Rule Name (English): ${error.expectedRule?.name.en}');
      print('Expected Duration: ${error.expectedDuration} seconds');
      print('Actual Recited Duration: ${error.actualDuration} seconds');
      print('Status: ${error.durationStatus}'); 
      // TajweedDurationStatus.defect  (نقص - held too short)
      // TajweedDurationStatus.surplus (زيادة - held too long)
      // TajweedDurationStatus.valid   (صحيح)
    }
  }
});
```

#### Covered Tajweed Rules:
| Rule ID | Rule Name | Description | Target Harakat |
| :--- | :--- | :--- | :--- |
| **1** | Normal Madd (`المد الطبيعي`) | Natural 2-beat vowel elongation | 2 Harakat (0.50s) |
| **2** | Monfasel Madd (`المد المنفصل`) | Separated elongation before Hamzah | 4 Harakat (1.00s) |
| **3** | Mottasel Madd (`المد المتصل`) | Connected elongation with Hamzah | 4 Harakat (1.00s) |
| **4** | Aared Lil-Sukoon (`المد العارض للسكون`) | Optional pause elongation | 4 Harakat (1.00s) |
| **5** | Leen Madd (`مد اللين`) | Soft vowel pause elongation | 4 Harakat (1.00s) |
| **6** | Lazem Madd (`المد اللازم`) | Compulsory 6-beat elongation | 6 Harakat (1.50s) |
| **9** | Shaddah (`الشدة`) | Consonant closure & doubling hold | ~1.5 Harakat (0.375s) |
| **10** | Mushaddad Ghunnah (`النون والميم المشددتان`) | Nasal resonance holding on `نّ` and `مّ` | 2 Harakat (0.50s) |

---

### 3. Voice Navigation & Ayah Search (6,236 Ayahs)

Allow your users to recite any verse or fragment to jump directly to that Surah and Ayah:

```dart
final searchController = VoiceSearchController(engine: tracker.engine);

// Preload the 6,236-Ayah phonetic index
await searchController.preloadIndex();

// When user holds the mic button:
await searchController.startSearch();

// Feed streaming ASR text to search:
tracker.onTranscript.listen((transcript) async {
  final AnchorResult? match = await searchController.processRealtime(transcript);
  if (match != null) {
    print('⚡ Instant Unique Match Found: Surah ${match.surah}, Ayah ${match.ayah}');
    tracker.setTargetSurah(match.surah);
  }
});
```

---

### 4. Difficulty Presets & Config Tuning

Adjust the dynamic alignment sensitivity at runtime:

```dart
// 1. Easy Mode (Recommended for children, beginners, or noisy environments):
tracker.updateConfig(TrackerConfig.easy());

// 2. Normal Mode (Default balanced calibration):
tracker.updateConfig(TrackerConfig.normal());

// 3. Strict Mode (Recommended for certification / strict exams):
tracker.updateConfig(TrackerConfig.strict());

// 4. Custom Parameter Tuning:
tracker.updateConfig(
  TrackerConfig(
    defaultMaxPathCost: 0.30,        // DTW distance threshold (0.0 to 1.0)
    shortWordPathCost: 0.25,         // Stricter threshold for 1-3 letter words
    acousticConfusionCost: 0.25,     // Cost for phonetically similar Arabic sounds
    harakatDurationSeconds: 0.250,   // Base beat speed in seconds (Tadweer calibration)
    maxSkipWords: 2,                 // Maximum words to lookahead on omission
  ),
);
```

---

## 📚 Complete API Reference

### `ReciteQuran` (Main Facade)
| Method / Getter | Description |
| :--- | :--- |
| `initialize()` | Spawns background Isolates, loads ONNX model, and starts the ASR pipeline. |
| `setTargetSurah(int surah, {int startGlobalWord})` | Loads reference phonemes and sets the tracking target Surah. |
| `jumpToWord(int globalWordIndex)` | Moves tracking cursor directly to a specific word index. |
| `feedAudioChunk(Float32List chunk, {bool isFinal})` | Feeds 16 kHz mono PCM float audio chunks to recognizer. |
| `resetBuffer()` | Clears internal ASR audio buffer. |
| `setTajweedMode(bool active)` | Enables or disables Tajweed duration validation. |
| `updateConfig(TrackerConfig newConfig)` | Updates cost matrix and timing parameters at runtime. |
| `onWordMatched` | `Stream<WordMatchedEvent>` emitting real-time alignment and Tajweed errors. |
| `onTranscript` | `Stream<String>` emitting live phoneme transcriptions. |
| `dispose()` | Gracefully releases all Isolates, audio controllers, and memory. |

### `AudioProcessor`
| Method | Description |
| :--- | :--- |
| `start({required Function(Float32List, bool) onChunk})` | Initializes microphone session (16 kHz, Mono, PCM) and streams audio. |
| `stop()` | Stops recording and releases hardware microphone session. |

---

## 📱 Interactive Sample App

A complete, production-ready Flutter app demonstrating real-time highlighting, Tajweed error modal dialogs, audio waveforms, and auto-scrolling is located in the [`example/`](example/) directory.

```bash
cd example
flutter pub get
dart run recite_quran:model_loader
flutter run -d windows   # or -d android / -d chrome
```

---

## ❓ Troubleshooting & FAQ

### 1. "Missing ONNX model on disk" error
* **Cause:** The neural model has not been downloaded to your project assets.
* **Fix:** Run `dart run recite_quran:model_loader` in your project root and ensure `assets/model/zipformer_p_arabic_v3.int8.onnx` is listed in your `pubspec.yaml`.

### 2. Microphone does not detect Arabic breathy sounds (like `هـ` or `ح`)
* **Cause:** System-level aggressive noise cancellation or echo suppression is filtering speech.
* **Fix:** Use `AudioProcessor` from `recite_quran`. It automatically configures `AVAudioSession` and Android `AudioRecord` with `noiseSuppress: false` and `autoGain: false` to preserve subtle Arabic phonetic characteristics.

### 3. Words match too easily or are too strict
* **Fix:** Adjust difficulty using `tracker.updateConfig(TrackerConfig.easy())` or `TrackerConfig.strict()`.

---

## 🤲 Sacred Covenant & License (لوجه الله تعالى)

### **مَا أَسْأَلُكُمْ عَلَيْهِ مِنْ أَجْرٍ ۖ إِنْ أَجْرِيَ إِلَّا عَلَىٰ رَبِّ الْعَالَمِينَ**

> **THIS PACKAGE AND SOURCE CODE ARE DEDICATED FOR THE SAKE OF ALLAH ALONE.**

Before viewing, using, distributing, or modifying any part of this repository, you explicitly agree to the following covenants:

1. **100% Free to End Users**:
   You may use, study, and redistribute this software or its logic **ONLY** in applications and services that are completely free of charge to all end users forever.
2. **Strict Prohibition on Commercialization & Profit**:
   You are **STRICTLY FORBIDDEN** from selling this application, placing it behind paywalls, subscription models, in-app purchases, charging download fees, monetizing it with advertisements (AdMob, Unity Ads, etc.), or extracting any financial revenue from this codebase, models, or outputs.
3. **Pass-Through**:
   These terms are immutable and strictly pass on to any fork, derivative work, or redistributed component.

---

## 🙏 Acknowledgments

*Alhamdulillah (الحمد لله رب العالمين)* — this work builds upon open-source research and contributions from:
- **[Zipformer Quran Streaming Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother Mustafa
- **[quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript)** by Brother Abdullah Aml
- **[Quranic Universal Aligner (qua_sdk)](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner)** by Brother Ahmad Ibrahim
- **[Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx)** by Next-Gen Kaldi Team

---

<div align="center">

**هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم**

</div>
