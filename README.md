<div align="center">

# وما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ
الحمد لله
# ReciteQuran — اتلو القران
### Real-Time On-Device Quran Karim Recitation Tracking & Tajweed Verification



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
- [ UI Integration & Color Highlighting (Green / Yellow / Red)](#-ui-integration--color-highlighting-green--yellow--red)
  - [Word State & Color Resolution](#word-state--color-resolution)
  - [Building a Highlighting Mushaf Widget](#building-a-highlighting-mushaf-widget)
  - [Tajweed Error BottomSheet / Dialog](#tajweed-error-bottomsheet--dialog)
- [Core Features & Guides](#-core-features--guides)
  - [1. Real-Time Word Tracking](#1-real-time-word-tracking-green--red-matching)
  - [2. Deterministic Tajweed Verification](#2-deterministic-tajweed-verification)
  - [3. Voice Navigation & Ayah Search (6,236 Ayahs)](#3-voice-navigation--ayah-search-6236-ayahs)
  - [4. Difficulty Presets & Config Tuning](#4-difficulty-presets--config-tuning)
- [Complete API Reference](#-complete-api-reference)
- [ Example App Code Architecture](#-example-app-code-architecture)
- [Troubleshooting & FAQ](#-troubleshooting--faq)
- [Sacred Covenant & License (لوجه الله تعالى)](#-sacred-covenant--license-لوجه-الله-تعالى)
- [Acknowledgments](#-acknowledgments)

---

## 🌟 Overview

> [!IMPORTANT]
> **Scholarly & Pedagogical Note (تنبيه وأمانة شرعية):**
> **This recitation engine is an assistive algorithmic aid designed to facilitate revision, memorization practice, and self-testing.**
> It **can never substitute** for learning directly from and reciting to a qualified, certified Sheikh (*المشافهة والتلقي على شيخ متقن ومجاز بالسند المتصل*). Verifying letter articulation points (*مخارج الحروف*), subtle oral characteristics (*صفات الحروف*), and sound Hifdh must always be confirmed through direct recitation to authorized scholars.

> [!NOTE]
> **Important Architectural Note on Riwayat & Qira'at Support:**
> The neural acoustic Zipformer model (`Quran-Lab/zipformer_p-arabic-v3`) was trained exclusively on Hafs recitation audio. When users recite according to other Riwayat (e.g. Warsh, Qalun, Al-Duri, etc.), the engine uses the canonical **[Quranpedia Qira'at Ayah Mapping dataset](https://github.com/quranpedia/qiraat-ayah-map)** to follow along, track memorization progress, and enable hands-free auto-scrolling and recall. Deterministic Tajweed rule verification is disabled for non-Hafs recitations until dedicated acoustic models are trained for each Riwaya's specific Tajweed rules.


**`recite_quran`** is a high-performance, real-time on-device speech-to-text alignment and Tajweed evaluation engine for Flutter.

*  **Continuous Word Tracking**: Zero-lag real-time word alignment powered by semi-global Dynamic Time Warping (DTW) and causal Zipformer CTC acoustic models.
* **Deterministic Tajweed Rules**:
  * **Madd Rules (1–7)**: Validates elongation duration (2, 4, 6 Harakat) against acoustic timestamps.
  * **Mushaddad Ghunnah (10)**: Verifies 2-Harakah nasal holding on Mushaddad Noon (`نّ`) & Meem (`مّ`).
  * **Shaddah (9)**: Inspects consonant closure duration (~1.5 Harakat) and doubling.
*  **Instant Voice Navigation**: Recite any verse or phrase to instantly search across all Ayahs.
*  **100% Private & Offline**
*  **Cross-Platform Multi-Threading**

---

##  Architecture & Data Pipeline

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
│ Green / Red / Yellow      │      │ Madd, Ghunnah, Shaddah    │
└───────────────────────────┘      └───────────────────────────┘
```

---


##  Installation & Model Setup

### 1. Add Dependency
Add `recite_quran` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  recite_quran: ^1.0.1
```

### 2. Download the Neural Model
The neural acoustic model (`zipformer_p_arabic_v3.int8.onnx`, ~72MB) is hosted on GitHub Releases to keep the initial pub download lightweight.

Run this single setup command from your Flutter project root:

```bash
dart run recite_quran:download_model
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
      print(' Word #${event.wordId} skipped or mispronounced');
    } else {
      print(' Matched Word #${event.wordId} (Score: ${(event.score * 100).toInt()}%)');
      
      // Inspect Tajweed duration diagnostics (if any)
      if (event.tajweedErrors != null && event.tajweedErrors!.isNotEmpty) {
        for (final errorMap in event.tajweedErrors!) {
          final error = ReciterError.fromMap(errorMap);
          print(' Tajweed rule: ${error.expectedRule?.name.ar} | Status: ${error.durationStatus}');
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

##  UI Integration & Color Highlighting (Green / Yellow / Red)

### Word State & Color Resolution
When users recite, each word transitions through a clear 3-color state machine:

| Color | Status | Condition in `WordMatchedEvent` | Meaning |
| :--- | :---: | :--- | :--- |
| 🟢 **Green** | **PASS** | `isRed == false && (tajweedErrors == null \|\| tajweedErrors.isEmpty)` | Pronounced correctly with valid Tajweed duration. |
| 🟡 **Yellow** | **WARNING** | `isRed == false && tajweedErrors.isNotEmpty` | Correct word, but held Madd/Ghunnah too short (`defect`) or too long (`surplus`). |
| 🔴 **Red** | **FAIL** | `isRed == true` | Word was skipped or mispronounced (omission / substitution). |
| ⚪ **Default** | **UNSPOKEN** | Not yet emitted by stream | Upcoming unrecited Quran text. |

---

### Building a Highlighting Mushaf Widget

Here is how to connect `onWordMatched` to a Flutter `StatefulWidget` using `RichText` and `TextSpan`:

```dart
class QuranAyahView extends StatefulWidget {
  final List<ContinuousQuranWord> words;
  final ReciteQuran tracker;

  const QuranAyahView({super.key, required this.words, required this.tracker});

  @override
  State<QuranAyahView> createState() => _QuranAyahViewState();
}

class _QuranAyahViewState extends State<QuranAyahView> {
  final Map<int, WordMatchedEvent> _matchedWords = {};

  @override
  void initState() {
    super.initState();
    widget.tracker.onWordMatched.listen((event) {
      setState(() {
        _matchedWords[event.wordId] = event;
      });
    });
  }

  Color _resolveColor(int wordIndex) {
    final match = _matchedWords[wordIndex];
    if (match == null) return Colors.black87; // Unspoken word
    if (match.isRed) return Colors.red;        // 🔴 Skipped / Mispronounced
    if (match.tajweedErrors != null && match.tajweedErrors!.isNotEmpty) {
      return Colors.amber.shade700;           // 🟡 Tajweed Duration Warning
    }
    return Colors.green.shade600;              // 🟢 Perfect Match
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RichText(
        text: TextSpan(
          children: widget.words.map((w) {
            return TextSpan(
              text: '${w.uthmani} ',
              style: TextStyle(
                fontFamily: 'HafsSmart',
                fontSize: 26,
                color: _resolveColor(w.globalIndex),
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  final match = _matchedWords[w.globalIndex];
                  if (match != null && match.tajweedErrors != null && match.tajweedErrors!.isNotEmpty) {
                    _showTajweedErrorDialog(context, match.tajweedErrors!);
                  }
                },
            );
          }).toList(),
        ),
      ),
    );
  }
}
```

---

### Tajweed Error BottomSheet / Dialog

When a user taps a 🟡 **Yellow word**, display the exact Tajweed rule breakdown:

```dart
void _showTajweedErrorDialog(BuildContext context, List<Map<String, dynamic>> errors) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تنبيه تجويد (Tajweed Notice)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...errors.map((errorMap) {
              final error = ReciterError.fromMap(errorMap);
              final String statusText = error.durationStatus == TajweedDurationStatus.defect
                  ? 'نقص في المد / الغنة (Held too short)'
                  : 'زيادة في المد / الغنة (Held too long)';
              return ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                title: Text(error.expectedRule?.name.ar ?? 'حكم تجويد'),
                subtitle: Text('$statusText\nExpected: ${error.expectedDuration}s | Actual: ${error.actualDuration}s'),
              );
            }),
          ],
        ),
      );
    },
  );
}
```

---

##  Core Features & Guides

### 1. Real-Time Word Tracking (Green / Red Matching)

The tracking engine processes the user's recitation sequentially using semi-global DTW:
* **Green Match (`event.isRed == false`)**: The spoken word matched the reference within the configured threshold.
* **Red Match (`event.isRed == true`)**: The user skipped one or more words or made a substantial phonetic mistake.
* **Anchor Advancement**: When a match occurs, the alignment window automatically advances to the next word.
* **Partial Words**: If a user is currently pronouncing a long word, the engine holds state until the full word is articulated.

---

### 2. Deterministic Tajweed Verification

When `isTajweed: true` is enabled, each matched word evaluates acoustic duration timestamps against canonical Tajweed rules:

#### Covered Tajweed Rules:
| Rule ID | Rule Name | Description | Target Harakat | Normal Target (`0.20s`) |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Normal Madd (`المد الطبيعي`) | Natural 2-beat vowel elongation | 2 Harakat | **0.40s** |
| **2** | Monfasel Madd (`المد المنفصل`) | Separated elongation before Hamzah | 4 Harakat | **0.80s** |
| **3** | Mottasel Madd (`المد المتصل`) | Connected elongation with Hamzah | 4 Harakat | **0.80s** |
| **4** | Aared Lil-Sukoon (`المد العارض للسكون`) | Optional pause elongation | 4 Harakat | **0.80s** |
| **5** | Leen Madd (`مد اللين`) | Soft vowel pause elongation | 4 Harakat | **0.80s** |
| **6** | Lazem Madd (`المد اللازم`) | Compulsory 6-beat elongation | 6 Harakat | **1.20s** |
| **9** | Shaddah (`الشدة`) | Consonant closure & doubling hold | ~1.5 Harakat | **0.30s** |
| **10** | Mushaddad Ghunnah (`النون والميم المشددتان`) | Nasal resonance holding on `نّ` and `مّ` | 2 Harakat | **0.40s** |

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

Adjust the dynamic alignment sensitivity and Harakat duration at runtime:

```dart
// 1. Easy Mode (0.150s / Harakah - For children, beginners, or noisy environments):
tracker.updateConfig(TrackerConfig.easy());

// 2. Normal Mode (0.200s / Harakah - Default balanced calibration):
tracker.updateConfig(TrackerConfig.normal());

// 3. Strict Mode (0.250s / Harakah - For certification / strict exams):
tracker.updateConfig(TrackerConfig.strict());

// 4. Custom Parameter Tuning:
tracker.updateConfig(
  TrackerConfig(
    defaultMaxPathCost: 0.30,        // DTW distance threshold (0.0 to 1.0)
    shortWordPathCost: 0.25,         // Stricter threshold for 1-3 letter words
    acousticConfusionCost: 0.25,     // Cost for phonetically similar Arabic sounds
    harakatDurationSeconds: 0.200,   // Base beat speed in seconds (200ms)
    maxSkipWords: 2,                 // Maximum words to lookahead on omission
  ),
);
```

---

---

### 5. Best-Drop LCS Word Omission Locator

Accurately pinpoint dropped or forgotten words during recitation using the $O(N)$ 2-row dynamic programming Best-Drop algorithm:

```dart
import 'package:recite_quran/recite_quran.dart';

final phonemesPerWord = [
  'ءِننننَ',     // [0]
  'شَاانِءَكَ', // [1]
  'هُوَ',       // [2] (omitted by reciter)
  'لءَبڇتَر',   // [3]
];
final emittedPhonemes = 'ءِننننَشَاانِءَكَلءَبڇتَر';

final OmissionResult result = LcsOmissionDetector.detectOmission(
  phonemesPerWord: phonemesPerWord,
  emittedPhonemes: emittedPhonemes,
);

if (result.isOmissionDetected) {
  print('⚠️ Omitted Word Index: ${result.omittedWordIndex}'); // Index 2 ("هُوَ")
  print('Shortfall characters: ${result.shortfall}');
  print('Confidence Gap: ${result.confidenceGap}');
}
```

---

### 6. Comprehensive Cross-Riwaya Ayah Alignment (`QiraatAyahMapper`)

Seamlessly track reciters across all **6 canonical counting madhhabs (مذاهب العدّ الستة)** and **20 mutawatir rawis** against Hafs acoustic models using verified **[Quranpedia Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** data:

| Counting System | Total Ayahs | Associated Qira'at & Rawis |
| :--- | :--- | :--- |
| **Kufi (`الكوفي`)** | 6,236 | Asim (Hafs, Shu'ba), Hamza (Khalaf, Khallad), Al-Kisai, Khalaf Al-Ashir |
| **Madani-Last (`المدني الأخير`)** | 6,214 | Nafi' (Warsh, Qalun) |
| **Madani-First (`المدني الأول`)** | 6,214 | Abu Ja'far (Ibn Wardan, Ibn Jammaz) |
| **Makki (`المكي`)** | 6,219 | Ibn Kathir (Al-Bazzi, Qunbul) |
| **Basri (`البصري`)** | 6,204 | Abu 'Amr (Al-Duri, Al-Susi), Ya'qub (Ruways, Rawh) |
| **Dimashqi (`الدمشقي`)** | 6,226 | Ibn 'Amir (Hisham, Ibn Dhakwan) |

```dart
import 'package:recite_quran/recite_quran.dart';

// 1. Automatically load mapping table for any Rawi by name (cached in-memory):
final warshMapper = await QiraatAyahMapper.loadForRawi('warsh');
final duriMapper = await QiraatAyahMapper.loadForRawi('duri');

// 2. Kufan recitations (e.g. Hafs, Shu'ba) require zero disk load (O(1) identity):
final hafsMapper = QiraatAyahMapper.kufiIdentity();

// 3. Bidirectional verse lookups:
// In Al-Fatiha, Warsh Ayah 1 covers Hafs Ayahs 1 & 2:
final hafsAyahs = warshMapper.getHafsAyahs(1, 1); // [1, 2]
final status = warshMapper.getMappingStatus(1, 1); // 'covers_multiple'

// Reverse lookup from Hafs to Warsh:
final warshAyahs = warshMapper.getSourceAyahs(1, 3); // [2]
```

---

### 7. Built-in On-Demand Model Downloader

Avoid adding ~85 MB into the initial app bundle by streaming neural model assets on demand with progress callbacks:

```dart
import 'package:recite_quran/recite_quran.dart';

final downloader = ModelDownloader();

if (!await downloader.isModelReady()) {
  await downloader.downloadAssets(
    onProgress: (progress, status) {
      print('$status: ${(progress * 100).toInt()}%');
    },
  );
}

// Pass downloaded directory to SherpaEngine:
final modelDir = await downloader.getModelDirectoryPath();
final engine = SherpaEngine(assetOverrideDir: modelDir);
```


##  Complete Reference

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

### `WordMatchedEvent`
| Property | Type | Description |
| :--- | :--- | :--- |
| `wordId` | `int` | Global 0-indexed word position within the active Surah. |
| `score` | `double` | Acoustic match confidence score (`0.0` to `1.0`). |
| `cleanAsr` | `String` | Matched phoneme substring produced by ASR. |
| `isRed` | `bool` | `true` if the word was skipped or mispronounced. |
| `isNeutral` | `bool` | `true` if the word was neutrally skipped. |
| `tajweedErrors` | `List<Map<String, dynamic>>?` | Detailed Tajweed timing issues for this word. |

---

## 📁 Example App Code Architecture

The complete, production-ready sample application is located in the [`example/`](example/) directory:

| File in `example/` | What it demonstrates |
| :--- | :--- |
| [`example/lib/ui/tracking_screen.dart`](example/lib/ui/tracking_screen.dart) | Full screen layout with mic button, auto-scrolling, and Surah picker. |
| [`example/lib/ui/widgets/helpers/verse_span_builder.dart`](example/lib/ui/widgets/helpers/verse_span_builder.dart) | High-performance `InlineSpan` builder with Green/Yellow/Red color resolution. |
| [`example/lib/ui/widgets/dialogs/error_detail_dialog.dart`](example/lib/ui/widgets/dialogs/error_detail_dialog.dart) | Interactive Tajweed diagnostic bottom-sheet popup. |
| [`example/lib/ui/widgets/mic_bar.dart`](example/lib/ui/widgets/mic_bar.dart) | Audio waveform visualizer and push-to-talk voice search. |

```bash
cd example
flutter pub get
dart run recite_quran:download_model
flutter run -d windows   # or -d android / -d chrome
```

---

## ❓ Troubleshooting

### 1. "Missing ONNX model on disk" error
* **Cause:** The neural model has not been downloaded to your project assets.
* **Fix:** Run `dart run recite_quran:download_model` in your project root and ensure `assets/model/zipformer_p_arabic_v3.int8.onnx` is listed in your `pubspec.yaml`.

### 2. Microphone does not detect Arabic breathy sounds (like `هـ` or `ح`)
* **Cause:** System-level aggressive noise cancellation or echo suppression is filtering speech.
* **Fix:** Use `AudioProcessor` from `recite_quran`. It automatically configures `AVAudioSession` and Android `AudioRecord` with `noiseSuppress: false` and `autoGain: false` to preserve subtle Arabic phonetic characteristics.

### 3. Words match too easily or are too strict
* **Fix:** Adjust difficulty using `tracker.updateConfig(TrackerConfig.easy())` or `TrackerConfig.strict()`.

---

## License (لوجه الله تعالى)

### **مَا أَسْأَلُكُمْ عَلَيْهِ مِنْ أَجْرٍ ۖ إِنْ أَجْرِيَ إِلَّا عَلَىٰ رَبِّ الْعَالَمِينَ**

> **THIS PACKAGE AND SOURCE CODE ARE DEDICATED FOR THE SAKE OF ALLAH ALONE.**

Before viewing, using, distributing, or modifying any part of this repository, you explicitly agree to the following covenants:

1. **100% Free to End Users**:
   You may use, study, and redistribute this software or its logic **ONLY** in applications and services that are completely free of charge to all end users forever.
2. **Strict Prohibition on Commercialization & Profit**:
   You are **STRICTLY FORBIDDEN** from selling this application, placing it behind paywalls, subscription models, in-app purchases, charging download fees, monetizing it with advertisements (AdMob, Unity Ads, etc.), or extracting any financial revenue from this codebase, models, or outputs.
3. **Pass-Through**:
   These terms are immutable and strictly pass on to any fork, derivative work, or redistributed component.

---------

## 🤝 Acknowledgments & External Projects

*Alhamdulillah (الحمد لله رب العالمين)* — this package stands upon the shoulders of brilliant Islamic tech initiatives, researchers, and open-source projects:

- **[Zipformer Quran Acoustic Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother Mustafa & **[QuranLab](https://huggingface.co/Quran-Lab)** for the Zipformer causal streaming ASR model training and acoustic phoneme tokenization.
- **[Quranpedia (موسوعة القرآن)](https://quranpedia.net)** for the verified **[Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset linking all 6 counting systems and 20 rawis to Kufi numbering.
- **[tasmee3-muaalem-findings / Seraj](https://github.com/omar-abuhfs)** (Dr. Omar Abu Hafs) for the Best-Drop LCS word omission detection research, formulations, and benchmark datasets.
- **[Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx)** by the Next-gen Kaldi team for real-time on-device speech recognition inference.
- **[quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript)** by Brother Abdullah Aml.
- **[Quranic Universal Aligner (qua_sdk)](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner)** by Brother Ahmad Ibrahim.

---

<div align="center">

**هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم**

</div>
