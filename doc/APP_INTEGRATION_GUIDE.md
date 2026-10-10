# 📱 Building Production Quran Apps with `recite_quran`

This comprehensive guide walks through the architectural patterns, state management strategies, and UI implementations required to build a production-grade Quran recitation application powered by **`recite_quran`**.

---

## 📑 Table of Contents

1. [Architectural Overview](#1-architectural-overview)
2. [Platform Permissions & Microphone Setup](#2-platform-permissions--microphone-setup)
3. [Model Management Strategy](#3-model-management-strategy)
4. [State Management Pattern (ChangeNotifier / Riverpod / Bloc)](#4-state-management-pattern)
5. [Real-time Mushaf Rendering & Word Highlighting](#5-real-time-mushaf-rendering--word-highlighting)
6. [Tajweed Error Feedback (Pre-built vs Custom UI)](#6-tajweed-error-feedback)
7. [Audio Interruption & Lifecycle Handling](#7-audio-interruption--lifecycle-handling)
8. [Voice Navigation & Candidate Search Modal](#8-voice-navigation--candidate-search-modal)
9. [Performance Best Practices & Production Checklist](#9-performance-best-practices--production-checklist)
10. [Complete 1-File Minimal Working App (lib/main.dart)](#10-complete-1-file-minimal-working-app-libmaindart)

---

## 1. Architectural Overview

A typical Flutter Quran application using `recite_quran` separates audio capture, neural inference, and UI rendering cleanly:

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                     │
│  - Mushaf Word Spans (Green / Yellow / Red)            │
│  - Tajweed Modal Sheet / Custom Dialogs                │
│  - Surah / Ayah Selection & Auto-Scroll Controller     │
└──────────────────────────▲─────────────────────────────┘
                           │ (Stream<WordMatchedEvent>)
┌──────────────────────────┴─────────────────────────────┐
│             State Controller / ViewModel               │
│  - Tracks current Surah, Ayah, active WordIndex        │
│  - Manages mic state & audio streaming lifecycle       │
└──────────────────────────▲─────────────────────────────┘
                           │
┌──────────────────────────┴─────────────────────────────┐
│                 ReciteQuran SDK Core                   │
│  - SherpaEngine (ONNX Zipformer ASR in Background)     │
│  - PhonemeAlignmentIsolate (Dynamic Time Warping)      │
│  - ErrorExplainer (Deterministic Tajweed Matrix)       │
└──────────────────────────▲─────────────────────────────┘
                           │ (Float32 PCM 16kHz)
┌──────────────────────────┴─────────────────────────────┐
│                 AudioProcessor                         │
│  - Hardware DSP filters bypassed for Arabic clarity    │
└────────────────────────────────────────────────────────┘
```

---

## 2. Platform Permissions & Microphone Setup

Because recitation tracking relies on clear speech signals without aggressive noise cancellation filtering Arabic breath consonants (like `هـ`, `ح`, `ع`), proper microphone permissions are mandatory.

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <!-- ... -->
</manifest>
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to listen to your Quran recitation and provide real-time Tajweed and pronunciation feedback.</string>
```

### macOS (`macos/Runner/DebugProfile.entitlements` & `Release.entitlements`)
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

---

## 3. Model Management Strategy

The ONNX neural model (`zipformer_p_arabic_v3.int8.onnx`, ~72 MB) can either be:

1. **Bundled in Assets**: Best for fully offline apps. Download via `dart run recite_quran:download_model` and include in `pubspec.yaml`.
2. **On-Demand Download**: Best for keeping initial app download size under 25 MB on app stores.

```dart
import 'package:recite_quran/recite_quran.dart';

Future<ReciteQuran> setupRecitationEngine({
  required QuranRepository repository,
  Function(double progress, String status)? onProgress,
}) async {
  final downloader = ModelDownloader();
  
  if (!await downloader.isModelReady()) {
    await downloader.downloadAssets(
      onProgress: (progress, status) {
        onProgress?.call(progress, status);
      },
    );
  }

  final modelDir = await downloader.getModelDirectoryPath();
  final engine = SherpaEngine(assetOverrideDir: modelDir);

  final tracker = ReciteQuran(
    repository: repository,
    engine: engine,
    config: TrackerConfig.normal(),
    isTajweed: true,
  );

  await tracker.initialize();
  return tracker;
}
```

---

## 4. State Management Pattern

Here is a production `ChangeNotifier` controller managing recitation state:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:recite_quran/recite_quran.dart';

enum RecitationStatus { idle, initializing, listening, paused, error }

class RecitationController extends ChangeNotifier {
  final ReciteQuran tracker;
  final AudioProcessor _audioProcessor = AudioProcessor();

  RecitationStatus _status = RecitationStatus.idle;
  int _currentSurah = 1;
  int _activeWordIndex = 0;
  final Map<int, WordMatchedEvent> _wordMatches = {};
  String _liveTranscript = '';

  StreamSubscription? _wordSub;
  StreamSubscription? _transcriptSub;

  RecitationController({required this.tracker});

  RecitationStatus get status => _status;
  int get currentSurah => _currentSurah;
  int get activeWordIndex => _activeWordIndex;
  Map<int, WordMatchedEvent> get wordMatches => Map.unmodifiable(_wordMatches);
  String get liveTranscript => _liveTranscript;

  Future<void> initialize() async {
    _status = RecitationStatus.initializing;
    notifyListeners();

    try {
      await tracker.initialize();

      _wordSub = tracker.onWordMatched.listen((event) {
        _wordMatches[event.wordId] = event;
        _activeWordIndex = event.wordId;
        notifyListeners();
      });

      _transcriptSub = tracker.onTranscript.listen((text) {
        _liveTranscript = text;
        notifyListeners();
      });

      setSurah(1);
      _status = RecitationStatus.idle;
      notifyListeners();
    } catch (e) {
      _status = RecitationStatus.error;
      notifyListeners();
    }
  }

  void setSurah(int surahNumber) {
    _currentSurah = surahNumber;
    _wordMatches.clear();
    _activeWordIndex = 0;
    tracker.setTargetSurah(surahNumber);
    notifyListeners();
  }

  /// Switch active Riwayah (e.g. Warsh 'an Nafi', Hafs 'an Asim, Al-Duri)
  Future<void> setRiwayah(QuranRiwayah riwayah, [String? rawiName]) async {
    QiraatAyahMapper? mapper;
    if (rawiName != null && rawiName != 'hafs') {
      mapper = await QiraatAyahMapper.loadForRawi(rawiName);
    }
    tracker.repository.setRiwayah(riwayah, mapper);
    setSurah(_currentSurah);
  }

  /// Update recitation speed dynamically (Tahqiq, Tadweer, Hadr)
  void setRecitationSpeed(RecitationSpeed speed) {
    tracker.updateConfig(tracker.config.copyWith(recitationSpeed: speed));
    notifyListeners();
  }

  Future<void> startListening() async {
    if (_status == RecitationStatus.listening) return;

    _status = RecitationStatus.listening;
    notifyListeners();

    await _audioProcessor.start(
      onChunk: (chunk, isFinal) {
        tracker.feedAudioChunk(chunk, isFinal: isFinal);
      },
    );
  }

  Future<void> stopListening() async {
    if (_status != RecitationStatus.listening) return;

    await _audioProcessor.stop();
    tracker.resetBuffer();
    _status = RecitationStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _wordSub?.cancel();
    _transcriptSub?.cancel();
    _audioProcessor.dispose();
    tracker.dispose();
    super.dispose();
  }
}
```

---

## 5. Real-time Mushaf Rendering & Word Highlighting

A responsive Quran page displays words in authentic RTL Arabic and applies real-time state coloring:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

class MushafSurahView extends StatelessWidget {
  final List<ContinuousQuranWord> words;
  final Map<int, WordMatchedEvent> wordMatches;
  final Function(WordMatchedEvent event, String uthmani) onWordTapped;

  const MushafSurahView({
    super.key,
    required this.words,
    required this.wordMatches,
    required this.onWordTapped,
  });

  Color _resolveColor(int wordIndex) {
    final match = wordMatches[wordIndex];
    if (match == null) return const Color(0xFF2C2C2E); // Default unread text
    if (match.isRed) return const Color(0xFFE53935);    // 🔴 Skipped / Mispronounced
    if (match.tajweedErrors != null && match.tajweedErrors!.isNotEmpty) {
      return const Color(0xFFD97706);                 // 🟡 Tajweed Duration Warning
    }
    return const Color(0xFF16A34A);                    // 🟢 Perfect Match
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SelectableText.rich(
        TextSpan(
          children: words.map((w) {
            final match = wordMatches[w.globalIndex];
            return TextSpan(
              text: '${w.uthmani} ',
              style: TextStyle(
                fontFamily: 'HafsSmart',
                fontSize: 28,
                height: 2.0,
                color: _resolveColor(w.globalIndex),
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  if (match != null) {
                    onWordTapped(match, w.uthmani);
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

## 6. Tajweed Error Feedback

### Approach 1: Pre-Built Bottom Sheet (Ready to use)
Use the included `showTajweedErrorSheet` modal bottom sheet. It adapts automatically to dark mode and includes Arabic/English toggle:

```dart
void handleWordTap(BuildContext context, WordMatchedEvent match, String wordText) {
  if (match.tajweedErrors == null || match.tajweedErrors!.isEmpty) return;

  final errors = match.tajweedErrors!
      .map((map) => ReciterError.fromMap(map))
      .toList();

  showTajweedErrorSheet(
    context,
    errors: errors,
    wordText: wordText,
    isArabic: true,
  );
}
```

### Approach 2: 100% Custom App UI
Consume the raw fields of `ReciterError` to match your app's exact design language:

```dart
class CustomTajweedFeedbackBanner extends StatelessWidget {
  final ReciterError error;

  const CustomTajweedFeedbackBanner({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFDE68A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Text(
                  error.messageAr,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              error.adviceAr,
              style: const TextStyle(fontSize: 14, color: Color(0xFF78350F)),
            ),
            if (error.actualDuration != null && error.expectedDuration != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (error.actualDuration! / error.expectedDuration!).clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFFDE68A),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFD97706)),
              ),
              const SizedBox(height: 4),
              Text(
                'الزمن المقروء: ${error.actualDuration!.toStringAsFixed(2)}ث | المطلوب: ${error.expectedDuration!.toStringAsFixed(2)}ث',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## 7. Audio Interruption & Lifecycle Handling

When users receive phone calls or minimize the app, ensure the audio stream resets gracefully:

```dart
class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> with WidgetsBindingObserver {
  late final RecitationController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause microphone and reset buffer when app is backgrounded
      controller.stopListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ...
    return const Scaffold();
  }
}
```

---

## 8. Voice Navigation & Candidate Search Modal

Users love being able to recite any verse or fragment and jump to it immediately. `recite_quran` provides `VoiceSearchController` with:
- **Bit-Parallel Myers' Substring Search** over all 6,236 Ayahs.
- **Live Candidate Streaming**: As the reciter articulates words, candidates are emitted on `onSearchResult` (`Stream<VoiceSearchResult>`) or `currentResult` (`ValueNotifier<VoiceSearchResult?>`).
- **Progressive Narrowing & Auto-Jump**: When words narrow the match to 1 unique verse, `isUnique == true` fires and `processRealtime` returns the `AnchorResult` immediately.
- **Mutashabihat (متشابهات) Disambiguation**: When an opening phrase matches multiple Ayahs, the UI displays candidate tiles with Arabic Uthmani text and match confidence badges (`96%`). Reciters can either tap any tile to navigate directly or keep reciting.

### Integration Pattern:
```dart
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

class VoiceSearchService {
  final VoiceSearchController controller;

  VoiceSearchService({
    required SherpaEngine engine,
    required QuranRepository repository,
  }) : controller = VoiceSearchController(
         engine: engine,
         repository: repository, // Enriches candidates with Arabic Uthmani text & titles
       );

  Future<void> start(BuildContext context, {required Function(int surah, int ayah) onNavigate}) async {
    await controller.startSearch();

    // Show modal dialog or bottom sheet listening to candidates
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => ValueListenableBuilder<VoiceSearchResult?>(
          valueListenable: controller.currentResult,
          builder: (context, result, _) {
            if (result == null || result.candidates.isEmpty) {
              return const Center(child: Text('Recite any verse…'));
            }

            return ListView.builder(
              itemCount: result.candidates.length,
              itemBuilder: (context, i) {
                final match = result.candidates[i];
                return ListTile(
                  title: Text('${match.surahNameAr} — آية ${match.ayah}'),
                  subtitle: Text(match.textUthmani ?? ''),
                  trailing: Text('${(match.score * 100).toInt()}%'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onNavigate(match.surah, match.ayah);
                  },
                );
              },
            );
          },
        ),
      );
    }
  }
}
```

---

## 9. Performance Best Practices & Production Checklist

- [ ] **Release Mode**: Always test recitation tracking in Flutter `--release` mode. Dart AOT execution gives up to 3x faster DTW alignments than JIT debug mode.
- [ ] **Avoid Rebuilding Full Spans**: Keep `MushafSurahView` optimized. Rebuilding only the active Ayah rather than the entire Surah minimizes UI frame drops.
- [ ] **Isolate Memory Disposal**: Always call `tracker.dispose()` when popping screens to terminate the background Sherpa and Alignment Isolates.
- [ ] **Microphone Permission UX**: Request microphone permission *before* initiating tracking with an explicit user explanation screen.

---

## 10. Complete 1-File Minimal Working App (`lib/main.dart`)

This complete, self-contained file can be placed directly into a new Flutter project's `lib/main.dart`. It handles Quran metadata loading, background ASR, audio streaming, real-time RTL word highlighting, and the Islamic Tajweed bottom sheet with zero external dependencies besides `recite_quran`:

```dart
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: QuranTrackerPage(),
  ));
}

class QuranTrackerPage extends StatefulWidget {
  const QuranTrackerPage({super.key});

  @override
  State<QuranTrackerPage> createState() => _QuranTrackerPageState();
}

class _QuranTrackerPageState extends State<QuranTrackerPage> {
  final QuranMetadataService _metadataService = QuranMetadataService();
  late final QuranRepository _repository;
  ReciteQuran? _tracker;
  final AudioProcessor _audioProcessor = AudioProcessor();

  List<ContinuousQuranWord> _words = [];
  final Map<int, WordMatchedEvent> _matchedWords = {};
  bool _isInitialized = false;
  bool _isRecording = false;
  String _liveTranscript = '';

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    // 1. Initialize Quran Repository and pre-load Surah Al-Fatihah
    _repository = QuranRepository(_metadataService);
    await _repository.loadSurahAsync(1);
    _words = _repository.getSurahWords(1);

    // 2. Initialize tracking engine
    _tracker = ReciteQuran(
      repository: _repository,
      config: TrackerConfig.normal(),
      isTajweed: true,
    );

    await _tracker!.initialize();
    _tracker!.setTargetSurah(1);

    // 3. Listen to real-time word matches
    _tracker!.onWordMatched.listen((event) {
      if (mounted) {
        setState(() {
          _matchedWords[event.wordId] = event;
        });
      }
    });

    // 4. Listen to live ASR phonetic transcript
    _tracker!.onTranscript.listen((transcript) {
      if (mounted) {
        setState(() {
          _liveTranscript = transcript;
        });
      }
    });

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  Future<void> _toggleMic() async {
    if (_tracker == null || !_isInitialized) return;

    if (_isRecording) {
      await _audioProcessor.stop();
      _tracker!.resetBuffer();
      setState(() => _isRecording = false);
    } else {
      setState(() => _isRecording = true);
      await _audioProcessor.start(
        onChunk: (Float32List chunk, bool isFinal) {
          _tracker!.feedAudioChunk(chunk, isFinal: isFinal);
        },
      );
    }
  }

  Color _resolveWordColor(int wordIndex) {
    final match = _matchedWords[wordIndex];
    if (match == null) return Colors.black87; // Unspoken
    if (match.isRed) return Colors.red.shade700; // Skipped / Mispronounced
    if (match.tajweedErrors != null && match.tajweedErrors!.isNotEmpty) {
      return Colors.amber.shade800; // Tajweed Duration Warning
    }
    return Colors.green.shade700; // Correct Match
  }

  @override
  void dispose() {
    _audioProcessor.dispose();
    _tracker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ReciteQuran Tracker'),
        backgroundColor: const Color(0xFFB8860B),
        foregroundColor: Colors.white,
      ),
      body: !_isInitialized
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFB8860B)),
                  SizedBox(height: 16),
                  Text('Initializing ASR Engine & Quran Database…'),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Mushaf Display
                  Expanded(
                    child: SingleChildScrollView(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: _words.map((w) {
                              final match = _matchedWords[w.globalIndex];
                              return TextSpan(
                                text: '${w.uthmani} ',
                                style: TextStyle(
                                  fontSize: 30,
                                  height: 2.2,
                                  color: _resolveWordColor(w.globalIndex),
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    if (match?.tajweedErrors != null &&
                                        match!.tajweedErrors!.isNotEmpty) {
                                      final errors = match.tajweedErrors!
                                          .map((m) => ReciterError.fromMap(m))
                                          .toList();
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
                      ),
                    ),
                  ),

                  // Real-time transcript display
                  if (_liveTranscript.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'ASR: $_liveTranscript',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),

                  // Floating Microphone Toggle Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording
                            ? Colors.red.shade700
                            : const Color(0xFFB8860B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _toggleMic,
                      icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                      label: Text(
                        _isRecording ? 'Listening… (Tap to Stop)' : 'Start Reciting',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
