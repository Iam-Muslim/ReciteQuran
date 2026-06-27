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

Instead of computing an expensive matrix or tracking indices rigidly, `PhoneticWordTracker` buffers all incoming phonemes into an `activeChunk`. 

If the ASR engine resets mid-word (due to a VAD boundary), `KmpStitcher` safely finds the overlap prefix and stitches the new chunk onto the existing text, preventing stutter.

For the current expected word:
1. It scans possible substrings in `activeChunk` starting at index `startK` with length `L`.
2. It calculates the Levenshtein accuracy between the substring candidate and the expected phoneme.
3. If the best accuracy exceeds `matchThreshold` (e.g., 0.65), it marks the word as `correct`.
4. It consumes the matched part of `activeChunk`, advancing `_asrCursor` to discard used characters, and moves `_wordCursor` to the next word.

### Lookahead & Self-Healing

The algorithm supports **lookahead**: it doesn't just scan for the *next* expected word, it scans for up to `lookAheadWords` ahead. If it finds a strong match for Word 2 while currently waiting for Word 0, it means the user skipped Words 0 and 1. Those skipped words are marked `skipped` (Red), and the tracker jumps to Word 2.

If too much "noise" accumulates (e.g., > 150 characters unmatched), a self-healing rolling buffer drops the oldest noise, preventing the tracker from getting permanently stuck behind.

### The Last Word Problem (Waqf)

If the matched substring reaches the very end of the `activeChunk`, it means the ASR is still outputting the word. The algorithm normally waits for more text to ensure the highest possible accuracy before committing. However, if it's the **last word of the verse**, waiting indefinitely would cause the system to hang. The tracker explicitly handles this case: if it's the last word and accuracy is acceptable, it commits immediately instead of waiting for more phonemes that will never arrive.

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
[Prefix Sliding Window] Word 0 "بِسمِ" matched. Candidate: "بِسم", Acc: 0.75
[Prefix Sliding Window] Word 1 "للَااهِ" matched. Candidate: "للَااه", Acc: 0.8333333333333334
[Prefix Sliding Window] Word 2 "ررَحمَاانِ" matched. Candidate: "ررَحمَاان", Acc: 0.7777777777777778
[Prefix Sliding Window] Word 3 "ررَحِۦۦۦۦم" matched. Candidate: "ررَحِۦۦم", Acc: 0.625
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
