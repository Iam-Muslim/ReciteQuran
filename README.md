> *"And We have certainly made the Quran easy for remembrance, so is there any who will remember?"* — Al-Qamar 54:17

#  وَما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِنَّ أَجرِيَ إِلّا عَلَىٰ رَبِّ العالَمِين 
**For The Sake Of Allah only** if you used this app or the source code in any other work you aren't allowed to get from it any money or make profit from it and you have to mention that this app is for the sake of Allah only .


(1) you may use and redistribute it ONLY in applications that are FREE to end users

(2) you may NOT sell it, place it behind a paid subscription or paywall, monetize it with ads, or earn any revenue from an app or service that uses this model or its outputs;

(3) these terms pass on to anyone you share it with.

---
<img width="279" height="585" alt="5900085639712018203" src="https://github.com/user-attachments/assets/6eeb46e3-a773-4e9d-b29d-4a322dbd42c0" />
<img width="279" height="585" alt="5900085639712018204" src="https://github.com/user-attachments/assets/9b5670cb-1f60-44dc-968d-893dae1b8902" />
<img width="279" height="585" alt="5900085639712018205" src="https://github.com/user-attachments/assets/767c65b4-0f4f-41cc-ae4b-a19c18b8ec95" />



## What Is This Project?

**ReciteQuran** is a Flutter mobile application that listens to a user reciting the Holy Quran, word by word, and highlights each word as **correct (green)**, **wrong (red)**, or **has a Tajweed error (yellow)**.

It runs **entirely on-device**, with no internet connection needed. An Arabic ASR (Automatic Speech Recognition) model runs live in the background, converting your voice into phonetic Arabic text in real-time.


---

## Table of Contents

