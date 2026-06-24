# Real-Time Word Tracking — The Streaming DP

## What Is This?

`PhoneticWordTracker` is the engine that, in real-time, watches your speech and decides: "You just finished word 3. It was GREEN."

It does this using a **Levenshtein DP (Dynamic Programming)** algorithm, run incrementally — one character at a time as the ASR model outputs new text.

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

The flat reference string with word boundaries marked:
```
Index: 0 1 2 3 4  5 6 7  8 9 10 11 12 13  14 15 16 17 18
Char:  ب س م ل ل  ل ا ه  ر ر  ح  م  ا  ن   ر  ر  ح  ي  م
Word:  0 0 0 0 0  1 1 1  2 2  2  2  2  2   3  3  3  3  3
```

When the ASR has accumulated `"بسمللاه"` (7 chars), the DP path should show the tracker reached index 7 (just past word boundary of word 1). So word 0 is "committed" as GREEN.

---

## The Streaming DP Algorithm (Simplified)

The standard Levenshtein DP computes an NxM matrix. In a streaming context, we cannot recompute the full matrix every time a character arrives — that would be O(N×M) per character, which is too slow.

Instead, `PhoneticWordTracker` maintains only **one row** of the DP matrix: `_dpActiveRow`. Every time a new predicted character arrives, it computes the **next row** and replaces the active row.

### Step-by-step for one new character:

```
New predicted char: "ب"
Current _dpActiveRow: [0, ∞, ∞, ∞, ∞, ∞, ∞, ∞, ∞, ...]

For each reference position j from 1 to N:
  insertion  = _dpActiveRow[j]     + 1.0   (consume predicted char, don't advance ref)
  deletion   = nextRow[j-1]        + 1.0   (advance ref without consuming predicted)
  match/sub  = _dpActiveRow[j-1]   + cost  (cost=0 if chars match, 1 if different)
  nextRow[j] = min(insertion, deletion, match/sub)

→ nextRow becomes the new _dpActiveRow
```

### CTC Self-Loop (0-Cost Insertion)

If the new predicted character is IDENTICAL to the previous one (`بب` → second `ب`), the insertion cost is `0.0` instead of `1.0`. This handles CTC frame stutter without penalizing word boundaries.

### Window Optimization

Instead of computing the full row of N cells, the algorithm only computes a window of ±25 cells around the current tracked position `_charCursor`. This keeps each update to O(50) operations instead of O(N).

---

## Word Commitment

After updating the DP row, the tracker finds the **furthest J** (rightmost position with `cost ≤ 2.0`). This is the furthest position in the reference where the alignment is still "good."

If `furthestJ` crosses into a new word (i.e., `_rWordIndices[furthestJ] > _wordCursor`), the current word `_wordCursor` is committed:

```dart
statuses[_wordCursor] = WordMatchStatus.correct;
_wordCursor++;
```

The `_wordStartAsrIndices` map records exactly where in the ASR stream each word started, allowing the system to extract the "spoken chunk" for that word.

---

## Real Terminal Output Example

```
[Streaming DP] Word 0 "بِسمِ" completed. Spoken slice: "بسملل".
[Streaming DP] Word 1 "للَااهِ" completed. Spoken slice: "لاه".
[Streaming DP] Word 2 "ررَحمَاانِ" completed. Spoken slice: "رحمان".
[Streaming DP] Word 3 "ررَحِۦۦۦۦم" completed. Spoken slice: "رحيم".
```

Then if Tajweed is enabled:
```
[Tajweed] Ayah complete. Running global explainAyahError.
[Tajweed] Word 3 turned YELLOW due to errors: [ReciterError(tashkeel, ...)]
```

---

## Why Two Phases?

**Phase 1 (Real-Time, Green/Red):**
- Levenshtein is run character-by-character
- Only word BOUNDARIES matter — is the stream past word X yet?
- No Tajweed, no vowel analysis
- Result: instant, sub-100ms latency per word

**Phase 2 (Post-Ayah, Yellow):**
- Runs ONCE after the full Ayah is complete
- Operates on the full accumulated predicted string
- Applies CTC collapse filter (removes stutter)
- Classifies Tajweed (Madd length), Tashkeel (wrong harakat), Normal errors
- Result: ~50ms, only runs at end of Ayah

This separation is critical. Running full Tajweed analysis in real-time on every new character would add hundreds of milliseconds of lag.

---

## `WordMatchStatus` Values

| Status | Color | Meaning |
|---|---|---|
| `pending` | White (default) | Not yet evaluated |
| `correct` | Green | Word matched within threshold |
| `wrong` | Red | Word could not be matched (too many errors) |
| `skipped` | Red | Word was entirely skipped in the stream |
| *(correct + Tajweed errors)* | Yellow | Word matched but has Tajweed/Tashkeel errors |
