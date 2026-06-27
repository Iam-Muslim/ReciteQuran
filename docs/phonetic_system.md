# Phonetic System & Data Format

## The Problem: Uthmani Arabic vs. ASR Output

The Quran is displayed in **Uthmani Hafs script** — the classical calligraphy standard.

Example: `وَكَذَٰلِكَ زَيَّنَ`

However, an ASR (speech recognition) model does NOT output this. The model outputs phonetic characters — what the sounds actually ARE, not how they are traditionally written.

The ASR model outputs: `وَكَذَاالِكَزَييَنَ`

These are fundamentally different:
- Uthmani: `ذَٰلِكَ` (uses small alef U+0670 `ٰ` above the ذ)
- Phonetic: `ذَاالِكَ` (the actual stretched alef sound written as two characters `ا`)

This is why we have TWO text systems in every Ayah entry.

---

## `aya_text` — The Display Text (Uthmani)

This is the beautiful traditional Arabic script shown on screen. It contains:
- Classical ligatures
- Waqf (pause) markers (۞ ۩)
- Special diacritics used in Hafs transmission

**Never use this for phonetic comparison.** The model will never output Uthmani ligatures.

---

## `aya_phoneme` — The Model's Reference Output

This is what the **ASR model is expected to output** when it hears a perfect recitation of this Ayah. It uses a simplified phonetic encoding where:

### Repeated Characters = Length

The single most important rule:

| Phonetic | Meaning |
|---|---|
| `يَ` | Short ya sound |
| `يَيَ` | Slightly longer (like a double consonant) |
| `ي` | Pure vowel ya (no harakat = pure vowel) |
| `يي` | Long Madd ya (about 2 counts) |
| `ييي` | Longer Madd (about 3 counts) |
| `يييي` | Full Madd wajib (4 counts = ~0.6 seconds) |

This means the phonetic representation directly encodes **Tajweed length rules**:

```
Word "رَحِيمِ" in Surah Al-Fatiha:
Phoneme: "ررَحِۦۦۦۦم"

Breaking down:
  رر   = The ra is slightly elongated (connected from previous word)
  َ    = fatha harakat
  حِ   = ha with kasra
  ۦۦۦۦ = small ya × 4 = full Madd (4 counts of lengthening)
  م    = meem (final)
```

---

## `aya_phonemes_list` — Word-Level Phonemes

The same `aya_phoneme` string, but pre-split into one entry per word, matching the word count of `aya_text`.

```json
"aya_phonemes_list": [
    "بِسمِ",          // word 0: Bismillah
    "للَااهِ",        // word 1: Allah (note: double alef = madd)
    "ررَحمَاانِ",     // word 2: Al-Rahman
    "ررَحِۦۦۦۦم"     // word 3: Al-Rahim
]
```

The `ErrorExplainer` uses these to map phoneme-level alignment errors back to specific word indices.

---

## `aya_ui` — The Invisible Word Boundary Markers

This is perhaps the trickiest field. It looks like whitespace but contains invisible Unicode directional markers that encode where each Uthmani word starts.

**Why not just use spaces?** The Uthmani script has complex rendering rules. Some words that appear visually separate are joined in rendering. The `aya_ui` field encodes the LOGICAL word boundaries.

**How it is parsed in code (`QuranVerse.fromJson`):**
```dart
final rawWords = rawUthmani.trim().split(' ');
// Then remove empty items and filter special chars (۞ ۩)
```

The invisible markers between words act as the split point, giving us the correct `uthmaniWords` list.

---

## Special Phonetic Characters Reference

| Char | Unicode | Usage |
|---|---|---|
| `ۦ` | U+06E6 | Small ya — marks long ya vowel in madd |
| `ۥ` | U+06E5 | Small waw — marks long waw vowel in madd |
| `ء` | U+0621 | Hamza (glottal stop) |
| `ٱ` | U+0671 | Hamzat wasl (always normalized away in matching) |
| Double consonants | e.g. `رر`, `شش` | Idgham / Shadda (consonant doubling) |
| `ن` repeated | e.g. `نن` | Ghunna (nasal resonance in Noon/Meem) |

---






