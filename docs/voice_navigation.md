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
1. Normalizes the ASR text using `QuranNormalizer.normalizeWithTashkeel`
2. Passes the normalized text to `PhoneticSearch.search()`

### 5. Phonetic Fuzzy Search (Levenshtein)

`PhoneticSearch` reads the pre-built `ph_index.npy` and `ph_index.txt` files and:

1. Normalizes the query by combining consecutive identical core characters into a single character and stripping residuals (harakat/tashkeel).
2. Runs a heavily optimized **Fuzzy Search (Levenshtein Distance)** algorithm (`fuzzy_search.dart`) against the entire Quran phonetic reference string.
3. Allows for an error ratio (e.g., 10%) so slight mispronunciations or ASR errors do not ruin the search.
4. Returns all matches, sorted by edit distance (lowest distance wins).
5. Maps the winning character span back to the exact Surah and Ayah indices using the `.npy` binary index.

**Example:**

You recite Surah Al-An'am 6:137. 

Input:  "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِممممِنَلمُشرِكِ..."
Output: `PhonemesSearchResult(start: (surah: 6, ayah: 137), end: ..., distance: 2)`

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

## The Phonetic Index

The index is built offline and stored in two assets:
1. `assets/model/ph_index.txt`: A single continuous string containing the stripped phonetic representation of the entire Quran (~350 KB).
2. `assets/model/ph_index.npy`: A binary NumPy array mapping every character index in the `.txt` file back to its Surah, Ayah, Word, and Uthmani character indices (~2.4 MB).

### Loading at Runtime

The index is loaded **lazily** — only when the user first long-presses the button. Loading takes a fraction of a second. After the first load, it stays in memory for the rest of the session.

```dart
// In VoiceSearchController:
Future<void> _loadIndexIfNeeded() async {
    _search = PhoneticSearch();
    await _search!.load(); // lazy load
}
```

---

## Accuracy Notes

- **Short verses (1-2 words):** May return multiple matches across the Quran (like Bismillah). The system currently returns the first best match found.
- **Long verses (5+ words):** High accuracy. The fuzzy search will perfectly align to the unique phonetic sequence.
- **Noisy environments:** The Levenshtein distance gracefully handles small errors (insertions, deletions, substitutions) caused by background noise, making it extremely robust compared to exact N-gram matching.

---

## Architecture Isolation

> **This feature is completely isolated from the main tracking system.**

The `VoiceSearchController` does not touch `PhoneticWordTracker` or `HighlightingController`'s word states. It only calls:
1. `engine.transcribe()` (same Sherpa engine)
2. `_ctrl.setTargetSurah()` + `_ctrl.setManualAyah()` at the end

This means you can safely modify the voice search code without risking any changes to the core word-tracking pipeline.
