 <div align="center">  بسم الله الرحمن الرحيم </div>
<br>
 <div align="center"> ولقد يسرنا القرآن للذكر فهل من مدكر  </div>


 
<br><br>

<div align="center">
  <a href="https://recitequran.pages.dev/">
    <img src="https://img.shields.io/badge/Download-For android-2ea44f?style=for-the-badge&logo=download" alt="Recite Quran Download" />
  </a>
</div>
<br>

# Real-Time Quran Recitation Tracker
An offline Android app that listens to your Quran recitation and tracks your progress word-by-word in real time.


## Screenshots




## Features
- **Real-time word tracking** — highlights each word as you recite it
- **100% Offline** — all audio processing happens on-device, zero internet required
- **Mistake detection** — skipped or mispronounced words are highlighted differently
- **Adjustable settings** — mistake sensitivity, lookahead words, font size
- **Hide/Reveal mode** — hides unrecited words for memorization (Hifz) practice
- **Reading mode** — auto-scroll for reading without recording

# Developing 
##  Architecture
```
lib/
├── core/
│   ├── app_state.dart        # Global state (theme, language, settings)
│   └── types.dart            # Shared types (TrackerState, VerseMatch)
├── data/
│   ├── models/
│   │   ├── quran_data.dart       # QuranVerse model
│   │   └── quran_repository.dart # In-memory verse store with surah cache
│   └── quran_metadata_service.dart # Loads quran.json in background Isolate
├── engine/
│   ├── sherpa_engine.dart        # Sherpa-ONNX ASR in dedicated Isolate
│   └── segmentation_service.dart # Splits ASR text into words
├── recording/
│   ├── audio_processor.dart      # Microphone capture + VAD
│   └── live_recitation_controller.dart # Word-by-word matching engine
├── screens/
│   ├── tracking_screen.dart      # Main recitation screen
│   └── widgets/
│       ├── verse_row.dart        # Fingerprint-diffed verse display
│       ├── mic_bar.dart          # Bottom action toolbar
│       ├── surah_picker.dart     # Surah selection sheet
│       └── settings_dialog.dart  # Settings bottom sheet
├── utils/
│   └── normalizer.dart           # Arabic text normalization
└── main.dart                     # Entry point + Orchestrator
```

### Audio Pipeline
```
Microphone (16kHz PCM)
    ↓
AudioProcessor (VAD + buffering)
    ↓ chunks every 300ms
SherpaEngine (Isolate, Sherpa-ONNX CTC)
    ↓ transcription text
LiveRecitationController (word matching)
    ↓ green/red/amber state
VerseRow (fingerprint-diffed UI)
```

### Performance Design
- **Fingerprint-based diffing**: Each `VerseRow` computes a compact hash of its visual state. Only verses whose fingerprint changed rebuild their `TextSpan` tree. This prevents O(N) rebuilds on every ASR result.
- **Engine busy-check**: The ASR Isolate drops intermediate audio chunks if it's still processing the previous one. This prevents thermal throttling death spirals.
- **Sliding window**: Only the most recent 2s of audio is sent for inference, capping inference time regardless of how long the user has been speaking.

## 📂 Assets
- `assets/model/quran.json` — Complete Quran metadata (6236 verses)
- `assets/model/fastconformer_ar_ctc_q8.onnx` — Sherpa-ONNX Arabic ASR model (quantized)
- `assets/model/tokens.txt` — CTC decoder token vocabulary
- `assets/fonts/UthmanicHafs_V22.ttf` — Uthmanic Hafs Quran font


**هذا من فضل ربي — الحمد لله**

سبحان الله عما يصفون


