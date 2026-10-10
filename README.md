<div align="center">

# وما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ
الحمد لله رب العالمين
بفضل الله و برحمته

# ReciteQuran — اتلو القران
### Real-Time On-Device Quran Karim Recitation Tracking & Tajweed Verification

[![License](https://img.shields.io/badge/License-For%20The%20Sake%20Of%20Allah%20Subhanu-purple.svg)](#-sacred-covenant--license-لوجه-الله-تعالى)
[![pub package](https://img.shields.io/badge/pub.dev-recite__quran%20v1.0.4-blue.svg)](https://pub.dev/packages/recite_quran)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-green.svg)](https://pub.dev/packages/recite_quran)
[![Offline](https://img.shields.io/badge/Offline-100%25%20On--Device-orange.svg)](https://pub.dev/packages/recite_quran)

</div>

You can download the model from repo of my Brother Mustafa : https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3 

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
  - [Tajweed Error Presentation (Pre-built vs Custom UI)](#tajweed-error-presentation-pre-built-vs-custom-ui)
- [Core Features & Guides](#-core-features--guides)
  - [1. Real-Time Word Tracking](#1-real-time-word-tracking-green--red-matching)
  - [2. The Deterministic Tajweed Matrix](#2-the-deterministic-tajweed-matrix)
  - [3. Multi-Riwayah & Multi-Qira'at System (20 Mutawatir Rawis)](#3-multi-riwayah--multi-qiraat-system-20-mutawatir-rawis)
  - [4. Voice Navigation & Ayah Search (6,236 Ayahs)](#4-voice-navigation--ayah-search-6236-ayahs)
  - [5. Best-Drop LCS Word Omission Locator](#5-best-drop-lcs-word-omission-locator)
  - [6. Difficulty Presets & Speed Calibration](#6-difficulty-presets--speed-calibration)
  - [7. On-Demand Neural Model Streaming](#7-on-demand-neural-model-streaming)
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
> **Multi-Riwayat & Qira'at Coverage:**
> - **Native Tajweed Verification**: Fully supported for **Hafs 'an Asim** and **Warsh 'an Nafi'** (with sound-level phoneme datasets powered by `quranic-phonemizer`).
> - **Universal Cross-Riwayah Tracking**: Supported across all **6 canonical counting madhhabs (مذاهب العدّ الستة)** and **20 mutawatir rawis** using the **[Quranpedia Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset for seamless verse following, memorization tracking, and auto-scrolling.

**`recite_quran`** is a high-performance, real-time on-device speech-to-text alignment and Tajweed evaluation engine for Flutter.

* **Continuous Word Tracking**: Zero-lag real-time word alignment powered by semi-global Dynamic Time Warping (DTW) and causal Zipformer CTC acoustic models.
* **Deterministic Tajweed Rules**:
  * **Madd Rules (1–7)**: Validates elongation duration (2, 4, 6 Harakat) against acoustic timestamps, with legitimate Aared Waqf flexibility (Qasr, Tawassut, Tool) and multi-Madd span matching.
  * **Mushaddad Ghunnah (10)**: Verifies 2-Harakah nasal holding on Mushaddad Noon (`نّ`) & Meem (`مّ`).
  * **Shaddah (9)**: Inspects consonant closure duration (~1.5 Harakat) and doubling.
* **Instant Voice Navigation**: Recite any verse or phrase to instantly search across all 6,236 Ayahs.
* **Best-Drop LCS Word Omission Locator**: Pinpoints skipped or forgotten words with $O(N)$ dynamic programming.
* **100% Private & Offline**
* **Cross-Platform Multi-Threading**

---

##  Architecture & Data Pipeline

```
┌─────────────────────────┐
│     Microphone (16kHz)  │
└────────────┬────────────┘
             │ Raw PCM Chunks
             ▼
┌─────────────────────────┐
│     AudioProcessor      │ ──► Raw 16kHz PCM Stream via record (Hardware DSP filters bypassed)
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
  recite_quran: ^1.0.4
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
          print(' ⚠️ Tajweed: ${error.messageAr}');
          print('    Advice: ${error.adviceAr}');
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

> [!TIP]
> **Complete Production App Guide**:
> For a full architecture guide including state management (Riverpod / Bloc / ChangeNotifier), auto-scrolling, and app lifecycle handling, check out **[doc/APP_INTEGRATION_GUIDE.md](doc/APP_INTEGRATION_GUIDE.md)**.

### Word State & Color Resolution
When users recite, each word transitions through a clear 3-color state machine:

| Color | Status | Condition in `WordMatchedEvent` | Meaning |
| :--- | :---: | :--- | :--- |
| 🟢 **Green** | **PASS** | `isRed == false && (tajweedErrors == null \|\| tajweedErrors.isEmpty)` | Pronounced correctly with valid Tajweed duration. |
| 🟡 **Yellow** | **WARNING** | `isRed == false && tajweedErrors.isNotEmpty` | Correct word, but held Madd/Ghunnah too short (`underheld`) or too long (`overheld`). |
| 🔴 **Red** | **FAIL** | `isRed == true` | Word was skipped or mispronounced (omission / substitution). |
| ⚪ **Default** | **UNSPOKEN** | Not yet emitted by stream | Upcoming unrecited Quran text. |

---

### Building a Highlighting Mushaf Widget

Here is how to fetch word models and connect `onWordMatched` to a Flutter `StatefulWidget` using `RichText` and `TextSpan`:

```dart
// 1. Fetch word models for the active Surah (e.g. Surah Al-Fatihah #1):
final List<ContinuousQuranWord> words = repository.getSurahWords(1);

// 2. Pass to your custom Mushaf Widget:
// QuranAyahView(words: words, tracker: tracker);

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
                  if (match != null &&
                      match.tajweedErrors != null &&
                      match.tajweedErrors!.isNotEmpty) {
                    final errors = match.tajweedErrors!
                        .map((m) => ReciterError.fromMap(m))
                        .toList();

                    // Option A: 1-line pre-built Islamic bottom sheet
                    showTajweedErrorSheet(
                      context,
                      errors: errors,
                      wordText: w.uthmani,
                      isArabic: true,
                    );
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

### Tajweed Error Presentation (Pre-built vs Custom UI)

`recite_quran` provides two ways to present Tajweed, Tashkeel, or Pronunciation errors:

#### Option A: Pre-built Elegant Bottom Sheet (`showTajweedErrorSheet`)
Zero boilerplate. Automatically handles dark/light theme, Islamic typography, color-coded badges, and Arabic/English localization:

```dart
import 'package:recite_quran/recite_quran.dart';

void onWordTapped(BuildContext context, WordMatchedEvent event, String wordText) {
  if (event.tajweedErrors == null || event.tajweedErrors!.isEmpty) return;

  final errors = event.tajweedErrors!
      .map((map) => ReciterError.fromMap(map))
      .toList();

  showTajweedErrorSheet(
    context,
    errors: errors,
    wordText: wordText, // Optional word title in header
    isArabic: true,     // Toggle Arabic / English text
  );
}
```

#### Option B: 100% Custom App UI via `ReciterError`
If your application has its own design system, custom Arb localization, or unique layout, `ReciterError` provides both pre-formatted localized helpers and raw numeric telemetry:

```dart
final error = ReciterError.fromMap(errorMap);

// 1. Ready-to-render localized text:
print(error.messageAr); // "نقص في المد المنفصل: تم مد الصوت 0.25ث والحد الأدنى 0.60ث"
print(error.messageEn); // "Underheld Madd Monfasel: held for 0.25s, target is 0.80s"
print(error.adviceAr);  // "أطل زمن مد الصوت بمقدار 4 حركات"
print(error.adviceEn);  // "Hold the vowel elongation for the full 4 beats."

// 2. Raw telemetry for custom calculation / styling:
final ErrorCategory category   = error.errorType;         // .tajweed, .tashkeel, .normal
final TajweedDurationStatus? s = error.durationStatus;    // .underheld, .overheld, .valid
final TajweedRule? rule        = error.expectedRule;      // TajweedRule model
final double? actualSec        = error.actualDuration;    // e.g. 0.25
final double? expectedSec      = error.expectedDuration;  // e.g. 0.80
final String expectedPhoneme   = error.expectedPh;        // e.g. "aa"
final String reciterPhoneme    = error.predictedPh;       // e.g. "a"
```

##### Custom Widget Example:
```dart
Widget buildCustomErrorTile(ReciterError error) {
  final isUnderheld = error.durationStatus == TajweedDurationStatus.underheld;
  
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.amber.shade300),
    ),
    child: Row(
      children: [
        Icon(
          isUnderheld ? Icons.timer_outlined : Icons.timer_off_outlined,
          color: Colors.amber.shade800,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error.messageAr,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                error.adviceAr,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
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

### 2. The Deterministic Tajweed Matrix

When `isTajweed: true` is enabled, each matched word evaluates acoustic duration timestamps against canonical Tajweed rules with zero heuristic guesswork. All rules are bound to explicit compile-time `const AcousticThreshold` matrices.

#### Covered Tajweed Rules:
| Rule ID | Rule Name | Description | Target Harakat | Normal Target (`0.20s`) | Fast Floor (`0.15s`) |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **1** | Normal Madd (`المد الطبيعي`) | Natural 2-beat vowel elongation | 2 Harakat | **0.40s** | `0.075s` (catches dropped vowels) |
| **2** | Monfasel Madd (`المد المنفصل`) | Separated elongation before Hamzah | 4 Harakat | **0.80s** | `0.300s` |
| **3** | Mottasel Madd (`المد المتصل`) | Connected elongation with Hamzah | 4 Harakat | **0.80s** | `0.300s` |
| **4** | Aared Lil-Sukoon (`المد العارض للسكون`) | Flexible pause elongation at Waqf | 2, 4, 6 Harakat | **0.40s – 1.20s** | `0.150s` (allows Qasr/Tawassut/Tool) |
| **5** | Leen Madd (`مد اللين`) | Soft vowel pause elongation at Waqf | 2, 4, 6 Harakat | **0.40s – 1.20s** | `0.150s` |
| **6** | Lazem Madd (`المد اللازم`) | Compulsory 6-beat elongation | 6 Harakat | **1.20s** | `0.600s` |
| **9** | Shaddah (`الشدة`) | Consonant closure & doubling hold | ~1.5 Harakat | **0.30s** | `0.190s` (catches single consonants) |
| **10** | Mushaddad Ghunnah (`النون والميم المشددتان`) | Nasal resonance holding on `نّ` and `مّ` | 2 Harakat | **0.40s** | `0.200s` |

#### Architectural Tajweed Highlights:
* **Multi-Madd Span Matching**: Accurately tracks words containing multiple sequential Madd rules (e.g. Lazem 6 Harakat + Aared in `الضَّآلِّينَ`, or Normal 2 Harakat + Aared in `العَٰلَمِينَ`), binding each span to its dedicated rule.
* **Legitimate Waqf Allowance**: For *Aared Lil-Sukoon*, reciters can legitimately stop with 2 Harakat (*Qasr*), 4 Harakat (*Tawassut*), or 6 Harakat (*Tool*). The engine accommodates this scholarly consensus without emitting false `underheld` errors.
* **Pro-Rated Character Durations**: Distributes multi-character ASR CTC token spikes proportionately across constituent phonemes with zero-duration shields.

---

### 3. Multi-Riwayah & Multi-Qira'at System (20 Mutawatir Rawis)

`recite_quran` features full native datasets for **Hafs** and **Warsh**, plus universal cross-Riwayah verse alignment across all **6 canonical counting madhhabs (مذاهب العدّ الستة)** and **20 mutawatir rawis** powered by the **[Quranpedia Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset:

| Counting System | Total Ayahs | Associated Qira'at & Rawis |
| :--- | :---: | :--- |
| **Kufi (`الكوفي`)** | 6,236 | Asim (Hafs, Shu'ba), Hamza (Khalaf, Khallad), Al-Kisai, Khalaf Al-Ashir |
| **Madani-Last (`المدني الأخير`)** | 6,214 | Nafi' (Warsh, Qalun) |
| **Madani-First (`المدني الأول`)** | 6,214 | Abu Ja'far (Ibn Wardan, Ibn Jammaz) |
| **Makki (`المكي`)** | 6,219 | Ibn Kathir (Al-Bazzi, Qunbul) |
| **Basri (`البصري`)** | 6,204 | Abu 'Amr (Al-Duri, Al-Susi), Ya'qub (Ruways, Rawh) |
| **Dimashqi (`الدمشقي`)** | 6,226 | Ibn 'Amir (Hisham, Ibn Dhakwan) |

#### How to Switch Riwayah in Your App:
```dart
import 'package:recite_quran/recite_quran.dart';

// 1. Switch to Warsh 'an Nafi' (with native Warsh phonemes & Tajweed rules):
final warshMapper = await QiraatAyahMapper.loadForRawi('warsh');
repository.setRiwayah(QuranRiwayah.warsh, warshMapper);
tracker.setTargetSurah(1);

// 2. Query all 20 canonical Riwayat metadata (for dropdowns / selectors):
final List<RiwayaDescriptor> allRiwayat = await RiwayaRegistry.getAllRiwayat();
for (final r in allRiwayat) {
  print('${r.nameAr} (${r.nameEn}) | Ayahs: ${r.totalAyahs} | Tajweed: ${r.tajweedVerified}');
}

// 3. Bidirectional verse lookup:
// In Al-Fatihah, Warsh Ayah 1 corresponds to Hafs Ayahs 1 & 2:
final hafsAyahs = warshMapper.getHafsAyahs(1, 1); // [1, 2]
```

---

### 4. Voice Navigation & Ayah Search (6,236 Ayahs)

Allow your users to recite any verse or phrase to instantly search across all 6,236 Ayahs with sub-millisecond bit-parallel Myers' fuzzy phonetic matching:

* **Real-Time Candidate Streaming**: As the reciter speaks, candidate verses stream live via `onSearchResult` (`Stream<VoiceSearchResult>`) or `currentResult` (`ValueNotifier<VoiceSearchResult?>`).
* **Progressive Narrowing & Instant Jump**: If the spoken words uniquely identify a single verse, `processRealtime` immediately emits `isUnique == true` and returns the `AnchorResult` so your app can auto-navigate without waiting for speech silence.
* **Mutashabihat (متشابهات) Disambiguation**: When an opening phrase matches multiple Ayahs (e.g. 4 similar verses), candidates are presented in real time with Arabic Uthmani preview and match confidence (`96%`). The user can either tap any candidate to jump immediately, or continue reciting the next words to narrow it down to the exact verse.
* **Rich Metadata Enrichment**: Attach your `QuranRepository` to automatically populate Arabic Surah titles (`surahNameAr`), English names (`surahNameEn`), and Uthmani verse texts (`textUthmani`) on each candidate.

#### Quick Implementation:
```dart
import 'package:recite_quran/recite_quran.dart';

final searchController = VoiceSearchController(
  engine: tracker.engine,
  repository: quranRepository, // Enriches candidates with Arabic text & names
);

// Preload the 6,236-Ayah phonetic index in background
await searchController.preloadIndex();

// Start search session (resets engine buffer & clears previous results)
await searchController.startSearch();

// 1. Listen to real-time candidate updates for UI display:
searchController.onSearchResult.listen((VoiceSearchResult result) {
  print('Transcribed: "${result.queryText}"');
  print('Candidates: ${result.candidates.length} (isUnique: ${result.isUnique})');

  for (final match in result.candidates) {
    print('• ${match.surahNameAr} Ayah ${match.ayah} (${(match.score * 100).toInt()}%)');
    print('  ${match.textUthmani}');
  }
});

// 2. Feed live ASR speech chunks & auto-jump on unique match:
tracker.onTranscript.listen((partialText) async {
  final AnchorResult? uniqueMatch = await searchController.processRealtime(partialText);
  if (uniqueMatch != null) {
    print('⚡ Unique Verse Identified! Navigating to Surah ${uniqueMatch.surah}, Ayah ${uniqueMatch.ayah}');
    await tracker.setTargetSurah(uniqueMatch.surah);
  }
});

// 3. User taps a candidate or stops search manually:
void onCandidateSelected(int surah, int ayah) async {
  await tracker.setTargetSurah(surah);
}
```

---

### 5. Best-Drop LCS Word Omission Locator

Accurately pinpoint dropped or forgotten words during recitation using the $O(N)$ 2-row dynamic programming Best-Drop algorithm (derived from `tasmee3-muaalem-findings` benchmark research):

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

### 6. Difficulty Presets & Speed Calibration

Calibrate recitation speed and alignment sensitivity dynamically at runtime:

```dart
// 1. Slow / Tahqiq / Tartil (0.250s / Harakah - For slow study, children, beginners):
tracker.updateConfig(TrackerConfig.strict().copyWith(
  recitationSpeed: RecitationSpeed.slow,
));

// 2. Normal / Tadweer (0.200s / Harakah - Default balanced calibration):
tracker.updateConfig(TrackerConfig.normal().copyWith(
  recitationSpeed: RecitationSpeed.normal,
));

// 3. Fast / Hadr / Muraja'ah (0.150s / Harakah - For rapid memorization revision):
tracker.updateConfig(TrackerConfig.easy().copyWith(
  recitationSpeed: RecitationSpeed.fast,
));
```

---

### 7. On-Demand Neural Model Streaming

Avoid adding ~72 MB to your initial app bundle download by streaming the INT8 ONNX acoustic model on first launch with real-time progress callbacks:

```dart
import 'package:recite_quran/recite_quran.dart';

final downloader = ModelDownloader();

if (!await downloader.isModelReady()) {
  await downloader.downloadAssets(
    onProgress: (double progress, String status) {
      print('$status: ${(progress * 100).toInt()}%');
    },
  );
}

// Pass downloaded directory to SherpaEngine:
final modelDir = await downloader.getModelDirectoryPath();
final engine = SherpaEngine(assetOverrideDir: modelDir);
```

---


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

### `ReciterError` (Tajweed & Speech Error Model)
| Property / Method | Type | Description |
| :--- | :--- | :--- |
| `fromMap(map)` | `ReciterError` | Deserializes from a raw entry in `event.tajweedErrors`. |
| `toMap()` | `Map<String, dynamic>` | Serializes to self-documenting JSON-compatible map. |
| `errorType` | `ErrorCategory` | `.tajweed` (duration/holding), `.tashkeel` (vowel mark), or `.normal` (pronunciation). |
| `speechErrorType` | `SpeechErrorType` | `.replace` (substitution), `.delete` (dropped/omitted), `.insert` (added). |
| `durationStatus` | `TajweedDurationStatus?` | `.underheld` (held too short), `.overheld` (held too long), `.valid`. |
| `expectedRule` | `TajweedRule?` | The formal Tajweed rule definition (`MaddRule`, `GhunnahRule`, `ShaddahRule`). |
| `actualDuration` | `double?` | Acoustic speech duration measured in seconds from ASR neural timestamps. |
| `expectedDuration` | `double?` | Canonical target duration threshold in seconds for active recitation speed. |
| `messageAr` / `messageEn` | `String` | Ready-to-render localized friendly explanations for users. |
| `adviceAr` / `adviceEn` | `String` | Actionable pedagogical advice on how to correct the recitation. |

### Pre-built UI (`TajweedErrorSheet`)
| Function / Widget | Description |
| :--- | :--- |
| `showTajweedErrorSheet(context, {errors, wordText, isArabic})` | Displays a ready-to-use Islamic styled modal bottom sheet with automatic dark/light theme support. |
| `TajweedErrorSheet` | The standalone widget that can be embedded into custom sheets, dialogs, or side panels. |

### `VoiceSearchController` (Voice Navigation)
| Property / Method | Type | Description |
| :--- | :--- | :--- |
| `preloadIndex()` | `Future<void>` | Loads the 6,236-Ayah bit-parallel phonetic index into memory asynchronously. |
| `startSearch()` | `Future<void>` | Resets audio engine buffers and initializes the live search session. |
| `processRealtime(text)` | `Future<AnchorResult?>` | Evaluates streaming speech chunks; emits live candidates and returns `AnchorResult` when uniquely identified. |
| `stopSearch(finalText)` | `Future<AnchorResult?>` | Finalizes search pass and returns the top-ranked `AnchorResult` with all candidates attached. |
| `searchCandidates(query)` | `Future<VoiceSearchResult?>` | Standalone query method returning all ranked candidates for a given text string. |
| `onSearchResult` | `Stream<VoiceSearchResult>` | Broadcast stream emitting ranked candidate verses on each speech increment. |
| `currentResult` | `ValueNotifier<VoiceSearchResult?>` | Observable holding the latest live search candidates and uniqueness status. |
| `isIndexLoading` | `ValueNotifier<bool>` | Observable boolean tracking whether the phonetic asset index is currently loading. |

### `VoiceSearchResult` & `AyahSearchMatch`
| Property | Type | Description |
| :--- | :--- | :--- |
| `result.candidates` | `List<AyahSearchMatch>` | Ranked list of verses matching the query, ordered by edit distance. |
| `result.isUnique` | `bool` | `true` when the search has narrowed down definitively to exactly one target Ayah. |
| `result.topMatch` | `AyahSearchMatch?` | The best-matching candidate verse in the current pass. |
| `match.surah` / `match.ayah` | `int` | 1-indexed Surah and Ayah numbers. |
| `match.score` | `double` | Normalized match confidence score (`0.0` to `1.0`). |
| `match.distance` | `int` | Levenshtein edit distance between the normalized query and reference phonemes. |
| `match.surahNameAr` / `match.surahNameEn` | `String?` | Arabic and English Surah titles (populated when `QuranRepository` is provided). |
| `match.textUthmani` | `String?` | Full Arabic Uthmani text of the candidate verse. |

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

## External Projects

*Alhamdulillah (الحمد لله رب العالمين)* — بفضل الله و برحمته وحده

- **[Zipformer Quran Acoustic Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother Mustafa & **[QuranLab](https://huggingface.co/Quran-Lab)** for the Zipformer causal streaming ASR model training and acoustic phoneme tokenization.
- **[quranic-phonemizer](https://github.com/M97Chahboun/quranic-phonemizer)** for generating authentic native Riwayat phonetic datasets (e.g. Warsh 'an Nafi', 6,214 ayahs), sound-level Tajweed rule annotations, and CTC-compatible acoustic phoneme alignments.
- **[Quranpedia (موسوعة القرآن)](https://quranpedia.net)** for the verified **[Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset linking all 6 counting systems and 20 rawis to Kufi numbering.
- **[quran-transcript](https://github.com/obadx/quran-transcript)** by Brother Abdullah Aml.

- **[tasmee3-muaalem-findings / Seraj]** (Dr. Omar Abu Hafs) for the Best-Drop LCS word omission detection research, formulations, and benchmark datasets.
- **[Quran Universal Aligner (qua_sdk)]** by Brother Ahmad Ibrahim.

### 📱 Applications Powered by ReciteQuran
- **[Tathbeet (تثبيت)](https://app.tathbeet.space)** — Comprehensive Quran memorization and review platform featuring authentic multi-Riwayah recitation tracking and real-time Tajweed evaluation.


---

<div align="center">

**هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم**

</div>
