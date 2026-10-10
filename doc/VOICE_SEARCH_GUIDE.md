# 🎙️ Voice Search & Ayah Finder ("Recite to Navigate") — Guide

A comprehensive architectural and developer integration guide for building **Tarteel-style "Recite to Navigate"** voice search across all **6,236 Ayahs** of the Holy Quran using **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Overview: What is "Recite to Navigate"?](#1-overview-what-is-recite-to-navigate)
2. [End-to-End Search Architecture](#2-end-to-end-search-architecture)
3. [The Search Engine: Myers 64-Bit Bit-Parallel Search](#3-the-search-engine-myers-64-bit-bit-parallel-search)
4. [Continuous Real-Time Streaming vs One-Shot Search](#4-continuous-real-time-streaming-vs-one-shot-search)
5. [Mutashabihat & Progressive Disambiguation](#5-mutashabihat--progressive-disambiguation)
6. [Intelligent Prefix Stripping (Isti'adha & Basmalah)](#6-intelligent-prefix-stripping-istiadha--basmalah)
7. [The `VoiceSearchController` API Reference](#7-the-voicesearchcontroller-api-reference)
8. [Complete 1-File Voice Navigation Modal Example (Flutter)](#8-complete-1-file-voice-navigation-modal-example-flutter)
9. [Performance & Production Best Practices](#9-performance--production-best-practices)

---

## 1. Overview: What is "Recite to Navigate"?

In modern Quran apps (such as Tarteel AI), users often remember an Ayah or a fragment of a verse, but do not know the Surah name or Ayah number.

**"Recite to Navigate"** enables the user to press a microphone button, recite any part of any verse in the Quran, and have the app:
1. **Recognize speech phonetically on-device** in real time.
2. **Search across all 6,236 Ayahs** in $< 5\text{ ms}$.
3. **Stream live candidates** as the user speaks.
4. **Auto-navigate the Mushaf** to the exact Surah and Ayah as soon as the verse becomes uniquely identified!

---

## 2. End-to-End Search Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Live Microphone Stream                      │
│                  16kHz Audio PCM Input                      │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 SherpaEngine (Streaming ASR)                │
│    Emits real-time Arabic text: "ءَلحَمدُ لِلَّاهِ..."      │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             VoiceSearchController (Search Core)             │
│  1. Strips Isti'adha & Basmalah if recited as prelude       │
│  2. Normalizes phonetic text                                │
│  3. Myers 64-bit Bit-Parallel search on pre-indexed index   │
│  4. Ranks candidates by Levenshtein distance                │
└──────────────────────────────┬──────────────────────────────┘
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
┌──────────────────────────────┐ ┌──────────────────────────────┐
│     Unique Match Detected    │ │    Ambiguous / Incomplete    │
│  - Exactly 1 top candidate   │ │  - Multiple candidates       │
│  - Confidence >= 0.85        │ │  - Emits candidate list UI   │
│  - AUTO-NAVIGATE MUSHAF!     │ │  - Awaits further speech     │
└──────────────────────────────┘ └──────────────────────────────┘
```

---

## 3. The Search Engine: Myers 64-Bit Bit-Parallel Search

Traditional database queries (`LIKE '%...%'`) fail miserably for Quranic voice search because:
1. ASR text contains acoustic variations, Madd elongation differences, and phoneme confusion pairs (`س` vs `ص`, `ذ` vs `ز`).
2. Reciters frequently start reciting from the **middle** of a long verse.

`recite_quran` uses **Gene Myers' 64-bit Bit-Parallel algorithm** ([`lib/tracking/ayah_search/fuzzy_search.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/tracking/ayah_search/fuzzy_search.dart)):
- **Bit-Parallel Computation:** Packs 64-character dynamic programming vectors into single CPU 64-bit registers.
- **$O(M)$ Throughput:** Scans the entire 600,000-character normalized Quranic text in less than **$5$ milliseconds** on mobile CPUs.
- **Substring Alignment:** Automatically finds matches anywhere inside a verse—even across verse boundaries (*Wasl* recitation).

---

## 4. Continuous Real-Time Streaming vs One-Shot Search

### Mode A: Continuous Real-Time Streaming (`processRealtime`)
The user holds or taps the microphone and recites. Every audio chunk updates the recognizer and feeds into `processRealtime`:

```dart
final controller = VoiceSearchController(
  engine: sherpaEngine,
  repository: quranRepository,
);

// Subscribe to real-time search results:
controller.currentResult.addListener(() {
  final result = controller.currentResult.value;
  if (result == null) return;

  if (result.isUnique) {
    print('⚡ UNIQUE MATCH! Navigate to Surah ${result.topMatch!.surah}, Ayah ${result.topMatch!.ayah}');
  } else {
    print('Multiple candidates found: ${result.candidates.length}');
  }
});

// Pass live recognized ASR text:
await controller.processRealtime(liveAsrText);
```

### Mode B: One-Shot Candidate Search (`searchCandidates`)
Used when searching via a recorded audio file, a typed phonetic snippet, or after the user finishes speaking:

```dart
final result = await controller.searchCandidates('قلهولاهءحد');

if (result != null && result.candidates.isNotEmpty) {
  for (final match in result.candidates) {
    print('${match.surahNameAr} [${match.surah}:${match.ayah}] - score: ${match.score}');
  }
}
```

---

## 5. Mutashabihat & Progressive Disambiguation

Many Quranic verses share identical openings or phrases (*Mutashabihat*). The engine provides **Progressive Disambiguation**:

### Example: Disjointed Letters (*Alif-Lam-Meem*)
1. Reciter says: `"الم"`
   - `searchCandidates('ءلفلامۦم')`
   - Returns **6 candidates**: Surah 2 (Al-Baqarah), Surah 3 (Ali 'Imran), Surah 29 (Al-'Ankabut), Surah 30 (Ar-Rum), Surah 31 (Luqman), Surah 32 (As-Sajdah).
   - `result.isUnique == false` $\to$ **Auto-navigation is safely suppressed!**
2. Reciter continues: `"ذَٰلِكَ الْكِتَابُ لَا رَيْبَ فِيهِ"`
   - Result immediately narrows to **Surah 2 (Al-Baqarah: 1–2)**.
   - `result.isUnique == true` $\to$ **Mushaf automatically navigates!**

---

## 6. Intelligent Prefix Stripping (Isti'adha & Basmalah)

When users recite an Ayah from memory, they almost always begin with:
- **Isti'adha:** *أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ*
- **Basmalah:** *بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ*

**The Problem:** Naive search engines will match the Isti'adha to Surah An-Nahl (16:98) or the Basmalah to Surah Al-Fatihah (1:1).

**The Solution:** `VoiceSearchController` includes built-in prefix detection:
- If the Isti'adha or Basmalah is detected at the beginning of the audio stream, it is **automatically stripped from the query vector** before searching the rest of the text.
- If the user *only* recited the Basmalah, it accurately returns Surah 1:1.

---

## 7. The `VoiceSearchController` API Reference

### `AyahSearchMatch` Object

```dart
class AyahSearchMatch {
  final int surah;            // 1-indexed Surah number (1..114)
  final int ayah;             // 1-indexed Ayah number within Surah
  final int startAyah;        // Starting Ayah of matched span
  final int endAyah;          // Ending Ayah of matched span
  final double score;         // Confidence score (0.0 to 1.0)
  final int distance;         // Levenshtein edit distance
  final int startWordIdx;     // Word index where alignment began
  final int endWordIdx;       // Word index where alignment ended
  final String? surahNameAr;  // Arabic name (e.g. "البقرة")
  final String? surahNameEn;  // English name (e.g. "Al-Baqarah")
  final String? textUthmani;  // Full Uthmani verse text
  bool get isMultiAyah;       // True if match crosses verse boundary
}
```

### Main Controller Methods

| Method | Description |
| :--- | :--- |
| `preloadIndex()` | Pre-loads the phonetic index synchronously for zero-lag instant searches. |
| `processRealtime(text)` | Streams live recognized speech tokens and updates `currentResult`. |
| `searchCandidates(query)` | Executes an async search and returns `VoiceSearchResult?`. |
| `startListening()` | Begins continuous microphone capture and recognition. |
| `stopListening()` | Stops recording and cleans up search state. |
| `reset()` | Clears current candidate list and resets internal buffer. |

---

## 8. Complete 1-File Voice Navigation Modal Example (Flutter)

Here is a complete, copy-pasteable Flutter modal widget for a **"Recite to Search"** dialog:

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:recite_quran/recite_quran.dart';

class VoiceSearchModal extends StatefulWidget {
  final Function(int surah, int ayah) onVerseSelected;

  const VoiceSearchModal({super.key, required this.onVerseSelected});

  static Future<void> show(BuildContext context, {required Function(int, int) onSelected}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VoiceSearchModal(onVerseSelected: onSelected),
    );
  }

  @override
  State<VoiceSearchModal> createState() => _VoiceSearchModalState();
}

class _VoiceSearchModalState extends State<VoiceSearchModal> {
  late final VoiceSearchController _searchController;
  final SherpaEngine _engine = SherpaEngine();
  bool _isListening = false;
  String _liveTranscript = '';

  @override
  void initState() {
    super.initState();
    _initSearch();
  }

  Future<void> _initSearch() async {
    await Permission.microphone.request();
    await _engine.initialize();

    _searchController = VoiceSearchController(
      engine: _engine,
    );
    _searchController.preloadIndex();

    _searchController.currentResult.addListener(() {
      final res = _searchController.currentResult.value;
      if (res != null && res.isUnique && res.topMatch != null) {
        // Auto-navigate immediately upon unique match!
        widget.onVerseSelected(res.topMatch!.surah, res.topMatch!.ayah);
        Navigator.pop(context);
      }
      setState(() {});
    });

    _startListening();
  }

  Future<void> _startListening() async {
    setState(() => _isListening = true);
    await _searchController.startListening();
  }

  @override
  void dispose() {
    _searchController.stopListening();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _searchController.currentResult.value;
    final candidates = result?.candidates ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Recite any verse...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _isListening ? 'Listening...' : 'Search ready',
            style: TextStyle(color: _isListening ? Colors.green : Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: candidates.isEmpty
                ? const Center(child: Text('Start reciting aloud to find verses across the Quran.'))
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final c = candidates[i];
                      return ListTile(
                        title: Text('Surah ${c.surahNameAr ?? c.surah} (Ayah ${c.ayah})'),
                        subtitle: Text(c.textUthmani ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text('${(c.score * 100).toInt()}% match'),
                        onTap: () {
                          widget.onVerseSelected(c.surah, c.ayah);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

---

## 9. Performance & Production Best Practices

1. **Preload the Search Index:** Call `controller.preloadIndex()` during app startup or splash screen so that when the user opens the search modal, searches execute instantly ($< 5\text{ ms}$).
2. **Handle Background Threads:** `VoiceSearchController` handles Myers bit-parallel search asynchronously, so it will never freeze or stutter your 60/120 FPS Flutter animations.
3. **Always Check `isUnique`:** Only auto-navigate when `result.isUnique == true`. For ambiguous verses (e.g. *الم* or *فبأي آلاء ربكما تكذبان*), display the list of candidate chapters for the user to select or continue reciting.
