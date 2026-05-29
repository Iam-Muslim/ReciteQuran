 <div align="center"> ولقد يسرنا القرآن للذكر فهل من مدكر  </div>


 


# Real-Time Quran Recitation Tracker
An offline Android app that listens to your Quran recitation and tracks your progress word-by-word in real time.

<br>
<div align="center">
  <a href="https://recitequran.pages.dev/">
    <img src="https://img.shields.io/badge/Download-For android-2ea44f?style=for-the-badge&logo=download" alt="Recite Quran Download" />
  </a>
</div>

## Screenshots


<img width="270" height="585" alt="Screenshot_20260525-181306_Recite Quran" src="https://github.com/user-attachments/assets/6b5a7e9b-9b94-49a0-b45b-a8cb7177a004" />

<img width="270" height="585" alt="Screenshot_20260525-181234_Recite Quran" src="https://github.com/user-attachments/assets/81411b9e-79a1-490d-81fc-606895efeace" />

<img width="270" height="585" alt="Screenshot_20260525-181317_Recite Quran" src="https://github.com/user-attachments/assets/0c56f56c-7fe9-49f9-b570-0a118cece212" />
<br>
<img width="279" height="585" alt="White-Record" src="https://github.com/user-attachments/assets/cc9d6265-f3c2-4f5a-ab73-7ad25bd39e91" />


<img width="270" height="585" alt="White-Surah Selection" src="https://github.com/user-attachments/assets/29abec1c-9a14-45b6-a3d1-94d116fba593" />

<img width="270" height="585" alt="White-Setting" src="https://github.com/user-attachments/assets/c89e8bbd-13cf-47d4-b957-85c896dca8c1" />


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
│       └── tagweed_screen.dart
    tajweed/
    ├── rules/
    │   ├── noun_rules.dart       # Nun/Mim Sakina and Tanwin rules
    │   ├── lam_rules.dart        # Lam rules (Shamsi/Qamari)
    │   ├── madd_rules.dart       # Madd/Gunnah rules
    │   ├── raa_rules.dart        # Raa rules (tafkhim/tarqiq)
    │   ├── hamza_rules.dart      # Hamza rules
    │   └── stop_rules.dart       # Waqf rules
    └── utils/
        ├── tajweed_analyzer.dart # Analyzes recitation for tajweed violations
         └── tajweed_rules.dart    # Common tajweed rules for reference
         
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

 
 **هذا من فضل ربي — الحمد لله** سبحان الله عما يصفون
## Projects Used
 [Yazinsai Offline-Tarteel](https://github.com/yazinsai/offline-tarteel) - Onnx Model , Normalizing , Decoding and ...
 <br>
 [FastConformer ar CTC model-Yazinsai](https://github.com/yazinsai/offline-tarteel/releases/tag/v0.1.0)
 <br>
 [Abdullah (obadx)](https://github.com/obadx) for the original Quran Muaalem model and research
 <br>
 [Quran Muaalem IOS App - itarek](https://github.com/iTarek/Quran-Muaalem-iOS)





