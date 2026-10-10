# 🧠 Memorization & Mistake Detection Guide (Hifdh Mode)

A comprehensive architectural and developer reference for building **Tarteel-style Memorization (Hifdh) Testing** and real-time **Mistake / Omission Detection** using **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Introduction: Hifdh Mode in Modern Quran Apps](#1-introduction-hifdh-mode-in-modern-quran-apps)
2. [The Core Mechanics of Memorization Testing](#2-the-core-mechanics-of-memorization-testing)
   - [Blind Mode (Hidden Words)](#blind-mode-hidden-words)
   - [Progressive Word Revelation](#progressive-word-revelation)
   - [Hint & Peek System](#hint--peek-system)
3. [Real-Time Mistake & Omission Detection](#3-real-time-mistake--omission-detection)
   - [Red Highlight Triggering (`WordMatchedEvent.isRed`)](#red-highlight-triggering)
   - [Best-Drop LCS Word Omission Locator (`LcsOmissionDetector`)](#best-drop-lcs-word-omission-locator)
   - [Tashkeel & Phonetic Divergence](#tashkeel--phonetic-divergence)
4. [Pedagogical State Machine for Hifdh Practice](#4-pedagogical-state-machine-for-hifdh-practice)
5. [Tapping for Correction & Comparison UI](#5-tapping-for-correction--comparison-ui)
6. [Complete 1-File Working Hifdh App (Flutter)](#6-complete-1-file-working-hifdh-app-flutter)
7. [Production Best Practices & Retention Analytics](#7-production-best-practices--retention-analytics)

---

## 1. Introduction: Hifdh Mode in Modern Quran Apps

In traditional Hifdh testing, a teacher (*Muhaffidh*) holds the Mus'haf and listens while the student recites from memory with their eyes closed or looking away. If the student slips, skips a word, or errs in harakah, the teacher alerts them.

**Tarteel AI** digitized this experience with **"Memorization Mode"**:
- **Verses are hidden** or blurred on screen so the user cannot read ahead.
- The on-device speech engine tracks speech in real time.
- Words **reveal themselves dynamically** in Green as the user recites correctly.
- If a word is omitted or mispronounced, it is flagged in **Red**.
- A summary report calculates accuracy score, forgotten words, and revision recommendations.

With **`package:recite_quran`**, you can build this exact experience 100% on-device with zero cloud server cost and zero latency.

---

## 2. The Core Mechanics of Memorization Testing

```
┌─────────────────────────────────────────────────────────────┐
│                 Student Recites from Memory                 │
│              (Screen initially masks all words)             │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 ReciteQuran Tracking Engine                 │
│                 (isTajweed: true or false)                  │
└──────────────────────────────┬──────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
 ┌──────────────────────┐              ┌──────────────────────┐
 │ Correct Pronunciation │              │   Mistake / Omission │
 │   (isRed: false)     │              │    (isRed: true)     │
 └──────────┬───────────┘              └──────────┬───────────┘
            │                                     │
            ▼                                     ▼
 ┌──────────────────────┐              ┌──────────────────────┐
 │ REVEAL WORD IN GREEN │              │ REVEAL WORD IN RED   │
 │ Word becomes visible │              │ Play gentle haptic   │
 │ with smooth fade-in  │              │ Add to mistake list  │
 └──────────────────────┘              └──────────────────────┘
```

### Blind Mode (Hidden Words)
In UI rendering, each word possesses an visibility state:
```dart
enum HifzWordVisibility {
  hidden,   // Completely blanked out or replaced with dots (••••)
  blurred,  // Gaussian blurred so text shape is illegible
  peeked,   // Temporarily revealed for 2 seconds on user request
  revealed, // Successfully recited and permanently shown
}
```

### Progressive Word Revelation
When the alignment engine emits `WordMatchedEvent`:
- If `!event.isRed`: Transition word state to `HifzWordVisibility.revealed` with a smooth 200ms opacity animation.
- If `event.isRed`: Transition to `HifzWordVisibility.revealed` with a distinct crimson red background and flag the error index in the session scorecard.

### Hint & Peek System
If a student is stuck and cannot recall the next word:
1. **First-Letter Hint:** Reveal only the first Arabic letter of the pending word (e.g., showing `قـ...` for `قُلْ`).
2. **2-Second Peek:** Temporarily reveal the next word on tap, then fade it back out. Every peek is counted as an assisted prompt in the final score.

---

## 3. Real-Time Mistake & Omission Detection

### Red Highlight Triggering
When the user pronounces an incorrect word or skips a word in the reference text:
1. The 2D Dynamic Programming sequencer checks the candidate phonemes.
2. If the user skipped ahead to word $i+1$ or $i+2$, word $i$ is immediately marked as skipped:
   ```dart
   tracker.onWordMatched.listen((event) {
     if (event.isRed) {
       // Word was omitted or pronounced incorrectly
       _markWordMistake(event.wordId);
     }
   });
   ```

### Best-Drop LCS Word Omission Locator
When a reciter skips an entire phrase or drops a single word in a fast-paced verse, **`LcsOmissionDetector`** ([`lib/utils/omission_detector.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/utils/omission_detector.dart)) uses the Longest Common Subsequence Best-Drop algorithm:

```dart
import 'package:recite_quran/recite_quran.dart';

final words = repository.getSurahWords(surahNumber);
final phonemesPerWord = words.map((w) => w.phoneme).toList();

final OmissionResult result = LcsOmissionDetector.detectOmission(
  phonemesPerWord: phonemesPerWord,
  emittedPhonemes: liveAsrPhonemes,
);

if (result.isOmissionDetected) {
  print('Omitted word index: ${result.omittedWordIndex}');
  print('Phoneme shortfall: ${result.shortfall}');
  print('Confidence gap: ${result.confidenceGap}');
}
```

The Best-Drop algorithm tests leaving out each word $w_i$ from the reference sentence and calculates the resulting LCS length against the reciter's speech. If dropping word $k$ dramatically increases alignment density with a significant `confidenceGap`, word $k$ is deterministically flagged as forgotten.

---

## 4. Pedagogical State Machine for Hifdh Practice

```dart
enum HifzSessionState {
  ready,
  reciting,
  paused,
  completed,
}

class HifzWordState {
  final int wordIndex;
  final String textUthmani;
  HifzWordVisibility visibility;
  bool hasError;
  int peekCount;

  HifzWordState({
    required this.wordIndex,
    required this.textUthmani,
    this.visibility = HifzWordVisibility.hidden,
    this.hasError = false,
    this.peekCount = 0,
  });
}
```

---

## 5. Tapping for Correction & Comparison UI

In Tarteel AI, tapping an erroneous (Red) word brings up a bottom sheet comparing what was expected vs what was heard:

```dart
void _showCorrectionSheet(BuildContext context, HifzWordState word, String? heardText) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('تصحيح الكلمة (Word Correction)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text('القرآن الكريم (Expected)', style: TextStyle(color: Colors.green)),
                  const SizedBox(height: 8),
                  Text(word.textUthmani,
                      style: const TextStyle(fontSize: 28, fontFamily: 'KFGQPC')),
                ],
              ),
              const Icon(Icons.arrow_forward, color: Colors.grey),
              Column(
                children: [
                  const Text('ما نطقته (Heard)', style: TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  Text(heardText ?? 'غير واضح / متروك',
                      style: const TextStyle(fontSize: 22, color: Colors.red)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.volume_up),
            label: const Text('استمع للنطق الصحيح (Play Qari)'),
            onPressed: () {
              // Trigger audio playback for this word or verse
            },
          ),
        ],
      ),
    ),
  );
}
```

---

## 6. Complete 1-File Working Hifdh App (Flutter)

Here is a complete, self-contained Flutter screen implementing **Blind Memorization Practice** with hidden words, progressive reveal on recitation, peek hints, and accuracy scoring:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HifzMemorizationScreen(),
  ));
}

class HifzMemorizationScreen extends StatefulWidget {
  const HifzMemorizationScreen({super.key});

  @override
  State<HifzMemorizationScreen> createState() => _HifzMemorizationScreenState();
}

class _HifzMemorizationScreenState extends State<HifzMemorizationScreen> {
  final QuranMetadataService _metadata = QuranMetadataService();
  late final QuranRepository _repo;
  ReciteQuran? _tracker;
  final AudioProcessor _audio = AudioProcessor();

  List<ContinuousQuranWord> _words = [];
  final Map<int, bool> _revealed = {};
  final Map<int, bool> _mistakes = {};
  bool _isReciting = false;
  int _activeSurah = 114; // Surat An-Nas

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    final hasPerm = await _audio.hasPermission();
    if (!hasPerm) return;

    _repo = QuranRepository(_metadata);
    await _repo.loadSurahAsync(_activeSurah);
    _words = _repo.getSurahWords(_activeSurah);

    _tracker = ReciteQuran(
      repository: _repo,
      config: const TrackerConfig(
        enableEarlyMatching: true,
        enableAutoReanchor: false, // Strict order for Hifz test
      ),
      isTajweed: false,
    );

    await _tracker!.initialize();
    _tracker!.setTargetSurah(_activeSurah);

    _tracker!.onWordMatched.listen((WordMatchedEvent event) {
      if (mounted) {
        setState(() {
          _revealed[event.wordId] = true;
          if (event.isRed) {
            _mistakes[event.wordId] = true;
          }
        });
      }
    });
  }

  Future<void> _toggleRecitation() async {
    if (_tracker == null) return;

    if (_isReciting) {
      await _audio.stop();
      setState(() => _isReciting = false);
    } else {
      await _audio.start(
        onChunk: (Float32List chunk, bool isFinal) {
          _tracker!.feedAudioChunk(chunk, isFinal: isFinal);
        },
      );
      setState(() => _isReciting = true);
    }
  }

  void _peekNextWord() {
    // Find first unrevealed word
    final nextIdx = _words.indexWhere((w) => !(_revealed[w.globalWordIndex] ?? false));
    if (nextIdx != -1) {
      setState(() => _revealed[nextIdx] = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !(_mistakes[nextIdx] ?? false)) {
          setState(() => _revealed[nextIdx] = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _audio.stop();
    _tracker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int totalWords = _words.length;
    final int recitedCount = _revealed.values.where((v) => v).length;
    final int mistakeCount = _mistakes.values.where((v) => v).length;
    final double accuracy = recitedCount > 0 ? ((recitedCount - mistakeCount) / recitedCount) * 100 : 100.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار الحفظ (Hifdh Test)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye_outlined),
            tooltip: 'لمحة خاطفة (Peek Hint)',
            onPressed: _peekNextWord,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Score Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الكلمات: $recitedCount / $totalWords'),
                  Text('الأخطاء: $mistakeCount', style: const TextStyle(color: Colors.red)),
                  Text('الدقة: ${accuracy.toStringAsFixed(1)}%'),
                ],
              ),
            ),
            // Masked Mushaf View
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: _words.map((word) {
                    final isRev = _revealed[word.globalWordIndex] ?? false;
                    final isErr = _mistakes[word.globalWordIndex] ?? false;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: !isRev
                            ? Colors.grey.shade200
                            : isErr
                                ? Colors.red.shade100
                                : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !isRev
                              ? Colors.grey.shade300
                              : isErr
                                  ? Colors.red
                                  : Colors.green,
                        ),
                      ),
                      child: Text(
                        isRev ? word.textUthmani : '•••••',
                        style: TextStyle(
                          fontSize: 22,
                          color: !isRev
                              ? Colors.grey.shade400
                              : isErr
                                  ? Colors.red.shade900
                                  : Colors.green.shade900,
                          fontWeight: isRev ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // Bottom Control Bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isReciting ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(_isReciting ? Icons.stop : Icons.mic),
                  label: Text(_isReciting ? 'إيقاف الاختبار (Stop Test)' : 'ابدأ التسميع (Start Reciting)',
                      style: const TextStyle(fontSize: 18)),
                  onPressed: _toggleRecitation,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 7. Production Best Practices & Retention Analytics

1. **Disable Auto Re-anchor in Tests (Keep Enabled in Reader Mode):** In examination mode, keep `enableAutoReanchor: false` so that omissions are penalized and marked in Red rather than forgiving the jump. Conversely, in your app's general Tilawah / Quran reading modes, always set `enableAutoReanchor: true` so users get smooth, hands-free auto-following.
2. **Haptic Feedback:** Trigger `HapticFeedback.mediumImpact()` when a red error occurs to alert the user without breaking their recitation rhythm.
3. **Heatmap & Spaced Repetition (SRS):** Store mistake word IDs in local SQLite/Isar. Verses with frequent red markers should be surfaced in the app's daily review queue.
4. **Offline Privacy:** Emphasize to users that all audio processing and error grading happens entirely on their device with zero audio uploaded to the cloud.
