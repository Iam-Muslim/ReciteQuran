# Tajweed & Error Analysis — `lib/tracking/matchers/error_explainer.dart`

## Overview

`ErrorExplainer.explainAyahError` is called once per Ayah, AFTER the reciter finishes all words. It takes the **full accumulated predicted phoneme string** and the **full expected phoneme string** for that Ayah, and returns a map of which words have which errors.

This runs in **post-processing**, not real-time. It's the "detailed report" after you finish an Ayah.

---

## The Three Error Categories

### 1. `ErrorCategory.normal` — Wrong consonant

The reciter said a completely different consonant. Example: saying `سـ` instead of `صـ`.

- Detected by: `replace`, `insert`, or `delete` operations in the Levenshtein alignment
- UI effect: Keeps word RED (if already wrong) or keeps GREEN if only minor

### 2. `ErrorCategory.tajweed` — Tajweed Rule Violation (Madd, Ghunnah, Qalqalah, etc.)

The reciter missed a specific Tajweed rule (e.g. didn't bounce a Qalqalah, skipped an Ikhfa/Idgham, or cut a Madd/Ghunnah short).

Example: The expected phoneme has `نننن` (4 Noons = 2 beats of Ghunnah). The reciter output only `ن` (1 count). The engine passes the reference chunk through the `TajweedRule` subclasses (like `Ghonnah`) and detects that the user's `count` was less than the required amount.

- Detected by: A mismatch (delete, replace, or unequal length) where the reference phonetic string triggers an active `TajweedRule` (e.g. `Qalqalah`, `MaddRule`, `Ghonnah`).
- UI effect: Word turns **YELLOW**

### 3. `ErrorCategory.tashkeel` — Wrong harakat (vowel mark)

The reciter said the right consonant but with the wrong harakat. Example: `بَ` (fatha) instead of `بِ` (kasra).

- Detected by: `equal` operation where lengths are the same or differ by exactly 1, but the actual chunk strings differ
- UI effect: Word turns **YELLOW**

---

## The CTC Collapse Filter — Why It Exists

The ASR model outputs audio frames, not clean text. A slow reader produces more frames:

```
Fast reader:  "بَ" → model outputs: [بَ]
Slow reader:  "بَ" → model outputs: [بَ, بَ, بَ, بَ]   ← same sound, more frames
```

Without the filter, the slow reader's `[بَ, بَ, بَ, بَ]` would look like 3 extra insertions.

The filter collapses consecutive identical non-vowel chunks:
```
[بَ, بَ, بَ, بَ] → [بَ]    ✓ collapsed
```

But for vowels (ا, و, ي, ۥ, ۦ), it CONCATENATES them instead:
```
[ي, ي, ي, ي] → [يييي]    ✓ kept (length = how long you held the sound)
```

**This preserves Madd length information while removing stutter noise.**

---

## The Levenshtein Alignment

After CTC collapse, both the reference groups and predicted groups are aligned using the Wagner-Fischer algorithm:

```
Reference:  [بِ, سـ, مِ, لـ, لَ, اا, هِ]   (from aya_phoneme)
Predicted:  [بـ, سـ, مِ, لـ, لـ, ا,  هِ]   (from ASR output)

Alignment:
  بِ ↔ بـ  → replace  (harakat differs: kasra vs. none) = tashkeel error
  سـ ↔ سـ  → equal
  مِ ↔ مِ  → equal
  لـ ↔ لـ  → equal
  لَ ↔ لـ  → replace  (harakat differs: fatha vs. none) = tashkeel error
  اا ↔ ا   → equal (same consonant, length diff = 1) = tashkeel error
  هِ ↔ هِ  → equal
```

---

## Word Attribution

Each alignment operation is mapped to a word index using `refGroupToWord`.

This list is built at the start of `explainAyahError` by:
1. Calculating the cumulative character positions of each phoneme word
2. For each reference phoneme group, finding which word's range it falls into

```
phonemeWords = ["بِسمِ", "للَاا", "هِ"]
spaceless concatenation: "بِسمِللَاا هِ"
boundaries: [0, 4, 9, 11]

Group "بِ" starts at char 0 → in range [0,4) → word 0
Group "سـ" starts at char 2 → in range [0,4) → word 0
Group "لـ" starts at char 4 → in range [4,9) → word 1
...
```

This allows the system to say: "Word 2 has a Tajweed error" — so only word 2 turns yellow, not the whole Ayah.

---

## Real Terminal Output During a Session

```
[Tajweed] Ayah complete. Running global explainAyahError.

[ErrorExplainer] === START GLOBAL TAJWEED EVALUATION ===
[ErrorExplainer] Raw Expected: "بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم"
[ErrorExplainer] Raw Predicted: "بسمللاهرحمانرحييم"
[ErrorExplainer] CTC Collapsed Reference Groups: [بِ, س, مِ, ل, لَ, ا, ا, هِ, ر, رَ, ح, مَ, ا, ا, نِ, ر, رَ, حِ, ۦ, ۦ, ۦ, ۦ, م]
[ErrorExplainer] CTC Collapsed Predicted Groups: [ب, س, م, ل, ل, ا, ه, ر, ح, م, ا, ن, ر, ح, ي, ي, م]

[ErrorExplainer] Output Errors By Word Index:
[ErrorExplainer]   -> Word 0: [ErrorCategory.tashkeel]
[ErrorExplainer]   -> Word 3: [ErrorCategory.tajweed]
[ErrorExplainer] === END GLOBAL TAJWEED EVALUATION ===

[Tajweed] Word 0 turned YELLOW due to errors: [...]
[Tajweed] Word 3 turned YELLOW due to errors: [...]
```

Word 0 (`بِسمِ`) has a tashkeel error — harakat was spoken without clear kasra.
Word 3 (`ررَحِۦۦۦۦم`) has a Tajweed error — the Madd (4 counts) was too short.