1. [Tech Stack](#tech-stack)
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

### `assets/model/ngram_index.json`

**~9.3 MB.** A pre-built search index used by the Voice Navigation feature. Built offline by running `dart run bin/build_ngram_index.dart`.

**Format:**
```json
{
    "ngramSize": 4,
    "ngramCounts": {
        "بِس|مِل|لَا|اهِ": 1,
        ...
    },
    "ngramPositions": {
        "بِس|مِل|لَا|اهِ": [{"s": 1, "a": 1}, {"s": 9, "a": 30}],
        ...
    }
}
```

Every consecutive group of 4 phoneme-chunks from every Ayah is registered here. The TF-IDF search weights rare N-grams higher, so unique phrases like `"لَاادِهِمشُرَكَاا"` pinpoint a single Ayah while common phrases like `"بِسمِللَاا"` score lower (appears in many surahs).

> **Do not edit this file manually.** Regenerate it with:
> ```bash
> dart run bin/build_ngram_index.dart
> ```

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

### CTC Frame Noise — The Critical Concept

> **This is the most important thing to understand for contributors.**

The model does NOT output clean text. It outputs one "best character" per audio frame. If a user speaks `بِسمِ` slowly:

```
Model frames: [ بِ ][ بِ ][ بِ ][ سـ ][ سـ ][ مـ ][ مِ ][ مِ ][ مِ ][ مِ ]
Raw output:   "بِبِبِسسممِمِمِمِ"
```

The model emits consecutive duplicate characters because it's processing each frame individually. This is "CTC frame stutter."

**The fix used in this project (CTC Self-Loop):** When comparing the streaming output against reference text, a repeated character (`chunk[i] == chunk[i-1]`) costs `0` instead of `1`. This makes the DP algorithm effortlessly absorb duplicate frames without misaligning word boundaries.

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

**Example:**
```
Input:    "ٱلرَّحْمَـٰنِ"
Output:   "الرحمن"
```

### `lib/tracking/matchers/phoneme_chunker.dart`

The Quran phonemes use a special character encoding. Each "phoneme group" is a consonant optionally followed by a harakat modifier. `PhonemeChunker` splits a phoneme string into these groups.

**Example:**
```
Input:   "بِسمِللَاا"
Output:  ["بِ", "س", "مِ", "ل", "لَ", "ا", "ا"]
```

This is a Dart port of the Python `chunk_phonemes()` function from `quran-transcript`.

### `lib/tracking/phonetic_word_tracker.dart`

**This is the core real-time word matching engine.** It implements a **streaming windowed Levenshtein DP**.

**The concept (explained simply):**
Imagine you have a long string of expected reference characters:
```
Reference: [ ب ِ س م ِ | ل ل َ ا ا ه ِ | ر ر َ ح م َ ا ا ن ِ | ر ر َ ح ِ ي م ]
              word 0         word 1              word 2              word 3
```

As you speak, new characters arrive. The DP matrix tracks the "cheapest path" from the start of the stream to every possible position in the reference. The "furthest J" (the rightmost position the path reached with low cost) determines which word you are currently on.

When the path crosses a word boundary marker, that word is "committed" as correct or skipped.

**Window:** The DP only looks at a ±25 character window around the current position for performance. No scanning the entire 200+ character Ayah on every new frame.

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

### Step 1: CTC Collapse Filter

Before alignment, both strings are processed through `_applyCtcCollapse`:
- Consecutive identical chunks are collapsed: `[ بِ, بِ, بِ ]` → `[ بِ ]`
- Vowel/length characters that repeat are *concatenated* not collapsed: `[ ا, ا, ا ]` → `[ ااا ]` (so we can measure how long you held the sound)

**Why?** Without this, a slow speaker would fail the Madd (length) check because their extra frames look like insertions.

### Step 2: Levenshtein Alignment on Phoneme Groups

The algorithm runs Levenshtein alignment on the collapsed phoneme groups and produces edit operations: `equal`, `replace`, `insert`, `delete`.

### Step 3: Error Classification

Each non-`equal` alignment is classified:

| Condition | Error Type | Meaning |
|---|---|---|
| `replace` / `delete` / `insert` | `ErrorCategory.normal` | Wrong consonant entirely |
| `equal` but different lengths (> 1 char difference) | `ErrorCategory.tajweed` | Madd/Ghunna length error (e.g. held too short/long) |
| `equal` but different lengths (≤ 1 char difference) | `ErrorCategory.tashkeel` | Harakat error (wrong vowel on consonant) |

### Step 4: Word Attribution

Each error is mapped back to a word index using the `refGroupToWord` list built at the start. The `HighlightingController` then turns those specific words from **green** to **yellow**.

**Terminal output during a session:**
```
[Tajweed] Ayah complete. Running global explainAyahError.
[ErrorExplainer] === START GLOBAL TAJWEED EVALUATION ===
[ErrorExplainer] Raw Expected: "بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم"
[ErrorExplainer] Raw Predicted: "بسمللاهرحمانرحيم"
[ErrorExplainer] CTC Collapsed Reference Groups: [بِ, س, مِ, ل, لَ, ا, ا, هِ, ...]
[ErrorExplainer] CTC Collapsed Predicted Groups: [ب, س, م, ل, ل, ا, ه, ...]
[ErrorExplainer] Output Errors By Word Index:
[ErrorExplainer]   -> Word 2: [ErrorCategory.tashkeel]
[ErrorExplainer] === END GLOBAL TAJWEED EVALUATION ===
[Tajweed] Word 2 turned YELLOW due to errors: [ReciterError(type: tashkeel, ...)]
```

---

## Voice Navigation — "Recite to Find"

**Files:** `lib/tracking/voice_search_controller.dart`, `lib/tracking/matchers/anchor.dart`

This feature lets the user **hold the microphone button** and recite any verse. The app will then automatically navigate to that Surah and Ayah.

### How It Works

1. **Long-press mic** → `_startVoiceSearch()` called in `main.dart`
2. Audio is fed to Sherpa like normal, but the accumulated `TranscriptionResult.text` is stored in `_voiceSearchAsrText` instead of being sent to the word tracker
3. **Release mic** → `VoiceSearchController.stopSearch(asrText)` called
4. The predicted text is chunked into phoneme groups
5. `Anchor.findAnchorByVoting` runs TF-IDF voting against the pre-built N-gram index

### The TF-IDF Voting Algorithm (from qua_sdk)

For each 4-gram (group of 4 consecutive phoneme chunks) in the predicted text:
- Look up which Ayahs contain that 4-gram in `ngram_index.json`
- Vote for those Ayahs, weighted by `1 / (number of Ayahs that have this 4-gram)`

Rare 4-grams that appear in only 1-2 Ayahs get a very high vote weight. Common phrases like Bismillah that appear in 114 surahs get a weight of `1/114 ≈ 0.009`.

After voting, the Surah with the highest total weight wins. Within that Surah, the algorithm finds the longest **contiguous run** of Ayahs with votes (to handle reciting across an Ayah boundary).

**Example test run result:**
```
Input:  "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِممممِنَلمُشرِكِ..."
Output: Surah 6, Ayah 137 ✓
```

### Rebuilding the Index

If `ordered_quran_phonemes.json` is ever updated, rebuild the search index:
```bash
dart run bin/build_ngram_index.dart
# Output: assets/model/ngram_index.json (~9.3 MB)
```

Then run the offline test to verify:
```bash
dart run bin/test_ngram_search.dart
```

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
│   ├── highlighting_mode.dart        # Enum: strict vs. lookahead tracking mode
│   ├── phonetic_word_tracker.dart    # Streaming Levenshtein DP per-ayah
│   ├── quran_normalizer.dart         # Normalize Arabic text for comparison
│   ├── voice_search_controller.dart  # Global Quran search via recitation
│   └── matchers/
│       ├── anchor.dart               # TF-IDF N-gram voting (port of qua_sdk)
│       ├── dp_aligner.dart           # [DEAD CODE] Legacy global aligner, not used
│       ├── error_explainer.dart      # Post-Ayah Tajweed/Tashkeel error classifier
│       ├── phoneme_chunker.dart      # Split phoneme string into groups
│       └── tajweed_rules.dart        # Tajweed Rule engine (Madd, Ghunnah, Qalqalah, etc.)
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
│   ├── ngram_index.json              # Pre-built TF-IDF search index (~9.3 MB)
│   ├── tokens.txt                    # Sherpa ONNX vocabulary
│   └── quran_phoneme_zipformer.int8.onnx  # The ASR model
bin/
│   ├── build_ngram_index.dart        # Script: builds ngram_index.json offline
│   └── test_ngram_search.dart        # Script: verifies ngram_index.json is correct
```

---

## Known Limitations & Open Tasks
TODO - LATER INSHA'A ALLAH



### Waqf (Pause) Support
- Currently there is no handling for Waqf marks. A reciter who pauses mid-Ayah will trigger the 800ms VAD timeout and the Ayah may be evaluated as incomplete.

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
