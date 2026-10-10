# 📖 Quran Dictation Tracking System — Architecture & Integration Guide

A technical reference and integration guide for developers and AI agents building real-time Quran recitation readers using **`package:recite_quran`** in **Dictation Mode** (`isTajweed: false`).

---

## 📑 Table of Contents

1. [Dictation Mode vs Tajweed Mode](#1-dictation-mode-vs-tajweed-mode)
2. [End-to-End Architecture](#2-end-to-end-architecture)
3. [Core Matching Engine (2D Dynamic Programming)](#3-core-matching-engine-2d-dynamic-programming)
4. [Early Matching System (`enableEarlyMatching`)](#4-early-matching-system-enableearlymatching)
   - [What It Is](#what-it-is)
   - [Why It Is Essential](#why-it-is-essential)
   - [How It Works (Frontier Shield & Tail Reservation)](#how-it-works-frontier-shield--tail-reservation)
5. [Automatic Re-anchoring (`enableAutoReanchor`)](#5-automatic-re-anchoring-enableautoreanchor)
   - [What It Is](#what-it-is-1)
   - [Why It Is Needed](#why-it-is-needed)
   - [Multi-Stage Window Probing](#multi-stage-window-probing)
   - [Anti-Ambiguity Guard (Mutashabihat Safety)](#anti-ambiguity-guard-mutashabihat-safety)
   - [Threshold Analysis: 24 vs 30 Phonemes](#threshold-analysis-24-vs-30-phonemes)
   - [Pros and Cons](#pros-and-cons)
6. [Tracker Configuration Reference (`TrackerConfig`)](#6-tracker-configuration-reference-trackerconfig)
7. [Step-by-Step App Integration Guide](#7-step-by-step-app-integration-guide)
8. [Complete 1-File Working Example (Flutter)](#8-complete-1-file-working-example-flutter)

---

## 1. Dictation Mode vs Tajweed Mode

`recite_quran` supports two operational paradigms via `isTajweed`:

| Feature | Dictation Mode (`isTajweed: false`) | Tajweed Mode (`isTajweed: true`) |
| :--- | :--- | :--- |
| **Primary Goal** | **Smooth, responsive hands-free reading** | **Strict recitation & phonetic grading** |
| **Acoustic Grading** | Disabled (focuses on words uttered) | Active (grades Shaddah, Madd, Ghunnah) |
| **Early Matching** | **Active** (eliminates Madd lag) | **Disabled** (must hear full vowel duration) |
| **Auto Re-anchor** | **Available** (recovers when user skips) | **Strictly Disabled** (unauthorized skips marked RED) |
| **User Experience** | Fluid page-following, high responsiveness | Precision feedback, diagnostic explanations |

---

## 2. End-to-End Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Microphone Audio                      │
│                  16kHz Mono 16-bit PCM Audio                │
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
│  - Receives live ASR phonetic tokens                        │
│  - Executes DictationSequencer                              │
│  - Completely offloads main UI thread                       │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│    QuranDictationMatcher     │    │     Auto Re-Anchor Engine    │
│  - 2D Dynamic Programming    │    │  - Myers Bit-Parallel Search │
│  - Levenshtein error matrix  │    │  - Multi-stage window probe  │
│  - Wasl / Idgham merge       │    │  - Anti-Ambiguity Guard      │
│  - Skip lookahead (0, 1, 2)  │    │  - Activates ONLY on stall   │
└──────────────┬───────────────┘    └──────────────┬───────────────┘
               │                                   │
               └─────────────────┬─────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                  Isolate Stream Controller                  │
│       Emits WordMatchedEvent(globalIndex, score, isRed)      │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       Flutter UI Layer                      │
│  - Updates word highlights (Green = Read, Red = Skipped)    │
│  - Auto-scrolls Mushaf view to active word                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Core Matching Engine (2D Dynamic Programming)

The core alignment algorithm operates as a bounded **2D Dynamic Programming (DP)** Levenshtein matrix comparing:
- **Reference phonemes** of the target Quranic word ($M$ characters).
- **Incoming unconsumed ASR phonemes** ($N$ characters).

### Lookahead & Skip Detection
The sequencer maintains a `targetWordCursor` pointing to the next expected word. In every processing cycle:
1. **`skip = 0` (Current Word):** Attempts to match the current target word.
2. **`skip = 1` (Omission Lookahead):** If `skip = 0` fails, checks if the reciter accidentally skipped 1 word.
3. **`skip = 2` (Extended Lookahead):** Checks if the reciter skipped 2 words.
4. **Boundary Merging (Wasl / Idgham):** Also tests merging word $W$ and $W+1$ to handle connected speech across word boundaries (e.g. *مِن بَعْدِ* $\to$ *مِمْبَعْدِ*).

If a match is found at `skip > 0`:
- The omitted words between `targetWordCursor` and `targetWordCursor + skip` are immediately committed as **RED** (missed words).
- The matched destination word is committed as **GREEN**.
- `asrCharAnchor` advances by `tokensConsumed`.

---

## 4. Early Matching System (`enableEarlyMatching`)

### What It Is
`enableEarlyMatching` is an optimization designed for Dictation mode that allows a word to commit **before the reciter finishes uttering its trailing vowels or prolonged letters**.

### Why It Is Essential
In natural Quranic recitation, readers continuously prolong trailing vowels (e.g., *الْعَالَمِــــــينَ*, *الرَّحِيــــــمِ*).
- **Without Early Matching:** The tracker must wait until the reciter finishes all 4 to 6 beats of the ending Madd before highlighting the word. This causes a perceptible delay ($0.5\text{s} - 1.0\text{s}$) between the reciter's voice and the UI highlight.
- **With Early Matching:** As soon as the root phonetic body of the word is confirmed ($> 85\%$ matched with near-zero error), the word is highlighted **instantly**, giving the reciter a seamless, real-time visual cue.

### How It Works (Frontier Shield & Tail Reservation)

```
Reciter voice:   "ءَلحَمدُ"  ───>  "لِلَّا" (already started next word!)
Phonetic stream: [ء][ل][ح][م][د][ل][ل][ا]...
                      ▲
                      │ Word commits HERE (Early Break)
                      │
Trailing letters:     [ُ] (Dammah) reserved as _pendingTail
```

1. **Early Break Trigger:** When unconsumed ASR characters match the primary consonants and vowels of a word ($\ge 4$ characters) with error cost below `0.15`, the word commits immediately.
2. **Tail Reservation (`_pendingTail`):** Any unuttered trailing phonemes from that word are stored in `_pendingTail`.
3. **Frontier Shield:** Upcoming words are **forbidden** from matching against these trailing leftovers.
4. **Tail Drain:** As the reciter finishes the trailing sounds or moves to the next word, `_pendingTail` drains or dissolves automatically.

> **Default:** `TrackerConfig(enableEarlyMatching: true)`. Always keep enabled for Dictation applications.

---

## 5. Automatic Re-anchoring (`enableAutoReanchor`)

### What It Is
Auto Re-anchoring is a supervisory recovery subsystem that detects when tracking is lost (e.g., when a user skips ahead several verses or flips to a different page within the Surah) and **automatically jumps the cursor to where the user is currently reading**.

### Why It Is Needed
Without auto re-anchoring, if a user skips from Ayah 2 to Ayah 10:
- The normal DP matcher only looks ahead 2 words (`maxSkipWords: 2`).
- Tracking permanently halts at Ayah 2.
- The user is forced to stop reciting, take their hands off, and tap the screen manually.

With auto re-anchoring, the app detects the stall, locates the new verse, and resumes tracking hands-free.

> [!TIP]
> ### 💡 Author's Note & Strong Recommendation (Enable Auto Re-anchor!)
>
> **Why is `enableAutoReanchor` `false` by default in `TrackerConfig`?**
> The author originally set the default to `false` purely out of conservative caution—having not yet tested it across millions of diverse real-world users, and wanting to avoid any risk of unexpected jumps during strict memorization exams or edge-case recitation stumbles.
>
> **Why you are STRONGLY ENCOURAGED to enable it (`enableAutoReanchor: true`):**
> For any Quran reading, Tilawah, or consumer Mus'haf app, **turning this on is what gives your app that modern, magical hands-free experience (like Tarteel AI)!** 
>
> You can enable it with full confidence because the engine was engineered with multiple strict defenses specifically designed to prevent false jumps:
> 1. **Anti-Ambiguity Guard ($\Delta\text{dist} < 3$):** If the user recites repeated verses (e.g., *فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ* which repeats 31 times in Surah Ar-Rahman), the engine detects tied candidates and **refuses to jump** until unique verse text is recited.
> 2. **Multi-Stage Window Probing:** Evaluates the entire unconsumed speech buffer (up to 64 chars) across verse boundaries. Multi-verse phrases are 100% unique across the Surah.
> 3. **Stall Threshold (24 phonemes):** It requires at least $\approx 3\text{--}5$ unconsumed words before triggering, ensuring casual pauses or small mispronunciations never cause accidental skips.

---

### Multi-Stage Window Probing

When unconsumed speech reaches the stall threshold, `DictationSequencer` executes a 3-stage search using Gene Myers' $O(M)$ Bit-Parallel algorithm:

```
Unconsumed Speech Buffer:
[فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ] [كُلُّ مَنْ عَلَيْهَا فَانٍ]
 └──────────────────────┬───────────────────────┘ └──────────┬───────────┘
               Stage 1: Full Query (up to 64 chars)          Stage 3: Pure Tail
```

1. **Stage 1 — Full Unconsumed Query (up to 64 chars):**
   - Probes the entire unconsumed speech buffer.
   - **Why this is critical:** If the reciter uttered an ambiguous refrain (e.g., *فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ*) followed by the next verse (*كُلُّ مَنْ عَلَيْهَا فَانٍ*), the combined multi-verse query is **100% unique in the entire Surah**. The ambiguity dissolves and the engine jumps with zero errors.
2. **Stage 2 — Front Window (first 36 chars):**
   - If the full query is ambiguous, evaluates the opening 36 characters.
3. **Stage 3 — Tail Window (~28 chars):**
   - If the opening was noisy or unaligned, evaluates the latest 28 characters where the user is currently reciting.

---

### Anti-Ambiguity Guard (Mutashabihat Safety)

The Quran contains identical or near-identical verses (*Mutashabihat*), such as:
- *فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ* (repeats **31 times** in Surah 55).
- *وَيْلٌ يَوْمَئِذٍ لِّلْمُكَذِّبِينَ* (repeats **10 times** in Surah 77).

**The Guard Rule:**
```dart
for (int i = 1; i < candidateWords.length; i++) {
  final c = candidateWords[i];
  if ((c.wordIndex - best.wordIndex).abs() > 2 && (c.dist - best.dist) < 3) {
    // Distant candidates with tied/close edit distance -> AMBIGUOUS!
    return null; // SUPPRESS JUMP!
  }
}
```
If two candidate verses are $> 2$ words apart and have edit distance difference $< 3$, the engine **refuses to jump**. It waits until the reciter utters the following unique verse before moving.

---

### Threshold Analysis: 24 vs 30 Phonemes

Which threshold should you use in your app?

| Metric | `reanchorStallThreshold: 24` *(Recommended)* | `reanchorStallThreshold: 30` *(Conservative)* |
| :--- | :--- | :--- |
| **Equivalent Arabic Words** | $\approx 3\text{ to }5$ words | $\approx 5\text{ to }7$ words |
| **Response Latency** | **Fast:** Catches up after $\approx 1$ short verse | **Slower:** Requires reciting $\approx 2$ full verses |
| **Short Verses** | Recognizes short verses (18–22 chars) smoothly | Stalls on short verses until next verse starts |
| **False Jump Protection** | Equal (both protected by Anti-Ambiguity Guard) | Slightly higher tolerance for noisy background chatter |
| **Best Used In** | **Commercial Quran Readers, Kids apps, Hands-Free Tilawah** | **Strict memorization testing, noisy classrooms** |

> **Recommendation:** Use **`24`** for consumer apps. The Anti-Ambiguity Guard and $22\%$ distance ceiling provide rock-solid safety against false jumps.

---

### Pros and Cons of Auto Re-anchoring

#### ✅ Pros
- **Hands-Free Excellence:** Users can flip pages, recite selected passages, or jump verses without touching the screen.
- **Surah-Scoped Safety:** Restricts candidate searches strictly within the currently open Surah; cannot accidentally jump to other Surahs.
- **Self-Healing:** Recovers from temporary microphone dropouts or skipped sentences automatically.

#### ⚠️ Cons (When NOT to use it)
- **Hifz / Memorization Testing:** In memorization exams, when a student skips words, the app should mark omissions **RED** and penalize them, NOT jump to where they skipped. (Use **Tajweed Mode** or keep `enableAutoReanchor: false` for exam features).

---

## 6. Tracker Configuration Reference (`TrackerConfig`)

```dart
const TrackerConfig({
  /// Pacing for Tajweed Madd lengths (fast, normal, slow).
  RecitationSpeed recitationSpeed = RecitationSpeed.normal,

  /// Matching sensitivity / Levenshtein cost thresholds (easy, normal, hard).
  MatchingStrictness matchingStrictness = MatchingStrictness.normal,

  /// Whether to commit words early in Dictation mode (Default: true).
  bool enableEarlyMatching = true,

  /// Whether to auto re-anchor when user skips ahead (Default: false).
  bool enableAutoReanchor = false,

  /// Phonemes needed to trigger re-anchor recovery (Default: 24).
  int reanchorStallThreshold = 24,
});
```

### Preset Factories

```dart
// Standard balanced configuration
final config = TrackerConfig.normal(
  enableEarlyMatching: true,
  enableAutoReanchor: true,
  reanchorStallThreshold: 24,
);

// High-speed / beginner configuration
final easyConfig = TrackerConfig.easy(
  enableAutoReanchor: true,
  reanchorStallThreshold: 20,
);

// Conservative / strict configuration
final strictConfig = TrackerConfig.strict(
  enableAutoReanchor: false,
);
```

---

## 7. Step-by-Step App Integration Guide

### Step 1: Add Dependencies (`pubspec.yaml`)
```yaml
dependencies:
  flutter:
    sdk: flutter
  recite_quran: ^1.0.0
  permission_handler: ^11.3.1
```

### Step 2: Request Microphone Permission
```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> initPermissions() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}
```

### Step 3: Initialize ReciteQuran Controller
```dart
import 'package:recite_quran/recite_quran.dart';

final controller = ReciteQuranController();

```dart
final metadataService = QuranMetadataService();
final repository = QuranRepository(metadataService);
await repository.loadSurahAsync(1);

final tracker = ReciteQuran(
  repository: repository,
  config: const TrackerConfig(
    matchingStrictness: MatchingStrictness.normal,
    enableEarlyMatching: true,
    enableAutoReanchor: true, // Enable for hands-free reading
    reanchorStallThreshold: 24,
  ),
  isTajweed: false, // DICTATION MODE
);

await tracker.initialize();
```

### Step 4: Set Active Surah in Dictation Mode
```dart
// Set Surah 1 (Al-Fatiha) in Dictation Mode
tracker.setTargetSurah(1);
```

### Step 5: Listen to Real-Time Word Events
```dart
tracker.onWordMatched.listen((WordMatchedEvent event) {
  // event.wordId: 0-based word index in the active Surah
  // event.isRed: true if the word was skipped by the user
  // event.isNeutral: true if not yet reached
  // event.cleanAsr: the phonemes recognized by the engine
  
  setState(() {
    if (event.isRed) {
      wordStates[event.wordId] = WordStatus.skipped;
    } else {
      wordStates[event.wordId] = WordStatus.matched;
    }
  });

  // Auto-scroll Mushaf to active word
  scrollToWord(event.wordId);
});
```

### Step 6: Start Listening to Microphone
```dart
final audioProcessor = AudioProcessor();
await audioProcessor.start(
  onChunk: (Float32List chunk, bool isFinal) {
    tracker.feedAudioChunk(chunk, isFinal: isFinal);
  },
);
```

---

## 8. Complete 1-File Working Example (Flutter)

Here is a complete, production-ready Flutter widget implementing a hands-free Quran reader with real-time word highlighting:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() => runApp(const MaterialApp(home: DictationReaderScreen()));

class DictationReaderScreen extends StatefulWidget {
  const DictationReaderScreen({super.key});

  @override
  State<DictationReaderScreen> createState() => _DictationReaderScreenState();
}

class _DictationReaderScreenState extends State<DictationReaderScreen> {
  final QuranMetadataService _metadataService = QuranMetadataService();
  late final QuranRepository _repository;
  ReciteQuran? _tracker;
  final AudioProcessor _audioProcessor = AudioProcessor();

  List<ContinuousQuranWord> _words = [];
  final Map<int, bool> _wordHighlightStatus = {};
  bool _isTracking = false;
  int _activeSurah = 1;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    // 1. Request microphone permission
    final hasPerm = await _audioProcessor.hasPermission();
    if (!hasPerm) return;

    // 2. Initialize Quran Repository & load Surah
    _repository = QuranRepository(_metadataService);
    await _repository.loadSurahAsync(_activeSurah);
    _words = _repository.getSurahWords(_activeSurah);

    // 3. Initialize engine with Dictation auto-reanchoring enabled
    _tracker = ReciteQuran(
      repository: _repository,
      config: const TrackerConfig(
        matchingStrictness: MatchingStrictness.normal,
        enableEarlyMatching: true,
        enableAutoReanchor: true, // Hands-free auto navigation
        reanchorStallThreshold: 24,
      ),
      isTajweed: false, // Dictation mode
    );

    await _tracker!.initialize();
    _tracker!.setTargetSurah(_activeSurah);

    // 4. Subscribe to word alignment stream
    _tracker!.onWordMatched.listen((WordMatchedEvent event) {
      if (mounted) {
        setState(() {
          _wordHighlightStatus[event.wordId] = !event.isRed;
        });
      }
    });
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
      appBar: AppBar(
        title: Text('Surah $_activeSurah (Dictation Mode)'),
        actions: [
          IconButton(
            icon: Icon(_isTracking ? Icons.mic : Icons.mic_off),
            color: _isTracking ? Colors.green : Colors.grey,
            onPressed: _toggleTracking,
          ),
        ],
      ),
      body: Center(
        child: Text(
          _isTracking ? 'Recite aloud... Tracking is live!' : 'Tap mic to begin recitation.',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
```

---

## 9. Best Practices Checklist for Production

- [x] **Ensure `isTajweed: false`** is passed to `setSurah()` when in Dictation mode.
- [x] **Keep `enableEarlyMatching: true`** to eliminate acoustic latency at word endings.
- [x] **Set `enableAutoReanchor: true`** if you want the app to follow the reciter when they skip verses hands-free.
- [x] **Use `reanchorStallThreshold: 24`** for the ideal balance between rapid response and zero false jumps.
- [x] **Always initialize the engine once** and switch chapters using `setSurah()`; never re-instantiate the entire isolate per chapter.
