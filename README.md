> *"And We have certainly made the Quran easy for remembrance, so is there any who will remember?"* — Al-Qamar 54:17

  # ما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ
before using any single character of codes here , you agree to this :
**For The Sake Of Allah only** if you used this app or the source code in any other work you aren't allowed to get from it any money or make profit from it and you have to mention that this app is for the sake of Allah only .
 (never sell or gain money from any work has any of this project )
 
(1) you may use and redistribute it ONLY in applications that are FREE to end users

(2) you are NOT allowed to sell it, place it behind a paid subscription or paywall, monetize it with ads, or earn any revenue from an app or service that uses this model or its outputs or this app or this codes or logics;

(3) these terms pass on to anyone you share it with.


---

<img width="139" height="292" alt="Screenshot_20260628-164337_Recite Quran" src="https://github.com/user-attachments/assets/42fc7e30-8a39-44bf-a4b9-9a3b48135e94" /><img width="139" height="292" alt="Screenshot_20260628-164253_Recite Quran" src="https://github.com/user-attachments/assets/357b58a4-3a84-4880-bce6-856c0092f211" /><img width="139" height="292" alt="Screenshot_20260628-164411_Recite Quran" src="https://github.com/user-attachments/assets/71bc8cb1-0c01-4eee-8053-3427fa0e0f99" /><img width="139" height="292" alt="Screenshot_20260628-164242_Recite Quran" src="https://github.com/user-attachments/assets/ce275229-65fd-435d-921e-de590eeecba6" />


---



## What Is This Project?

**ReciteQuran** is a Flutter mobile application that listens to a user reciting the Holy Quran, word by word, and highlights each word as **correct (green)**, **wrong (red)**, or **has a Tajweed error (yellow)**.

It runs **entirely on-device**, with no internet connection needed. An Arabic ASR (Automatic Speech Recognition) model runs live in the background, converting your voice into phonetic Arabic text in real-time.


---

## Table of Contents

