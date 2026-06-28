# Real-Time Word Tracking — Prefix Sliding Window

## What Is This?

`PhoneticWordTracker` is the engine that, in real-time, watches your speech and decides: "You just finished word 3. It was GREEN."

It does this using a **Prefix Sliding Window** algorithm, run incrementally as the ASR model outputs new text.

---

## The Core Problem

You are reciting Surah Al-Fatiha. The ASR outputs characters in a stream:

```
t=0ms:    ""
t=160ms:  "بس"
t=320ms:  "بسمل"
t=480ms:  "بسمللا"
t=640ms:  "بسمللاه"
t=800ms:  "بسمللاهر"
...
```

At each moment, the question is: **which word have I reached?**

The reference (from the JSON) is:
```
Word 0: "بسملل"    (Bismillah)
Word 1: "لاه"      (Allah — note: actually "للاه" in phonetic)
Word 2: "ررحمان"   (Al-Rahman)
Word 3: "ررحيم"    (Al-Rahim)
```

(After normalization — tashkeel stripped, spaces removed.)

When the ASR has accumulated `"بسمللاه"` (7 chars), the Prefix Sliding Window algorithm scans the text to find the best match for Word 0, extracts it, then moves to Word 1. 

---

## The Sliding Window Algorithm

Instead of computing an expensive matrix over the entire Ayah, `PhoneticWordTracker` buffers incoming phonemes into an `activeChunk`. It dynamically calculates an estimated search window using `estWords = activeChunk.length / 5.0`.

For the current expected word:
1. It runs the **QUA SDK 3D Wraparound DP Matrix** (`_alignWraparound3D`) against the `activeChunk`.
2. The matrix is constrained by precomputed `wordStarts` and `wordEnds`. It is mathematically impossible for the DP to finish a match in the middle of a syllable.
3. **Wraparound (k-dimension):** The DP uses a 3rd dimension to absorb acoustic stutters. Because the ASR and JSON now use **raw length-encoded frames** (where holding a sound outputs repeated characters like `سسس`), the DP matrix matches these 1:1. If an actual stutter or mismatch occurs, the matrix wraps backward from `jEnd` to `jStart`, paying a flat `wrapPenalty`, keeping the Normalized Distance from spiking.
4. **Spatial Prior Weighting:** To handle lookahead and skipping, the DP penalizes matches that are far away from the `expectedWord`. If it finds a perfect match for Word 3 while expecting Word 1, it will accept it, seamlessly skipping Words 1 and 2 and marking them Red.

### The Last Word Problem (Endpointing)

If the matched substring consumes the entire `activeChunk` (`bestI == P.length`), it means the ASR is still outputting the word. The algorithm normally pauses and waits for more text to ensure the highest possible accuracy before committing. However, if it receives an `isEndpoint` signal, it forces the commit immediately.

### Matching Difficulty (Easy vs Strict)

The tracker supports dynamic accuracy calculation based on the user's settings:
- **Easy Mode:** Uses standard Levenshtein distance on normalized strings, allowing partial matches (e.g., if you say one wrong letter but match 85% of the phonetic word).
- **Strict Mode:** Bypasses Levenshtein distance and strictly demands an exact 1-to-1 match. If there is a single mismatch, accuracy collapses to `0.0`.
*(This toggle operates entirely independently of the Lookahead logic).*

---

## Word Commitment

After committing a word:
1. The `activeChunk` is sliced to remove the consumed characters.
2. The UI is updated instantly with `WordMatchStatus.correct`.

```dart
// Commit targetIdx!
statuses[targetIdx] = WordMatchStatus.correct;
```

---

## Real Terminal Output Example

```
[Tracker] ----- NEW DP EVALUATION -----
[Tracker] Cursor: 0 | Window: 0 to 4
[Tracker] Audio (P): بسمل
[Tracker] Expected (R): بسمللاهررحمانررحيم
[Tracker] DP Outcome: bestI=4, bestJ=5, normDist=0.000 (Threshold: 0.65)
[Tracker] -> Wait: Match reached end of active chunk but normDist > 0. User still speaking.
...
[Tracker] DP Outcome: bestI=8, bestJ=5, normDist=0.000 (Threshold: 0.65)
[Tracker] -> COMMIT: Matched words 0 to 0
```

Then if Tajweed is enabled:
```
[Tajweed] Ayah complete. Running global explainAyahError.
[Tajweed] Word 3 turned YELLOW due to errors: [ReciterError(tashkeel, ...)]
```

---

## Why Two Phases?

**Phase 1 (Real-Time, Green/Red):**
- Sliding Window is run on the active chunk.
- High performance, evaluating only necessary substring lengths.
- Result: instant, sub-100ms latency per word.

**Phase 2 (Post-Ayah, Yellow):**
- Runs ONCE after the full Ayah is complete.
- Operates on the full accumulated predicted string.
- Classifies Tajweed (Madd length), Tashkeel (wrong harakat), Normal errors.
- Result: ~50ms, only runs at end of Ayah.

---

## `WordMatchStatus` Values

| Status | Color | Meaning |
|---|---|---|
| `pending` | White (default) | Not yet evaluated |
| `correct` | Green | Word matched within threshold |
| `wrong` | Red | Word could not be matched (too many errors) |
| `skipped` | Red | Word was entirely skipped in the stream |
| *(correct + Tajweed errors)* | Yellow | Word matched but has Tajweed/Tashkeel errors |
