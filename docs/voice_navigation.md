# Voice Navigation — "Recite to Find Any Ayah"

## What Is This Feature?

Instead of manually scrolling through 114 Surahs to find a verse, you can:

1. **Hold** the green microphone button (long-press)
2. Recite any verse you remember
3. **Release** — the app instantly navigates to that Surah and Ayah

---

## How It Works (Step by Step)

### 1. Long-Press Detected

In `mic_bar.dart`, the `GestureDetector` has two callbacks:
- `onTap` → normal tracking mode
- `onLongPressStart` → voice search mode

When long-press is detected, `_startVoiceSearch()` in `main.dart`:
- Resets the ASR buffer (clean slate)
- Starts the microphone
- Sets `_isVoiceSearching = true`
- The button turns gold+purple to signal the mode change

The UI shows a banner: **"جاري الاستماع للبحث عن الآية..."**

### 2. You Recite

Your speech is sent to Sherpa-ONNX exactly like normal tracking. But instead of going to `PhoneticWordTracker`, the accumulated text is stored in `_voiceSearchAsrText`. The word tracker is NOT involved.

### 3. Release Detected

When you release, `_stopVoiceSearch()` calls:
```dart
final result = _voiceSearchCtrl.stopSearch(_voiceSearchAsrText);
```

### 4. The Search

`VoiceSearchController.stopSearch()`:
1. Normalizes the ASR text (removes tashkeel, normalizes alef variants)
2. Chunks it into phoneme groups using `PhonemeChunker`
3. Passes the chunks to `Anchor.findAnchorByVoting()`

### 5. TF-IDF N-gram Voting

`findAnchorByVoting` reads the pre-built `ngram_index.json` and:

1. Generates all 4-grams from your recitation
2. For each 4-gram, looks up which Ayahs contain it
3. Votes for each Ayah, weighted by `1 / total_ayahs_with_this_ngram`
4. Sums votes by Surah
5. Within the top Surahs, finds the longest **contiguous Ayah run** with votes

**Example:**

You recite Surah Al-An'am 6:137. Your phoneme chunks include:
```
["وَ", "كَ", "ذَ", "ا", "ا", "لِ", ...]
```

4-grams generated: `"وَ|كَ|ذَ|ا"`, `"كَ|ذَ|ا|ا"`, `"ذَ|ا|ا|لِ"`, ...

In `ngram_index.json`:
- `"وَ|كَ|ذَ|ا"` → appears in 12 Ayahs → weight = 1/12 = 0.083
- `"شُرَكَاا|ءُ|هُ|م"` → appears in only 1 Ayah (6:137) → weight = 1/1 = **1.0**

The unique 4-grams dominate the vote, and 6:137 wins.

### 6. Navigation

If a result is found:
```dart
await _ctrl!.setTargetSurah(result.surah);
_ctrl!.setManualAyah(result.surah, result.ayah);
```

The UI scrolls to the matched Ayah and shows a success SnackBar:
```
تم الانتقال إلى سورة 6 آية 137
```

If nothing found: `"لم يتم العثور على الآية، حاول مرة أخرى"`

---

## The N-gram Index

The index is built offline (not at app startup) and stored in `assets/model/ngram_index.json` (~9.3 MB).

### Building It

```bash
dart run bin/build_ngram_index.dart
# Reads: assets/model/ordered_quran_phonemes.json
# Writes: assets/model/ngram_index.json
# Time: ~8 seconds
```

### Testing It

```bash
dart run bin/test_ngram_search.dart
# Feeds: aya_phoneme of 6:137
# Expects: Surah 6, Ayah 137
# Output: SUCCESS: The index correctly identified Al-An'am (6), Ayah 137!
```

### Loading at Runtime

The index is loaded **lazily** — only when the user first long-presses the button. Loading takes ~200ms. After the first load, it stays in memory for the rest of the session.

```dart
// In VoiceSearchController:
Future<void> startSearch() async {
    await _loadIndexIfNeeded();  // lazy load
    engine.resetBuffer();
}
```

---

## Accuracy Notes

- **Short verses (1-2 words):** May return wrong results if those words are common across many Ayahs (like Bismillah). The voting system weights uniqueness, but very short inputs have fewer unique 4-grams.

- **Long verses (5+ words):** High accuracy. Unique phrase combinations have very few matches in the entire Quran.

- **Noisy environments:** The ASR model still needs to hear you clearly. In very loud environments, the phoneme chunks may be too corrupted for reliable matching.

---

## Architecture Isolation

> **This feature is completely isolated from the main tracking system.**

The `VoiceSearchController` does not touch `PhoneticWordTracker` or `HighlightingController`'s word states. It only calls:
1. `engine.transcribe()` (same Sherpa engine)
2. `_ctrl.setTargetSurah()` + `_ctrl.setManualAyah()` at the end

This means you can safely modify the voice search code without risking any changes to the core word-tracking pipeline.
