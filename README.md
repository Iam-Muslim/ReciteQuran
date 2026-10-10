<div align="center">

# وَمَا أَسْأَلُكُمْ عَلَيْهِ مِنْ أَجْرٍ ۖ إِنْ أَجْرِيَ إِلَّا عَلَىٰ رَبِّ الْعَالَمِينَ
### الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ • بِفَضْلِ اللَّهِ وَبِرَحْمَتِهِ

# ReciteQuran — اتلو القرآن
### Real-Time On-Device Quran Recitation Tracking, Tajweed Verification & Voice Navigation for Flutter

[![License](https://img.shields.io/badge/License-For%20The%20Sake%20Of%20Allah%20Subhanu-purple.svg)](#-sacred-covenant--license-لوجه-الله-تعالى)
[![pub package](https://img.shields.io/badge/pub.dev-recite__quran%20v1.0.4-blue.svg)](https://pub.dev/packages/recite_quran)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-green.svg)](https://pub.dev/packages/recite_quran)
[![Offline](https://img.shields.io/badge/Offline-100%25%20On--Device-orange.svg)](https://pub.dev/packages/recite_quran)

*Neural acoustic model mirror:* [HuggingFace QuranLab Zipformer-v3](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3) (by Brother Mustafa)

</div>

---

> [!IMPORTANT]
> **Scholarly & Pedagogical Covenant (تنبيه وأمانة شرعية):**
> **This engine is an assistive algorithmic aid designed to facilitate revision, memorization practice, and self-testing.**
> It **can never substitute** for learning directly from and reciting to a qualified, certified Sheikh (*المشافهة والتلقي على شيخ متقن ومجاز بالسند المتصل*). Verifying letter articulation points (*مخارج الحروف*), subtle oral characteristics (*صفات الحروف*), and sound Hifdh must always be confirmed through direct recitation to authorized scholars.

---

## 📑 Table of Contents

- [⚡ 60-Second Quick Start](#-60-second-quick-start)
- [🏗️ System Architecture](#️-system-architecture)
- [  Core Features (With Deep Dive Guides)](#-core-features-with-deep-dive-guides)
  - [1. Hands-Free Dictation & Auto-Scroll](#1-hands-free-dictation--auto-scroll)
  - [2. Real-Time Deterministic Tajweed Matrix](#2-real-time-deterministic-tajweed-matrix)
  - [3. "Recite to Navigate" Voice Search](#3-recite-to-navigate-voice-search)
  - [4. Tarteel-Style Hifdh Memorization Mode](#4-tarteel-style-hifdh-memorization-mode)
  - [5. Production Audio Pipeline & Microphone Hardware](#5-production-audio-pipeline--microphone-hardware)
  - [6. Authentic Mus'haf UI & Page Layout](#6-authentic-mushaf-ui--page-layout)
  - [7. Multi-Riwayah & 20 Canonical Rawis](#7-multi-riwayah--20-canonical-rawis)
  - [8. Neural Model Deployment (On-Demand vs Bundled)](#8-neural-model-deployment-on-demand-vs-bundled)
- [🎨 Color Highlighting & Event Protocol](#-color-highlighting--event-protocol)
- [⚙️ Configuration Presets (`TrackerConfig`)](#️-configuration-presets-trackerconfig)
- [📚 Full Documentation Suite](#-full-documentation-suite)
- [📁 Example Application](#-example-application)
- [  Sacred Covenant & License (لوجه الله تعالى)](#️-sacred-covenant--license-لوجه-الله-تعالى)
- [🤲 Acknowledgments](#-acknowledgments)

---

## ⚡ 60-Second Quick Start

Get live word tracking running in your Flutter app in four simple steps:

### 1. Add Dependency
```yaml
dependencies:
  recite_quran: ^1.0.4
```

### 2. Download Neural Model
```bash
dart run recite_quran:download_model
```

### 3. Initialize & Stream Audio
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Quran repository & load Surat Al-Fatiha (Surah 1)
  final repository = QuranRepository(QuranMetadataService());
  await repository.loadSurahAsync(1);

  // 2. Initialize tracking engine (enableAutoReanchor is strongly recommended for reader apps!)
  final tracker = ReciteQuran(
    repository: repository,
    config: const TrackerConfig(
      enableEarlyMatching: true,
      enableAutoReanchor: true, // Strongly recommended: auto-recovers position hands-free!
    ),
    isTajweed: false, // Dictation / Tilawah mode
  );
  await tracker.initialize();
  tracker.setTargetSurah(1);

  // 3. Listen to real-time word matches
  tracker.onWordMatched.listen((event) {
    if (event.isGreen) {
      print('🟢 Word ${event.wordId} matched correctly!');
    } else if (event.isRed) {
      print('🔴 Word ${event.wordId} was skipped.');
    }
  });

  // 4. Stream audio from microphone
  final audio = AudioProcessor();
  await audio.start(
    onChunk: (Float32List chunk, bool isFinal) {
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    },
  );
}
```

👉 **Need state management or Mus'haf UI?** [Read the Complete App Integration Guide →](doc/APP_INTEGRATION_GUIDE.md)

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Microphone Audio Stream                     │
│    Raw 16kHz Mono 16-bit PCM (Hardware DSP Filters Bypassed) │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 SherpaEngine (Streaming ASR)                │
│       Onnx Zipformer acoustic model running in C++ / FFI     │
│       Emits phonetic token stream: [بِ], [س], [مِ], [للَ]... │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│        PhonemeAlignmentIsolate (Background Dart Isolate)    │
│  - Executes 2D Dynamic Programming alignment                │
│  - Evaluates deterministic Tajweed acoustic matrix          │
│  - Emits real-time WordMatchedEvent (Zero UI jank)          │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
 ┌──────────────────────┐              ┌──────────────────────┐
 │ Hands-Free Dictation │              │ Tajweed Evaluation   │
 │ Early Matching Commits│              │ Madd & Ghunnah Spans │
 └──────────┬───────────┘              └──────────┬───────────┘
            │                                     │
            └──────────────────┬──────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       Flutter UI Layer                      │
│   🟢 Green (Read) | 🟡 Yellow (Tajweed Slip) | 🔴 Red (Skip)│
│   Smooth auto-scroll keeps active word centered at 60 FPS   │
└─────────────────────────────────────────────────────────────┘
```

---

##   Core Features (With Deep Dive Guides)

### 1. Hands-Free Dictation & Auto-Scroll
Designed for seamless, responsive page reading:
- **Early Matching**: Commits words as soon as root consonants match without waiting for trailing vowels or pauses.
- **Automatic Re-anchoring (`enableAutoReanchor: true`)**: If a user skips ahead or jumps verses, the engine detects the stall and automatically re-anchors the Mus'haf to their active position hands-free.
- **💡 Author's Note & Strong Recommendation (Enable It!)**:
  > `enableAutoReanchor` defaults to `false` in `TrackerConfig` purely out of conservative caution—the author didn't want unexpected jumps during strict memorization exams or edge cases that had not yet undergone massive real-world testing.
  >
  > **However, for any Quran reading, Tilawah, or consumer Mus'haf app, you are STRONGLY ENCOURAGED to enable it (`enableAutoReanchor: true`)!**
  >
  > The engine is protected by an **Anti-Ambiguity Guard** ($\Delta\text{dist} < 3$) and multi-stage window probing, ensuring that false jumps are suppressed even across repeated refrains (*فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ* in Surah Ar-Rahman). Enjoy the magical hands-free experience!

👉 [**Deep Dive: Dictation Integration Guide →**](doc/DICTATION_SYSTEM_GUIDE.md)

---

### 2. Real-Time Deterministic Tajweed Matrix
Evaluates reciter pronunciation against an acoustic matrix:
- **Madd Rules (1–7)**: Validates elongation duration (2, 4, 5, 6 Harakat) with legitimate *Al-Madd Al-Aared Lissukun* Waqf flexibility (Qasr, Tawassut, Tool).
- **Mushaddad Ghunnah**: Enforces 2-Harakah nasal holding on Noon (`نّ`) and Meem (`مّ`).
- **Shaddah**: Measures consonant closure duration (~1.5 Harakat) and doubling.
- **Pedagogical Feedback**: Emits bilingual explanations (Arabic & English) via `ErrorExplainer` and the pre-built `TajweedErrorSheet`.

👉 [**Deep Dive: Tajweed Verification Guide →**](doc/TAJWEED_GUIDE.md)

---

### 3. "Recite to Navigate" Voice Search
Search across all **6,236 Ayahs** in $< 5\text{ ms}$:
- **Myers 64-Bit Bit-Parallel Search**: Scans the entire normalized Quran on background threads with zero UI freeze.
- **Prefix Stripping**: Intelligently removes *Isti'adha* and *Basmalah* if recited before the verse.
- **Auto-Navigation**: Emits live candidate verses and navigates immediately upon detecting a unique match.

👉 [**Deep Dive: Voice Search & Ayah Finder Guide →**](doc/VOICE_SEARCH_GUIDE.md)

---

### 4. Tarteel-Style Hifdh Memorization Mode
Build a full digital memorization companion:
- **Blind Recitation**: Words remain masked (`•••••`) or blurred until the reciter pronounces them correctly.
- **Progressive Revealing**: Words animate into view in Green upon correct recitation.
- **Omission Detection (`LcsOmissionDetector`)**: Uses the Best-Drop LCS algorithm to pinpoint skipped or forgotten words.
- **Hint System**: Peek at the next word for 2 seconds or reveal the first letter.

👉 [**Deep Dive: Memorization & Mistake Detection Guide →**](doc/MEMORIZATION_MODE_GUIDE.md)

---

### 5. Production Audio Pipeline & Microphone Hardware
Studio-grade audio recording tailored for Quranic speech:
- **Bypassing Hardware DSP Filters**: Explicitly disables Acoustic Echo Cancellation (AEC) and Noise Suppression (NS) so quiet breath consonants (`هـ`, `ح`, `ث`) and Madd elongation are not muted.
- **Automatic 16kHz Resampling**: Resamples hardware streams to 16,000 Hz Mono Float32 `[-1.0, 1.0]`.
- **Audio Interruption Resilience**: Gracefully handles incoming phone calls, Siri/Google Assistant, and Bluetooth AirPods switches.

👉 [**Deep Dive: Production Audio Pipeline Guide →**](doc/AUDIO_PIPELINE_GUIDE.md)

---

### 6. Authentic Mus'haf UI & Page Layout
Render authentic Islamic typography in Flutter:
- **15-Line Madani Mus'haf (604 Pages)**: Support for authentic page layouts matching the printed King Fahd Complex Mus'haf.
- **Uthmanic Fonts**: Guidance on integrating `KFGQPC Uthman Taha Naskh` and handling diacritics and verse end markers (۝).
- **Smooth Auto-Scroll & Page Turns**: Automatically flips pages when the reciter reaches the last word of a page.

👉 [**Deep Dive: Interactive Mus'haf UI & Layout Guide →**](doc/MUSHAF_UI_GUIDE.md)

---

### 7. Multi-Riwayah & 20 Canonical Rawis
First-class support for Islamic recitation traditions:
- **10 Mutawatir Qira'at & 20 Canonical Rawis**: Supports Hafs, Warsh, Qalun, Al-Duri, Shu'bah, etc.
- **6 Counting Madhhabs (مذاهب العدّ الستة)**: Resolves verse number discrepancies between Kufi (6,236), Madani (6,214), Basri (6,204), Makki (6,219), and Dimashqi (6,226).
- **`QiraatAyahMapper`**: Maps verse indices across traditions using canonical Quranpedia datasets.

👉 [**Deep Dive: Multi-Riwayah & Multi-Qira'at Guide →**](doc/RIWAYAH_GUIDE.md)

---

### 8. Neural Model Deployment (On-Demand vs Bundled)
Flexible deployment options for app publishers:
- **Strategy A (On-Demand Streaming)**: Keep your app store install size tiny (~10–15 MB) and download the 69MB model on first launch using `ModelDownloader`.
- **Strategy B (Asset Bundling)**: Bundle the `.onnx` file directly in `assets/model/` for 100% offline, zero-network, out-of-the-box operation.

👉 [**Deep Dive: Model & Assets Deployment Guide →**](doc/MODEL_DOWNLOAD_GUIDE.md)

---

## 🎨 Color Highlighting & Event Protocol

Every word alignment emitted on `tracker.onWordMatched` resolves into one of three color states:

```
┌─────────────────────────────────────────────────────────────┐
│ 🟢 GREEN  (Valid Pronunciation & Correct Tajweed)           │
│    event.isGreen == true (event.isRed == false & no errors) │
├─────────────────────────────────────────────────────────────┤
│ 🟡 YELLOW (Pronounced Correctly, but with a Tajweed Slip)   │
│    event.isYellow == true (tajweedErrors is not empty)      │
│    Tap word to open TajweedErrorSheet with corrective advice│
├─────────────────────────────────────────────────────────────┤
│ 🔴 RED    (Skipped Word, Omission, or Gross Mispronunciation)│
│    event.isRed == true                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚙️ Configuration Presets (`TrackerConfig`)

```dart
// 1. Hands-Free Page Reading (Forgiving & Auto-Navigating)
final dictationConfig = TrackerConfig.dictation();

// 2. Strict Tajweed Examination
final examConfig = const TrackerConfig(
  recitationSpeed: RecitationSpeed.normal,
  matchingStrictness: MatchingStrictness.strict,
  enableEarlyMatching: false, // Must pronounce full vowel duration
  enableAutoReanchor: false,  // Skipping is flagged in RED
);

// 3. Fast Revision (Taraweeh / Hadr Tempo)
final fastConfig = TrackerConfig.fast();
```

👉 **Need quick method signatures?** [Check the API Quick Reference Cheat Sheet →](doc/API_REFERENCE.md)

---

## 📚 Full Documentation Suite

All in-depth documentation is housed in the [`doc/`](doc/) directory:

| Guide | Description |
| :--- | :--- |
| 🗺️ [**Documentation Hub**](doc/README.md) | Master directory index and structured learning pathways |
| 📖 [**Dictation Integration Guide**](doc/DICTATION_SYSTEM_GUIDE.md) | Early Matching, Auto Re-anchoring, 24 vs 30 phoneme threshold |
| 🎯 [**Tajweed Verification Guide**](doc/TAJWEED_GUIDE.md) | Madd rules, Ghunnah, Shaddah, speed calibration, `ErrorExplainer` |
| 🎙️ [**Voice Search Guide**](doc/VOICE_SEARCH_GUIDE.md) | "Recite to Navigate", 6,236 Ayah Myers bit-parallel search |
| 🧠 [**Memorization & Mistake Detection Guide**](doc/MEMORIZATION_MODE_GUIDE.md) | Tarteel-style Hifdh testing, hidden words, `LcsOmissionDetector` |
| 🎧 [**Production Audio Pipeline Guide**](doc/AUDIO_PIPELINE_GUIDE.md) | 16kHz Float32 streaming, bypassing DSP filters, interruptions |
| 📜 [**Interactive Mus'haf UI & Layout Guide**](doc/MUSHAF_UI_GUIDE.md) | 15-line Madani layout, Uthmanic fonts, line centering, page turns |
|   [**Multi-Riwayah Guide**](doc/RIWAYAH_GUIDE.md) | 20 Mutawatir Rawis, 6 counting traditions, `QiraatAyahMapper` |
| 📦 [**Model & Assets Guide**](doc/MODEL_DOWNLOAD_GUIDE.md) | On-demand 69MB download (`ModelDownloader`) vs manual bundling |
| 📱 [**Complete App Integration Guide**](doc/APP_INTEGRATION_GUIDE.md) | State management (Riverpod/Bloc), lifecycle, 1-file minimal app |
| ⚡ [**API Quick Reference & Cheat Sheet**](doc/API_REFERENCE.md) | High-density method signatures, streams, configs, models |
| 🛠️ [**Troubleshooting & FAQ**](doc/TROUBLESHOOTING_FAQ.md) | Debugging microphone silence, alignment lag, repeated refrain jumping |

---

## 📁 Example Application

A complete, production-ready sample application is included in the [`example/`](example/) directory:

```bash
cd example
flutter pub get
dart run recite_quran:download_model
flutter run -d windows   # or -d android / -d chrome
```

---

##   Sacred Covenant & License (لوجه الله تعالى)

### **مَا أَسْأَلُكُمْ عَلَيْهِ مِنْ أَجْرٍ ۖ إِنْ أَجْرِيَ إِلَّا عَلَىٰ رَبِّ الْعَالَمِينَ**

> **THIS PACKAGE AND SOURCE CODE ARE DEDICATED FOR THE SAKE OF ALLAH ALONE.**

Before viewing, using, distributing, or modifying any part of this repository, you explicitly agree to the following covenants:

1. **100% Free to End Users**:
   You may use, study, and redistribute this software or its logic **ONLY** in applications and services that are completely free of charge to all end users for the end inshaa Allah .
2. **Strict Prohibition on Commercialization & Profit**:
   You are **STRICTLY FORBIDDEN** from selling this application, placing it behind paywalls, subscription models, in-app purchases, charging download fees, monetizing it with advertisements (AdMob, Unity Ads, etc.), or extracting any financial revenue from this codebase, models, or outputs.
3. **Pass-Through**:
   These terms are immutable and strictly pass on to any fork, derivative work, or redistributed component.

---

## 🤲 Acknowledgments

*Alhamdulillah (الحمد لله رب العالمين) — بفضل الله وبرحمته وحده*

- **[Zipformer Quran Acoustic Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother Mustafa & **[QuranLab](https://huggingface.co/Quran-Lab)** for the Zipformer causal streaming ASR model training.
- **[quranic-phonemizer](https://github.com/M97Chahboun/quranic-phonemizer)** for generating authentic native Riwayat phonetic datasets and sound-level Tajweed rule annotations.
- **[Quranpedia (موسوعة القرآن)](https://quranpedia.net)** for the verified **[Qira'at Ayah Map](https://github.com/quranpedia/qiraat-ayah-map)** dataset linking all 6 counting systems and 20 rawis to Kufi numbering.
- **[quran-transcript](https://github.com/obadx/quran-transcript)** by Brother Abdullah Aml.
- **[tasmee3-muaalem-findings / Seraj]** (Dr. Omar Abu Hafs) for the Best-Drop LCS word omission detection formulations and benchmarks.

---

<div align="center">

**هَٰذَا مِنْ فَضْلِ رَبِّي — رَبَّنَا تَقَبَّلْ مِنَّا ۖ إِنَّكَ أَنتَ السَّمِيعُ الْعَلِيمُ**

</div>