1. Elhamdule Allah
2. [How the Architecture Works](#how-the-architecture-works)
3. [Data Files — The JSON Assets](#data-files--the-json-assets)
4. [The Audio Pipeline](#the-audio-pipeline)
5. [The ASR Engine (Sherpa-ONNX)](#the-asr-engine-sherpa-onnx)
6. [The Tracking Pipeline — Real-Time](#the-tracking-pipeline--real-time)
7. [The Tajweed Pipeline — Post-Ayah](#the-tajweed-pipeline--post-ayah)
8. [Voice Navigation — "Recite to Find"](#voice-navigation--recite-to-find)
9. [The Phonetic Representation System](#the-phonetic-representation-system)
10. [Directory Structure](#directory-structure)
11. [Known Limitations & Open Tasks](#known-limitations--open-tasks)

Docs .md files may not be updated according to the latest project version
---

## How the Architecture Works

Think of it like an assembly line:

```
Microphone
    ↓
AudioProcessor (VAD — silence detection + chunking)
    ↓
SherpaEngine (Isolate — ONNX model inference)
    ↓
HighlightingController (word-matching brain)
    ↓
PhoneticWordTracker (per-ayah DP alignment)
    ↓
UI (TrackingScreen → VerseRow → word highlighting)
```

Each arrow is a Dart `Stream`. No step blocks the UI thread.

### Phase 1: Real-Time Green/Red Highlighting

As you speak each word, `PhoneticWordTracker` uses a **streaming Levenshtein DP** to find where in the reference phoneme list your voice currently is. When it passes a word boundary, the word turns:
- **Green** → you said it correctly
- **Red** → you skipped or mispronounced it

### Phase 2: Post-Ayah Tajweed Check (Yellow)

When you finish the last word of an Ayah, `HighlightingController` calls `ErrorExplainer.explainAyahError`. This takes the **entire accumulated predicted text** and the **entire expected phoneme string** for that Ayah and runs a global alignment. Green words with Tajweed/Tashkeel errors are then turned **yellow**.

---

## Data Files — The JSON Assets

### `assets/model/ordered_quran_phonemes.json`

**~8.6 MB.** The most important file in the entire project. Contains **all 6,236 Ayahs** of the Quran in this schema:

```json
"6:137": {
    "aya_text": "وَكَذَٰلِكَ زَيَّنَ ...",
    "aya_phoneme": "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِم...",
    "aya_ui": "  invisible Unicode word-boundary markers  ",
    "aya_phonemes_list": [
        "وَكَذَاالِكَ",
        "زَييَنَ",
        "لِكَثِۦۦرِ",
        ...
    ],
    "suraname_en": "Al-An'am",
    "suraname_ar": "الأنعام"
}
```

| Field | What it is |
|---|---|
| `aya_text` | The official Uthmani Hafs script shown in the UI |
| `aya_phoneme` | **CTC model output format** — what the ASR model actually outputs when it hears this Ayah. Not clean text, it's "frame-level" phonetic. See [Phonetic Representation](#the-phonetic-representation-system). |
| `aya_ui` | Special Unicode characters that encode word boundaries for the Uthmani display text. Used to split `aya_text` into individual words. |
| `aya_phonemes_list` | `aya_phoneme` pre-split into one string per word. Used in the Post-Ayah Tajweed phase. |

> **Important for contributors:** `aya_ui` uses invisible Unicode markers (like U+200F, U+200E). Do not delete these characters when editing the JSON. They are the word separators for the Uthmani text.

---

### `assets/model/ph_index.txt` & `assets/model/ph_index.npy`

These files power the Voice Navigation feature.

- **`ph_index.txt` (~350 KB):** A continuous string of the bare phonetic characters for the entire Quran.
- **`ph_index.npy` (~2.4 MB):** A binary NumPy array mapping every character index in the `.txt` file back to its exact `(Surah, Ayah, Word)` index.

The new **Fuzzy Search (Levenshtein)** algorithm uses these to find any spoken verse with high accuracy, even with slight mispronunciations.

### `assets/model/tokens.txt`

The vocabulary file for the Sherpa-ONNX ASR model. Maps integer token IDs to Arabic phoneme characters. Each line is one character that the model can output.

---

## The Audio Pipeline

**File:** `lib/audio/audio_processor.dart`

The `AudioProcessor` is responsible for:

1. **Starting the microphone** using the `record` package (PCM 16-bit, 16kHz, mono)
2. **VAD (Voice Activity Detection)** — detecting when you START and STOP speaking
3. **Chunking** — grouping speech frames into 160ms chunks and sending them to Sherpa

### How the VAD Works

The VAD is a simple adaptive noise-floor tracker:

- It continuously measures the **RMS (Root Mean Square) energy** of each 20ms audio frame
- While you are NOT speaking, it updates a slow-moving `_noiseFloor` average
- The **VAD threshold** = `noiseFloor × 2.0` (SNR of 2)
- When RMS > threshold → speech detected
- When 40 consecutive silent frames (800ms) pass → end of speech phrase

**Example flow:**
```
Frame  1-5:   Silence   → RMS=45,  noiseFloor=46,  threshold=92,   SILENT
Frame  6:     You speak → RMS=850, noiseFloor=46,  threshold=92,   SPEAKING! → pre-roll emitted
Frame  7-30:  Speaking  → 160ms chunks sent to Sherpa every ~8 frames
Frame  31-70: Silence   → silenceCount ticks up. After 40 frames: VAD OFF
```

**Pre-roll buffer:** The last 600ms of audio before speech is detected is included in the first chunk sent to Sherpa. This prevents the model from missing the very start of a word.

---

## The ASR Engine (Sherpa-ONNX)

**File:** `lib/engine/sherpa_engine.dart`

Sherpa-ONNX runs the `quran_phoneme_zipformer.int8.onnx` model inside a **Dart Isolate** (a separate thread). This is critical — ONNX inference is CPU-heavy and would freeze the UI if run on the main thread.

### What is a ZipFormer CTC Model?

- **ZipFormer:** A fast transformer encoder architecture optimized for streaming ASR
- **CTC (Connectionist Temporal Classification):** A decoding strategy that aligns audio frames to characters WITHOUT needing explicit segmentation
- **INT8 Quantized:** The model weights are stored in 8-bit integers instead of 32-bit floats. ~4x smaller, ~2x faster, tiny accuracy loss.

### Length-Aware Phonetic Encoding — The Critical Concept

> **This is the most important thing to understand for contributors.**

The advanced Zipformer model is trained to be **Tajweed and Madd aware**. It does NOT output clean text. It outputs frame-level phonetic alignments where **time duration is encoded as repeated characters**. 

If a user speaks `بِسمِ` slowly and holds the Madd, the model outputs raw frames like:

```
Raw output: "بسسسممللااهرررحمننرحييم"
```

Unlike traditional ASR systems that collapse these duplicates, this project **preserves the raw repeated output entirely**. The reference text in `ordered_quran_phonemes.json` is perfectly aligned to expect these exact repetitions.

**The DP Solution:** When comparing the streaming output against reference text, the 3D Wraparound DP matrix compares the raw length-encoded audio stream against the raw length-encoded expected text. The `k` (wraparound) dimension helps absorb any minor acoustic stutters without penalizing them as hard errors.

### Communication Flow

```
main thread: SherpaEngine.transcribe(chunk) 
    → sends chunk via SendPort to Isolate
    
Isolate: stream!.acceptWaveform() → recognizer.decode() → recognizer.getResult()
    → sends result back via mainSendPort

main thread: transcriptionStream.add(TranscriptionResult)
    → HighlightingController.feed() picks this up
```

---

## The Tracking Pipeline — Real-Time

### `lib/tracking/quran_normalizer.dart`

Before any comparison happens, both the ASR output and the reference words are "normalized" to remove sources of false mismatch.

**What it removes:**
- All harakat/tashkeel (ً ٌ ٍ َ ُ ِ ّ ْ) → so `بِسمِ` and `بسم` match
- Alef maksura ى → alef ا
- Hamzat wasl ٱ → alef ا
- Small alef (U+0670)
- Spaces

**What it explicitly PRESERVES (for Tajweed evaluation):**
- Sakt (Small seen above: `\u06E3`)
- Ishmam (`\u0658`)
- Tasheel (`\u065F`)
- Imala (`\u065E`)

**Example:**
```
Input:    "ٱلرَّحْمَـٰنِ"
Output:   "الرحمن"
```

### `lib/tracking/phonetic_word_tracker.dart`

**This is the core real-time word matching engine.** It is a **100% mathematical port of the QUA SDK's 3D Wraparound DP**, adapted for a real-time sliding window.

**The concept (explained simply):**
Instead of naive substring searches, it runs a 3-Dimensional Dynamic Programming matrix over the incoming audio chunk (`P`) and the dynamically estimated expected window (`R`).

1. **Strict Word Boundaries:** The DP is forced to evaluate scores only at exact `wordEnds`, preventing hallucinated matches on partial syllables.
2. **Dense Arabic Sub-Matrix:** Emphatic pairs (`ص/س`), Nasals (`ن/م`), and Alifs cost only `0.25` to swap, granting hyper-accurate phonetic leniency, while completely wrong letters cost `1.0`.
3. **Wraparound for Stutters:** A 3rd dimension (`k` wraps) allows the DP to jump backward in the matrix to a `wordStart` if you stutter or repeat a word. It subtracts a `wrapPenalty` so your phonetic distance score isn't ruined by an ASR CTC stutter.
4. **Spatial Prior Weighting:** Instead of hardcoded if-statements for skipping, it adds an automatic score penalty `prior_weight * abs(matched_word - expected_word)`. The math itself forces the matrix to find the best local word, seamlessly handling skips.

### Matching Level (Easy vs Strict)

The tracker operates in two user-configurable modes:
- **Easy Mode:** Uses the Levenshtein distance. If you are slightly off (e.g., one character), the engine can still score you > 50% and highlight the word green.
- **Strict Mode:** Disables Levenshtein distance completely. If the raw ASR output does not 100% identically match the expected phoneme, it forces an accuracy of `0.0`.
*(This feature operates entirely independently of the Auto-Skip / Lookahead feature).*

### `lib/tracking/highlighting_controller.dart`

The bridge between the ASR engine and the UI. It:
1. Subscribes to `SherpaEngine.transcriptionStream`
2. Routes each new transcription to the correct `PhoneticWordTracker` for the active Ayah
3. Reads the tracker's word statuses and updates the green/red/yellow highlight sets
4. Triggers the post-Ayah `ErrorExplainer` when an Ayah is complete
5. Automatically advances to the next Ayah

---

## The Tajweed Pipeline — Post-Ayah

**File:** `lib/tracking/matchers/error_explainer.dart`

When an Ayah finishes (all words matched or skipped), `explainAyahError` runs a **global alignment** of the entire predicted string against the entire expected `aya_phoneme` string.

### Step 1: Raw Frame Extraction

Before alignment, both strings are chunked into atomic phonetic units (a base consonant + its harakat) using `QuranNormalizer.chunkPhonemes`. 
Critically, **no CTC collapse filter is applied**. The raw length and timing data of the model is preserved exactly as spoken.

**Why?** The model uses repeated characters to denote the length of sounds (like `نننن` for a 2-beat Ghunnah or `اااا` for a Madd). Collapsing these would destroy the timing data needed to validate Tajweed rules.

### Step 2: Levenshtein Alignment on Phoneme Groups

The algorithm runs Levenshtein alignment on the collapsed phoneme groups and produces edit operations: `equal`, `replace`, `insert`, `delete`.

### Step 3: Error Classification

Each non-`equal` alignment is classified:

| Condition | Error Type | Meaning |
|---|---|---|
| `replace` / `delete` / `insert` | `ErrorCategory.normal` | Wrong consonant entirely |
| Tajweed Mismatch (Hams, Tafkheem, Qalqalah, Ghunnah) | `ErrorCategory.tajweed` | Violated an exact phonetic group constraint (e.g. whispered a Tafkheem letter) |
| `equal` but different lengths (> 1 char difference) | `ErrorCategory.tajweed` | Madd/Ghunna length error (e.g. held too short/long) |
| `equal` but different lengths (≤ 1 char difference) | `ErrorCategory.tashkeel` | Harakat error (wrong vowel on consonant) |

### Step 4: Word Attribution

Each error is mapped back to a word index using the `refGroupToWord` list built at the start. The `HighlightingController` then turns those specific words from **green** to **yellow**.

**Terminal output during a session:**
```
[Tajweed] Ayah complete. Running global explainAyahError.
[ErrorExplainer] === START GLOBAL TAJWEED EVALUATION ===
[ErrorExplainer] Raw Expected: "بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم"
[ErrorExplainer] Raw Predicted: "بسسسممللااهرررحمننرحييم"
[ErrorExplainer] Reference Groups: [بِ, س, مِ, ل, لَ, ا, ا, هِ, ...]
[ErrorExplainer] Predicted Groups: [ب, س, س, س, م, م, ل, ل, ا, ه, ...]
[ErrorExplainer] Output Errors By Word Index:
[ErrorExplainer]   -> Word 2: [ErrorCategory.tashkeel]
[ErrorExplainer] === END GLOBAL TAJWEED EVALUATION ===
[Tajweed] Word 2 turned YELLOW due to errors: [ReciterError(type: tashkeel, ...)]
```

---

## Voice Navigation — "Recite to Find"

**Files:** `lib/tracking/voice_search_controller.dart`, `lib/tracking/matchers/phonetic_search.dart`, `lib/tracking/matchers/fuzzy_search.dart`

This feature lets the user **press on record in surah selector** and recite any verse. The app will then automatically navigate to that Surah and Ayah.

### How It Works

1. **Long-press mic** → `_startVoiceSearch()` called in `main.dart`
2. Audio is fed to Sherpa like normal, but the accumulated `TranscriptionResult.text` is stored in `_voiceSearchAsrText` instead of being sent to the word tracker
3. **Sop reciting** → `VoiceSearchController.stopSearch(asrText)` called
4. The predicted text is normalized (with Tashkeel preserved).
5. `PhoneticSearch` runs a highly optimized fuzzy search algorithm to find the closest match.

### The Fuzzy Search Algorithm (Levenshtein)

Instead of rigid N-grams, the app uses a custom Dynamic Programming (Levenshtein distance) algorithm over the entire Quran phonetic string (`ph_index.txt`).

- **Tolerance:** It allows up to a 10% error margin (insertions, deletions, substitutions). This handles noisy environments and minor stuttering elegantly.
- **Mapping:** Once the substring with the lowest distance is found, the start index is looked up in the `ph_index.npy` binary array to instantly reveal the exact Surah and Ayah.

**Example test run result:**
```
Input:  "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِممممِنَلمُشرِكِ..."
Output: Surah 6, Ayah 137 ✓
```

See `docs/voice_navigation.md` for a full deep dive into how this is implemented.

---

## The Phonetic Representation System

This project uses a custom phonetic encoding designed specifically for the Arabic ASR model's output vocabulary. It is NOT IPA. Here are the key characters:

| Character | Unicode | Meaning |
|---|---|---|
| ا | U+0627 | Short alef sound (or extended vowel) |
| و | U+0648 | Waw vowel |
| ي | U+064A | Ya vowel |
| ۥ | U+06E5 | Small waw (used for diphthong/madd ending) |
| ۦ | U+06E6 | Small ya (used for diphthong/madd ending) |
| Repeated chars | — | Length encoding. `ییی` = longer "ee" sound than `ی` |

**Critical rule:** In `aya_phoneme`, phoneme length is encoded by repetition. `ررَحِۦۦۦۦم` has 4x `ۦ` because the ي in "رحيم" is a full Madd. The ErrorExplainer uses the LENGTH of repeated vowels to check if a user held a sound long enough.

---

## Directory Structure

```
lib/
├── main.dart                          # App entry point + _Orchestrator (lifecycle manager)
├── audio/
│   └── audio_processor.dart          # Microphone + VAD + chunking
├── data/
│   └── quran_data.dart               # QuranVerse model + JSON parsing + repository
├── engine/
│   └── sherpa_engine.dart            # Sherpa-ONNX ASR (in a Dart Isolate)
├── state/
│   └── app_state.dart                # Singleton settings (theme, lang, font size, mode)
├── tracking/
│   ├── highlighting_controller.dart  # Brain: routes ASR → word tracker → UI
│   ├── phonetic_word_tracker.dart    # Streaming Levenshtein DP per-ayah
│   ├── quran_normalizer.dart         # Normalize Arabic text for comparison
│   ├── voice_search_controller.dart  # Global Quran search via recitation
│   └── matchers/
│       ├── error_explainer.dart      # Post-Ayah Tajweed/Tashkeel error classifier
│       ├── fuzzy_search.dart         # Core Levenshtein fuzzy substring search
│       ├── phonetic_search.dart      # Manager mapping fuzzy search to Surah/Ayah via .npy
│       └── tajweed_rules.dart        # Tajweed Rule engine (Madd, Ghunnah, Qalqalah, Tafkheem, Hams)
├── ui/
│   ├── tracking_screen.dart          # Main screen
│   └── widgets/
│       ├── mic_bar.dart              # Bottom action bar (mic button, tap vs long-press)
│       ├── settings_dialog.dart      # Settings bottom sheet
│       ├── surah_picker.dart         # Surah selection bottom sheet
│       └── verse_row.dart            # Single Ayah row with word highlighting
assets/
├── model/
│   ├── ordered_quran_phonemes.json   # The Quran phoneme database (~8.6 MB)
│   ├── ph_index.npy                  # Binary NumPy index for phonetic mapping (~2.4 MB)
│   ├── ph_index.txt                  # The entire stripped phonetic Quran text (~350 KB)
│   ├── tokens.txt                    # Sherpa ONNX vocabulary
│   └── quran_phoneme_zipformer.int8.onnx  # The ASR model
```

---

## Known Limitations & Open Tasks
TODO - LATER INSHA'A ALLAH

Improve Tajweed System

---

## Reference Repositories
Elhamdule Allah
This project is built on research and code from the following open-source projects:

| Project | What was ported/adapted |
|---|---|
  [Quran-streaming-model](https://huggingface.co/Muno459/zipformer_p-quran)     | Muno459
| [quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript)       | obadx
| [qua_sdk](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner)    | Hetchy
  and more .....


  # هذا من فضل ربي - ربنا تقبل منا انك ان السميع العليم
