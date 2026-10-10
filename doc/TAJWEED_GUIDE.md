#      Tajweed Verification Engine — Architecture & Developer Guide

A comprehensive architectural and implementation guide for building automated Tajweed verification and correction applications using **`package:recite_quran`** in **Tajweed Mode** (`isTajweed: true`).

---

## 📑 Table of Contents

1. [Scholarly & Pedagogical Covenant (أمانة شرعية)](#1-scholarly--pedagogical-covenant-أمانة-شرعية)
2. [Tajweed Mode vs Dictation Mode](#2-tajweed-mode-vs-dictation-mode)
3. [The Deterministic Acoustic Matrix](#3-the-deterministic-acoustic-matrix)
4. [Supported Tajweed Rules](#4-supported-tajweed-rules)
   - [Madd Rules (مدود)](#madd-rules-مدود)
   - [Mushaddad Ghunnah (غنة النون والميم المشددتين)](#mushaddad-ghunnah-غنة-النون-والميم-المشددتين)
   - [Shaddah Closure (التشديد ونبر الحروف)](#shaddah-closure-التشديد-ونبر-الحروف)
   - [Qalqalah, Ikhfa, and Idgham](#qalqalah-ikhfa-and-idgham)
5. [Recitation Speed Calibration (مراتب التلاوة)](#5-recitation-speed-calibration-مراتب-التلاوة)
6. [Tajweed Error Diagnostic Models](#6-tajweed-error-diagnostic-models)
7. [Bilingual Explanations with `ErrorExplainer`](#7-bilingual-explanations-with-errorexplainer)
8. [UI Presentation: Pre-built vs Custom Dialogs](#8-ui-presentation-pre-built-vs-custom-dialogs)
9. [Complete 1-File Tajweed App Example (Flutter)](#9-complete-1-file-tajweed-app-example-flutter)
10. [Production Best Practices](#10-production-best-practices)

---

## 1. Scholarly Covenant

> [!IMPORTANT]
> **Essential Sacred Disclaimer:**
> Automated AI and algorithmic Tajweed evaluation is an **assistive diagnostic tool** for personal revision, practice, and self-testing.
> **It can never replace personal learning and oral recitation to an authorized, certified Sheikh (المشافهة والتلقي على شيخ متقن ومجاز بالسند المتصل).**
> Subtle articulation points (*مخارج الحروف*), complex oral resonance (*الاستعلاء والترقيق*), and nuanced oral delivery must always be verified by human scholars.

Applications built using this package should display this disclaimer to learners in their onboarding or settings view.

---

## 2. Tajweed Mode vs Dictation Mode

When initializing a tracking session via `setSurah()` or `setTajweedMode()`, passing `isTajweed: true` activates the **Deterministic Tajweed Verification Engine**:

| Engine Behavior | Dictation Mode (`isTajweed: false`) | Tajweed Mode (`isTajweed: true`) |
| :--- | :--- | :--- |
| **Word Alignment** | Fast, forgiving, early-break enabled | Strict, letter-by-letter verification |
| **Early Matching** | **Active** (commits word on root letters) | **Disabled** (must pronounce full vowels) |
| **Auto Re-anchor** | **Available** (recovers when user skips) | **Strictly Blocked** (omissions marked RED) |
| **Acoustic Grading** | Disabled | **Active** (measures holding times in ms) |
| **UI Color Codes** | Green (read), Red (skipped) | Green (correct), Yellow (Tajweed slip), Red (error/skipped) |

---

## 3. The Deterministic Acoustic Matrix

Traditional speech recognition packages rely on heuristic guesses or black-box neural scores that vary unpredictably across different mobile devices.

`recite_quran` uses an **Explicit, Deterministic Acoustic Boundary Matrix** ([`lib/tracking/tajweed/tajweed_rules.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/tracking/tajweed/tajweed_rules.dart)):
1. Every rule defines an immutable `AcousticThreshold`:
   - `minSeconds`: The minimum physical holding time required.
   - `targetSeconds`: The scholarly standard duration.
   - `maxSeconds`: The maximum allowed duration before over-elongation (*زيادة*).
2. The acoustic model emits timestamped token spikes.
3. The engine measures the precise duration elapsed across the phonetic span.
4. The duration is evaluated deterministically against the active speed tier.

```
Reciter Spoken Duration (e.g. 0.35s)
  ├─ If duration < minSeconds ───► TajweedDurationStatus.underheld (نقص)
  ├─ If duration > maxSeconds ───► TajweedDurationStatus.overheld (زيادة)
  └─ If min <= duration <= max ──► TajweedDurationStatus.valid    (صحيح)
```

---

## 4. Supported Tajweed Rules

### Madd Rules (مدود)

| Rule | Name (Arabic / English) | Standard Target (Harakah) | Description |
| :--- | :--- | :--- | :--- |
| **Madd Tabee'ee** | المد الطبيعي (Natural Madd) | **2 beats** | Standard letters of Madd (`ا`, `و`, `ي`) without Hamzah or Sukun after. |
| **Madd Monfasel** | المد المنفصل (Permissible Separated) | **2 / 4 / 5 beats** | Madd letter at the end of a word followed by Hamzah at the start of the next. |
| **Madd Mottasel** | المد المتصل (Obligatory Connected) | **4 / 5 beats** | Madd letter followed by Hamzah in the exact same word. |
| **Madd Lazim** | المد اللازم (Compulsory Heavy Madd) | **6 beats** | Madd letter followed by an original Sukun or Shaddah (e.g. *الضَّالِّينَ*). |
| **Madd Aared Lissukun** | المد العارض للسكون (Temporary Madd at Waqf) | **2 / 4 / 6 beats** | Vowel before the last letter of a verse when stopping (*وقف*). |
| **Madd Leen** | مد اللين (Soft Vowel at Waqf) | **2 / 4 / 6 beats** | Waw or Ya with Sukun preceded by Fathah before the stopped letter. |

#### Legitimate Waqf Flexibility (المد العارض وقفا)
When stopping at the end of an Ayah (*Waqf*), scholars of Tajweed permit reciting Al-Madd Al-Aared Lissukun in 3 valid lengths:
- **Qasr (قصر):** 2 Harakat
- **Tawassut (توسط):** 4 Harakat
- **Tool (طول / إشباع):** 6 Harakat

The engine automatically accepts **any of these three valid options** as `TajweedDurationStatus.valid` when a reciter pauses at the verse boundary.

---

### Mushaddad Ghunnah (غنة النون والميم المشددتين)
- **Target:** **2 complete beats** of resonant nasal holding.
- **Applied to:** Noon with Shaddah (`نّ`) and Meem with Shaddah (`مّ`).
- **Diagnosis:** If the reciter cuts off the nasal sound too quickly ($< \text{minSeconds}$), the engine flags `Ghunnah underheld (نقص في مقدار الغنة)`.

---

### Shaddah Closure (التشديد ونبر الحروف)
- **Target:** $\approx 1.5$ Harakat of consonant closure and acoustic pressure (*النبر*).
- **Diagnosis:** Verifies that doubled letters have appropriate closure duration and acoustic doubling rather than being pronounced as single relaxed letters.

---

### Qalqalah, Ikhfa, and Idgham
- **Qalqalah (قلقلة):** Distinct acoustic bounce on the letters of *قُطْبُ جَدٍّ* (`ق`, `ط`, `ب`, `ج`, `د`) when carrying Sukun.
- **Idgham (إدغام):** Merging of Noon Sakinah or Tanween into *يَرْمَلُونَ*.
- **Ikhfa (إخفاء):** Concealment of Noon Sakinah before the 15 Ikhfa letters with nasalization.

---

## 5. Recitation Speed Calibration (مراتب التلاوة)

Recitation speed dictates the real-world millisecond duration of one **Harakah (حركة)** beat:

```dart
enum RecitationSpeed {
  /// Fast recitation (الحدر) — 120ms per Harakah (Fast revision)
  fast,

  /// Normal recitation (التدوير) — 150ms per Harakah (Standard practice)
  normal,

  /// Slow recitation (التحقيق) — 180ms per Harakah (Slow teaching/learning)
  slow;
}
```

### Calculated Millisecond Durations by Speed

| Speed Tier | 1 Harakah | 2 Harakat (Qasr) | 4 Harakat (Tawassut) | 6 Harakat (Tool) |
| :--- | :--- | :--- | :--- | :--- |
| **Fast (الحدر)** | **$120\text{ ms}$** | $240\text{ ms}$ | $480\text{ ms}$ | $720\text{ ms}$ |
| **Normal (التدوير)** | **$150\text{ ms}$** | $300\text{ ms}$ | $600\text{ ms}$ | $900\text{ ms}$ |
| **Slow (التحقيق)** | **$180\text{ ms}$** | $360\text{ ms}$ | $720\text{ ms}$ | $1,080\text{ ms}$ |

To update the speed dynamically at runtime:
```dart
controller.updateConfig(
  controller.config.copyWith(
    recitationSpeed: RecitationSpeed.slow,
  ),
);
```

---

## 6. Tajweed Error Diagnostic Models

When a word has Tajweed issues, the `WordMatchedEvent` emitted on `onWordMatched` contains a list of `WordTajweedError`:

```dart
class WordTajweedError {
  /// The specific rule that was checked (e.g. Madd Monfasel, Ghunnah).
  final WordTajweedRule rule;

  /// Whether the holding was 'valid', 'underheld' (نقص), or 'overheld' (زيادة).
  final TajweedDurationStatus status;

  /// The actual acoustic duration measured by the neural recognizer (in seconds).
  final double measuredDuration;

  /// The target scholarly duration for this speed tier (in seconds).
  final double targetDuration;

  /// The character span inside the word where the rule occurred.
  final String span;
}
```

---

## 7. Bilingual Explanations with `ErrorExplainer`

The engine includes **`ErrorExplainer`** ([`lib/tracking/tajweed/error_explainer.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/tracking/tajweed/error_explainer.dart)), which translates raw error data into clear, student-friendly pedagogical guidance in **Arabic** or **English**:

```dart
final explanation = ErrorExplainer.explain(
  error: tajweedError,
  languageCode: 'ar', // or 'en'
);

print(explanation.title);       // e.g. "نقص في المد المتصل"
print(explanation.description); // e.g. "تم مد الحرف بمقدار 2 حركات والمطلوب 4 حركات"
print(explanation.remedy);      // e.g. "أشبع المد المتصل بمقدار 4 إلى 5 حركات عند الهمزة"
```

---

## 8. UI Presentation: Pre-built vs Custom Dialogs

### Option A: Using the Pre-Built Modal Sheet
The package provides a ready-to-use, polished bottom sheet modal widget:

```dart
import 'package:recite_quran/recite_quran.dart';

// Call this when user taps a Yellow/Red highlighted word:
TajweedErrorSheet.show(
  context: context,
  wordUthmani: word.textUthmani,
  errors: wordErrors,
  languageCode: 'ar', // 'ar' or 'en'
);
```

### Option B: Building a Custom Dialog
```dart
Widget buildErrorBadge(WordTajweedError err) {
  final info = ErrorExplainer.explain(error: err, languageCode: 'ar');

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.amber.shade400),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amber),
            const SizedBox(width: 8),
            Text(info.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(info.description),
        const SizedBox(height: 4),
        Text('نصيحة: ${info.remedy}', style: TextStyle(color: Colors.green.shade800)),
      ],
    ),
  );
}
```

---

## 9. Complete 1-File Tajweed App Example (Flutter)

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() => runApp(const MaterialApp(home: TajweedTrainerScreen()));

class TajweedTrainerScreen extends StatefulWidget {
  const TajweedTrainerScreen({super.key});

  @override
  State<TajweedTrainerScreen> createState() => _TajweedTrainerScreenState();
}

class _TajweedTrainerScreenState extends State<TajweedTrainerScreen> {
  final QuranMetadataService _metadataService = QuranMetadataService();
  late final QuranRepository _repository;
  ReciteQuran? _tracker;
  final AudioProcessor _audioProcessor = AudioProcessor();

  final Map<int, List<Map<String, dynamic>>> _wordErrors = {};
  final Map<int, bool> _wordPassed = {};
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    final hasPerm = await _audioProcessor.hasPermission();
    if (!hasPerm) return;

    _repository = QuranRepository(_metadataService);
    await _repository.loadSurahAsync(112);

    _tracker = ReciteQuran(
      repository: _repository,
      config: TrackerConfig.normal(
        speed: RecitationSpeed.normal, // 150ms per Harakah
      ),
      isTajweed: true, // TAJWEED MODE ACTIVATED
    );

    await _tracker!.initialize();
    _tracker!.setTargetSurah(112);

    _tracker!.onWordMatched.listen((WordMatchedEvent event) {
      if (mounted) {
        setState(() {
          if (event.tajweedErrors != null && event.tajweedErrors!.isNotEmpty) {
            // Yellow: Word pronounced, but with Tajweed duration defect
            _wordErrors[event.wordId] = event.tajweedErrors!;
            _wordPassed[event.wordId] = false;
          } else if (!event.isRed) {
            // Green: Word pronounced with perfect Tajweed
            _wordPassed[event.wordId] = true;
            _wordErrors.remove(event.wordId);
          }
        });
      }
    });
  }

  Color _getWordColor(int wordIndex) {
    if (_wordErrors.containsKey(wordIndex)) return Colors.amber.shade200; // Yellow (Slip)
    if (_wordPassed[wordIndex] == true) return Colors.green.shade200;    // Green (Valid)
    return Colors.transparent;
  }

  Future<void> _toggleTracking() async {
    if (_tracker == null) return;

    if (_isTracking) {
      await _audioProcessor.stop();
      setState(() => _isTracking = false);
    } else {
      await _audioProcessor.start(
        onChunk: (Float32List chunk, bool isFinal) {
          _tracker!.feedAudioChunk(chunk, isFinal: isFinal);
        },
      );
      setState(() => _isTracking = true);
    }
  }

  @override
  void dispose() {
    _audioProcessor.stop();
    _tracker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tajweed Practice (Surah 112)')),
      body: Center(
        child: ElevatedButton.icon(
          icon: Icon(_isTracking ? Icons.stop : Icons.mic),
          label: Text(_isTracking ? 'Stop Practice' : 'Start Recitation'),
          onPressed: _toggleTracking,
        ),
      ),
    );
  }
}
```

---

## 10. Production Best Practices

1. **Speed Alignment:** Allow users to choose their speed tier (Fast / Normal / Slow) in their settings so they aren't penalized for natural pacing variations.
2. **Audio Hardware Filters:** Ensure audio processing leaves native microphone speech unaltered without voice cancellation aggressive cutoffs.
3. **Interactive Feedback:** Allow users to tap on any word highlighted in **Yellow** to immediately open the `TajweedErrorSheet` and understand how to correct their recitation.
4. **Offline Zero Latency:** All Tajweed duration math runs deterministically in microseconds on the background isolate with zero internet required.
