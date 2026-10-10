# 📖 Interactive Mus'haf UI, Typography & Page Layout Guide

A comprehensive architectural and UI guide for building beautiful, authentic, and high-performance **Mus'haf Readers** with word-by-word real-time highlighting and auto-scrolling using **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Introduction: UI Paradigms in Modern Quran Apps](#1-introduction-ui-paradigms-in-modern-quran-apps)
2. [Authentic Quran Typography & Uthmanic Fonts](#2-authentic-quran-typography--uthmanic-fonts)
   - [Recommended Fonts (KFGQPC, Amiri Quran)](#recommended-fonts-kfgqpc-amiri-quran)
   - [Handling Diacritics (Tashkeel) & Verse End Glyphs (Ayah Markers)](#handling-diacritics-tashkeel--verse-end-glyphs)
3. [Layout Architectures: Page View vs Continuous Flow](#3-layout-architectures-page-view-vs-continuous-flow)
   - [Paradigm A: Authentic 15-Line Madani Page View (604 Pages)](#paradigm-a-authentic-15-line-madani-page-view)
   - [Paradigm B: Continuous Flowing Ayah List](#paradigm-b-continuous-flowing-ayah-list)
4. [Word Highlighting State & Color Design](#4-word-highlighting-state--color-design)
5. [Smooth Auto-Scrolling & Active Line Centering](#5-smooth-auto-scrolling--active-line-centering)
6. [Automatic Page Turning on Recitation](#6-automatic-page-turning-on-recitation)
7. [Complete 1-File Working Mushaf Viewer (Flutter)](#7-complete-1-file-working-mushaf-viewer-flutter)
8. [Performance Best Practices (60/120 FPS Flutter Rendering)](#8-performance-best-practices)

---

## 1. Introduction: UI Paradigms in Modern Quran Apps

When users recite the Holy Quran in an app like Tarteel AI, the visual interface must feel sacred, beautiful, and completely fluid. As words are spoken, the visual cursor must highlight each word with zero stutter, keeping the reciter's focal point comfortable.

`recite_quran` provides the underlying word tokens (`ContinuousQuranWord`), global word indices, and boundary markers, giving developers total flexibility to design:
1. **Classic 15-line Madani Mus'haf** layout (identical to the physical printed Mus'haf).
2. **Modern Responsive Reading view** (custom font sizes, night mode, vertical auto-scroll).

---

## 2. Authentic Quran Typography & Uthmanic Fonts

### Recommended Fonts

Using generic system Arabic fonts (like Roboto or Arial) is unacceptable for Quran applications because they do not support authentic Uthmanic diacritics, Madd signs, or stops (*Waqf* symbols).

| Font Family | Provider | Features |
| :--- | :--- | :--- |
| **KFGQPC Uthman Taha Naskh** | King Fahd Complex (Madinah) | The gold standard. Exactly matches the printed Madani Mus'haf. |
| **Amiri Quran** | Khaled Hosny / Google Fonts | Open-source typeface with extensive Quranic OpenType ligature support. |
| **Me Quran** | Tanzil Project | Lightweight, widely used for web and mobile Quran readers. |

### Declaring Quranic Fonts in `pubspec.yaml`

```yaml
flutter:
  fonts:
    - family: KFGQPC
      fonts:
        - asset: assets/fonts/KFGQPC_Uthman_Taha_Naskh.otf
```

### Verse End Marker (علامة نهاية الآية)
In Uthmanic text, the verse end symbol is unicode `\u06DD` (Arabic End of Ayah: ۝) containing the Ayah number:

```dart
String formatAyahWithEndMarker(String ayahText, int ayahNumber) {
  // Convert number to Eastern Arabic numerals (١, ٢, ٣...)
  final arabicNum = ayahNumber.toString().replaceAllMapped(
    RegExp(r'\d'),
    (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) + 1584),
  );
  return '$ayahText \u06DD$arabicNum ';
}
```

---

## 3. Layout Architectures: Page View vs Continuous Flow

### Paradigm A: Authentic 15-Line Madani Page View
- Exactly **604 pages**.
- Every page begins and ends at fixed Ayah points (except Surah Al-Baqarah Ayah 282 which occupies an entire page).
- Best for experienced memorizers (*Huffadh*) who have photographic memory of page corners.

### Paradigm B: Continuous Flowing Ayah List
- Verses flow vertically in a single continuous scrollable view.
- Supports adjustable font scaling for elderly readers or low-vision users.
- Ideal for hands-free dictation tracking on smartphones held in one hand.

---

## 4. Word Highlighting State & Color Design

Every word in the active view resolves to one of four visual states:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Neutral (Unrecited): Normal dark font, transparent bg    │
│ 2. Active (Pending): Subtle amber pulsing border            │
│ 3. Matched (Valid): Soft green background (rgba(0,180,0,0.15)│
│ 4. Tajweed Warning: Warm yellow background                   │
│ 5. Skipped / Error: Soft red background                      │
└─────────────────────────────────────────────────────────────┘
```

```dart
Color getWordBackgroundColor(int wordIndex, Map<int, WordMatchedEvent> matches, int activeWordIndex) {
  if (wordIndex == activeWordIndex) {
    return Colors.amber.withOpacity(0.2); // Currently active
  }
  final match = matches[wordIndex];
  if (match == null) return Colors.transparent;

  if (match.isRed) return Colors.red.withOpacity(0.2);
  if (match.tajweedErrors != null && match.tajweedErrors!.isNotEmpty) {
    return Colors.amber.withOpacity(0.25);
  }
  return Colors.green.withOpacity(0.2);
}
```

---

## 5. Smooth Auto-Scrolling & Active Line Centering

To prevent the active word from scrolling off-screen while the user is reciting hands-free:

```dart
final ScrollController _scrollController = ScrollController();
final Map<int, GlobalKey> _wordKeys = {};

void scrollToActiveWord(int wordIndex) {
  final key = _wordKeys[wordIndex];
  if (key?.currentContext == null) return;

  Scrollable.ensureVisible(
    key!.currentContext!,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeInOutCubic,
    alignment: 0.4, // Keep active word positioned at 40% from top of screen
  );
}
```

---

## 6. Automatic Page Turning on Recitation

When the user finishes reciting the final word of the active page:
1. Detect that `event.wordId == lastWordOfCurrentPage`.
2. Automatically trigger `PageController.nextPage()` with a smooth page-turn animation.
3. Update `tracker.setTargetSurah(nextSurah)` if the page crosses a Surah boundary.
4. Continue feeding audio seamlessly without stopping the microphone stream.

---

## 7. Complete 1-File Working Mushaf Viewer (Flutter)

Here is a complete, production-ready Flutter screen implementing an interactive Mus'haf reader with real-time word highlighting, auto-scroll, and hands-free microphone tracking:

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MushafReaderScreen(),
  ));
}

class MushafReaderScreen extends StatefulWidget {
  const MushafReaderScreen({super.key});

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  final QuranMetadataService _metadata = QuranMetadataService();
  late final QuranRepository _repo;
  ReciteQuran? _tracker;
  final AudioProcessor _audio = AudioProcessor();
  final ScrollController _scrollController = ScrollController();

  List<ContinuousQuranWord> _words = [];
  final Map<int, WordMatchedEvent> _matches = {};
  final Map<int, GlobalKey> _wordKeys = {};
  int _activeWordIndex = 0;
  bool _isTracking = false;
  int _activeSurah = 1; // Al-Fatiha

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

    for (final w in _words) {
      _wordKeys[w.globalWordIndex] = GlobalKey();
    }

    _tracker = ReciteQuran(
      repository: _repo,
      config: const TrackerConfig(
        enableEarlyMatching: true,
        enableAutoReanchor: true, // Strongly recommended: enables magical hands-free page following!
        reanchorStallThreshold: 24,
      ),
      isTajweed: false, // Dictation page-reading mode
    );

    await _tracker!.initialize();
    _tracker!.setTargetSurah(_activeSurah);

    _tracker!.onWordMatched.listen((WordMatchedEvent event) {
      if (mounted) {
        setState(() {
          _matches[event.wordId] = event;
          _activeWordIndex = event.wordId + 1;
        });
        _scrollToWord(event.wordId);
      }
    });
  }

  void _scrollToWord(int wordId) {
    final key = _wordKeys[wordId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
    }
  }

  Future<void> _toggleTracking() async {
    if (_tracker == null) return;

    if (_isTracking) {
      await _audio.stop();
      setState(() => _isTracking = false);
    } else {
      await _audio.start(
        onChunk: (Float32List chunk, bool isFinal) {
          _tracker!.feedAudioChunk(chunk, isFinal: isFinal);
        },
      );
      setState(() => _isTracking = true);
    }
  }

  @override
  void dispose() {
    _audio.stop();
    _tracker?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F1), // Classic Mus'haf cream paper color
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332), // Islamic deep green
        foregroundColor: Colors.white,
        title: const Text('المصحف الشريف (Surah Al-Fatiha)'),
        actions: [
          IconButton(
            icon: Icon(_isTracking ? Icons.mic : Icons.mic_off),
            color: _isTracking ? Colors.greenAccent : Colors.white70,
            onPressed: _toggleTracking,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 10,
              children: _words.map((word) {
                final match = _matches[word.globalWordIndex];
                final bool isCurrent = word.globalWordIndex == _activeWordIndex;

                Color bg = Colors.transparent;
                Color textCol = const Color(0xFF2D3142);

                if (match != null) {
                  if (match.isRed) {
                    bg = const Color(0xFFFFD6D6);
                    textCol = Colors.red.shade900;
                  } else {
                    bg = const Color(0xFFD8F3DC);
                    textCol = const Color(0xFF081C15);
                  }
                } else if (isCurrent) {
                  bg = const Color(0xFFFFF3CD);
                }

                return Container(
                  key: _wordKeys[word.globalWordIndex],
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                    border: isCurrent
                        ? Border.all(color: Colors.amber.shade700, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    word.textUthmani,
                    style: TextStyle(
                      fontSize: 26,
                      color: textCol,
                      fontFamily: 'KFGQPC',
                      height: 1.8,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 8. Performance Best Practices (60/120 FPS Flutter Rendering)

1. **RepaintBoundaries:** Wrap high-frequency widgets in `RepaintBoundary` so that updating a single word's highlight color does not trigger a full layout re-pass across the entire chapter.
2. **Key Recycling:** Pre-create and cache `GlobalKey` instances for words during initialization rather than instantiating new keys inside `build()`.
3. **Cream Paper Contrast:** Traditional Mus'haf paper uses warm off-white or soft cream (`#FBF9F1` or `#F4EBD9`). Use dark charcoal (`#2D3142`) rather than pure black for typography to reduce eye strain during extended night recitation.
