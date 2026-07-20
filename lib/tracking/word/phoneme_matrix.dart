import 'dart:typed_data';

///
/// FILE ROLE: Constants / Dictionaries / Mathematical Penalties
/// ARCHITECTURE: Pre-calculated contiguous memory lookup table (Float64List)
/// DEPENDENCIES: None
/// RESPONSIBILITY:
/// - Defines strict penalty costs for substituting one Arabic phoneme for another.
/// - Handles acoustic neighbor logic (e.g. Sin vs Sad, Hamza grouping).
/// - Dynamically builds an O(1) 2D lookup matrix when new phonemes are encountered.
/// AI NOTE: If the user wants to adjust how "forgiving" the engine is regarding specific
/// letters (e.g. "forgive Qaf vs Kaf"), edit the `isPair` logic in `SubCostTable` here.
/// Do NOT put Tajweed rules here. This is purely for ASR acoustic distance.
///

/// ────────────────────────────────────────────────────────────────────────────
/// [SubCostTable] - Phonetic Penalty System
/// ────────────────────────────────────────────────────────────────────────────
/// This class is the foundational mathematical rulebook for how the alignment engine
/// scores differences between the audio the user spoke (ASR output) and the text
/// they were supposed to read (Reference text).
///
/// In ASR systems, transcription isn't always perfect. Sometimes the microphone
/// hears a 'س' as a 'ص', or a 'ت' as a 'ط'. If we rigidly punished the user
/// every time the ASR made a slight mistake, the UI would constantly flash red
/// errors even when the user read perfectly.
///
/// To solve this, we use a "Cost Table" (also known as a Substitution Matrix).
/// Instead of a binary 0 (match) or 1 (fail), we calculate a fractional penalty
/// between 0.0 and 1.0 depending on how phonetically similar the sounds are.
///
/// The goal of this matrix is NOT Tajweed checking! The goal is pure "Tracking Stability".
/// We want the tracker to forgive small phonetic mistakes so it can keep moving
/// forward smoothly. (Strict Tajweed checking happens later in ErrorExplainer).
class SubCostTable {
  /// Calculates the exact float penalty for substituting [c1] (ASR) with [c2] (Reference).
  ///
  /// Returns:
  /// - 0.0 : Perfect match.
  /// - 0.1 : Minor variation (e.g. same base letter, different harakah if we tracked it).
  /// - 0.25: Phonetic neighbor (e.g. 'س' vs 'ص'). Forgivable by the tracker.
  /// - 1.0 : Completely different sound. Heavy penalty.
  static double getCost(String c1, String c2) {
    // -------------------------------------------------------------------------
    // Rule 1: The Golden Rule - Exact Match
    // If the string exactly matches the reference string, the cost is 0.0.
    // This is the ideal scenario where the user spoke perfectly and the ASR heard perfectly.
    // -------------------------------------------------------------------------
    if (c1 == c2) return 0.0;

    // -------------------------------------------------------------------------
    // Rule 2: Edge Case Protection - Empty Strings
    // If somehow an empty string sneaks into the comparison logic, we immediately
    // slap it with a maximum penalty (1.0) to reject it. You cannot substitute
    // nothingness for a real sound.
    // -------------------------------------------------------------------------
    if (c1.isEmpty || c2.isEmpty) return 1.0;

    // -------------------------------------------------------------------------
    // Rule 3: Base Character Extraction
    // Arabic letters can have multiple forms or decorations. We extract the very
    // first character of the chunk to determine the "Base" letter.
    // -------------------------------------------------------------------------
    String base1 = c1[0];
    String base2 = c2[0];

    // Check if the base characters are mathematically identical.
    bool sameBase = (base1 == base2);

    // -------------------------------------------------------------------------
    // Rule 4: The Hamza Forgiveness Zone
    // Arabic has many ways to write Hamza (ا، أ، إ، آ، ء، ؤ، ئ).
    // The ASR frequently mixes these up because they sound nearly identical.
    // If both letters belong to the Hamza family, we instantly forgive the mismatch
    // and treat them as the exact same base letter.
    // -------------------------------------------------------------------------
    final hamzas = const ['ا', 'أ', 'إ', 'آ', 'ء', 'ؤ', 'ئ'];
    if (!sameBase && hamzas.contains(base1) && hamzas.contains(base2)) {
      sameBase = true;
    }

    // -------------------------------------------------------------------------
    // Rule 5: The Alif Maqsura & Ya Forgiveness Zone
    // In many scripts (especially Uthmani), 'ي' (Ya) and 'ى' (Alif Maqsura) are
    // visually or phonetically interchangeable at the ends of words.
    // If the mismatch is just between these two, we forgive it.
    // -------------------------------------------------------------------------
    if (!sameBase &&
        (base1 == 'ي' || base1 == 'ى') &&
        (base2 == 'ي' || base2 == 'ى')) {
      sameBase = true;
    }

    // -------------------------------------------------------------------------
    // Rule 6: The Ta-Marbuta & Ha Forgiveness Zone
    // 'ة' (Ta-Marbuta) is pronounced as 'ه' (Ha) when stopping. The ASR constantly
    // confuses them. We treat them as the same base letter to maintain tracking stability.
    // -------------------------------------------------------------------------
    if (!sameBase &&
        (base1 == 'ه' || base1 == 'ة') &&
        (base2 == 'ه' || base2 == 'ة')) {
      sameBase = true;
    }

    // -------------------------------------------------------------------------
    // Rule 7: Shadda (Gemination) Penalty Calculation
    // If we determined above that the Base letters are the same, we still need
    // to check if one has a Shadda and the other doesn't.
    // Missing a Shadda is a minor error, so we give it a tiny penalty (0.25).
    // If the base is identical and Shadda matches, it gets an almost-perfect score of 0.1.
    // -------------------------------------------------------------------------
    if (sameBase) {
      bool hasShadda1 = c1.contains('ّ');
      bool hasShadda2 = c2.contains('ّ');
      if (hasShadda1 != hasShadda2)
        return 0.25; // Minor penalty for missing Shadda
      return 0.1; // Almost perfect match
    }

    // -------------------------------------------------------------------------
    // Rule 8: Phonetic Neighbors (The 0.25 Penalty Zone)
    // If the base letters are completely different, we check if they sound similar.
    // We define a helper function `isPair` to check bidirectional similarity.
    // -------------------------------------------------------------------------
    bool isPair(String a, String b) =>
        (base1 == a && base2 == b) || (base1 == b && base2 == a);

    // If the letters are notorious acoustic neighbors (like Sin/Sad, Ta/Ta, Thal/Zha),
    // we assign a low penalty of 0.25. The DP algorithm will gladly accept a 0.25 penalty
    // rather than doing a full deletion or insertion.
    if (isPair('س', 'ص') || // Sin / Sad
        isPair('ت', 'ط') || // Ta / Tta
        isPair('ذ', 'ظ') || // Thal / Zha
        isPair('د', 'ض') || // Dal / Dha
        isPair('ه', 'ح') || // Ha / Hha
        isPair('غ', 'خ') || // Ghayn / Kha
        isPair('ك', 'ق') || // Kaf / Qaf
        isPair('ء', 'ع') || // Hamza / Ayn
        isPair('ن', 'م') || // Nun / Mim (Nasal confusion)
        isPair('ن', 'ل') || // Nun / Lam (Liquid confusion)
        isPair('ز', 'ذ') || // Zay / Thal
        isPair('س', 'ث') || // Sin / Tha
        isPair('ظ', 'ض') || // Zha / Dha
        isPair('ن', 'ں') || // Nun / Noon Ghunna
        isPair('م', '۾') || // Mim / Mim variants
        isPair('ه', 'ت') || // Ta-Marbuta / Ta (Wasl vs Waqf confusion)
        isPair('و', 'ُ') || // Waw / Damma (Madd confusion)
        isPair('ي', 'ِ') || // Ya / Kasra (Madd confusion)
        isPair('ا', 'َ') || // Alif / Fatha (Madd confusion)
        isPair('ى', 'َ')) { // Alif Maqsura / Fatha
      return 0.25;
    }

    // -------------------------------------------------------------------------
    // Rule 9: Maximum Penalty
    // If the letters are totally different and do not sound alike at all (e.g., 'ب' vs 'ش'),
    // we return the maximum penalty of 1.0. This tells the DP engine "DO NOT MATCH THESE".
    // -------------------------------------------------------------------------
    return 1.0;
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// [PhonemeMatrix] - High-Performance 2D Lookup Cache
/// ────────────────────────────────────────────────────────────────────────────
/// Calling `SubCostTable.getCost()` dynamically during a realtime audio stream
/// is extremely slow because it uses `if` statements and string comparisons.
/// In a single second of audio, the DP engine might compare phonemes tens of thousands of times!
///
/// To achieve 0ms latency, we use this class to pre-calculate all possible string comparisons
/// and store them in a highly optimized contiguous block of C-style memory (`Float64List`).
///
/// Whenever a new, never-before-seen phoneme string arrives, we dynamically expand
/// this matrix, run the string comparisons ONCE, and cache the result.
class PhonemeMatrix {
  /// A dictionary mapping string phonemes (like 'ب') to unique integer IDs (like 14).
  /// String comparisons are slow. Integer lookups are instant.
  static final Map<String, int> _phonemeToId = {};

  /// Tracks exactly how many unique phonemes we have discovered so far.
  /// This number dictates the size of our NxN matrix.
  static int _numPhonemes = 0;

  /// The 1-Dimensional contiguous memory array that mathematically represents a 2D grid.
  /// Instead of `List<List<double>>`, we use `Float64List` for extreme CPU cache locality.
  static Float64List _subMatrix = Float64List(0);

  /// Takes a raw string phoneme (e.g. 'س') and returns its unique Integer ID.
  /// If the phoneme has never been seen before, it assigns a new ID and triggers
  /// a complete matrix rebuild to accommodate the new row and column.
  static int encode(String p) {
    if (!_phonemeToId.containsKey(p)) {
      // It's a new phoneme! Assign it an ID and increment the counter.
      _phonemeToId[p] = _numPhonemes++;

      // We must rebuild the 2D grid because we just added a new column and row.
      _rebuildMatrix();
    }
    // Return the cached integer ID instantly.
    return _phonemeToId[p]!;
  }

  /// Preheats the matrix with all known phonemes from tokens.txt.
  /// Calling this once before audio streaming begins ensures the matrix
  /// is fully built (O(1) lookups) and prevents micro-stutters.
  static void preheat(List<String> tokens) {
    if (_numPhonemes >= tokens.length) return; // Already preheated

    bool needsRebuild = false;
    for (String p in tokens) {
      if (!_phonemeToId.containsKey(p)) {
        _phonemeToId[p] = _numPhonemes++;
        needsRebuild = true;
      }
    }
    
    if (needsRebuild) {
      _rebuildMatrix();
    }
  }

  /// Rebuilds the NxN matrix from scratch.
  ///
  /// Let N be the total number of unique phonemes (`_numPhonemes`).
  /// This allocates a new 1D array of size N * N.
  /// It loops through every possible pair of phonemes, calculates their penalty
  /// using the slow `SubCostTable`, and saves the float value in the 1D array.
  static void _rebuildMatrix() {
    int size = _numPhonemes;

    // Allocate the new memory block. Size is N squared.
    Float64List newMat = Float64List(size * size);

    // By default, fill the entire matrix with the maximum penalty (1.0).
    newMat.fillRange(0, size * size, 1.0);

    // The diagonal of the matrix represents comparing a phoneme to itself (e.g. 'ب' vs 'ب').
    // The cost of self-comparison is always mathematically 0.0.
    for (int i = 0; i < size; i++) {
      // The formula to find the diagonal in a flattened 1D array is: (row * size) + col.
      // Since row == col on the diagonal, it becomes (i * size) + i.
      newMat[i * size + i] = 0.0;
    }

    // Now we do the heavy lifting. We iterate through every known phoneme string.
    for (var entry1 in _phonemeToId.entries) {
      // And we compare it against every other known phoneme string.
      for (var entry2 in _phonemeToId.entries) {
        int aid = entry1.value; // The integer ID of phoneme 1
        int bid = entry2.value; // The integer ID of phoneme 2

        // We already handled the diagonal (aid == bid) above, so we skip it.
        if (aid != bid) {
          // Calculate the exact penalty using the slow string comparison logic.
          // Save the result into the highly optimized 1D memory array.
          newMat[aid * size + bid] = SubCostTable.getCost(
            entry1.key,
            entry2.key,
          );
        }
      }
    }

    // Swap the old matrix out for the newly built one.
    _subMatrix = newMat;
  }

  /// The crown jewel of this class.
  /// Retrieves the pre-calculated penalty between two Integer IDs instantly.
  ///
  /// Time Complexity: O(1)
  /// Memory Complexity: O(1)
  static double getCost(int aid, int bid) {
    // -------------------------------------------------------------------------
    // Instant Win: If the IDs are identical, the cost is 0.0. No lookup needed!
    // -------------------------------------------------------------------------
    if (aid == bid) return 0.0;

    // -------------------------------------------------------------------------
    // Safe Lookup: If both IDs are valid (less than the max phonemes known),
    // we query the 1D array using the `row * width + col` formula.
    // -------------------------------------------------------------------------
    if (aid < _numPhonemes && bid < _numPhonemes) {
      return _subMatrix[aid * _numPhonemes + bid];
    }

    // -------------------------------------------------------------------------
    // Failsafe: If an invalid ID was requested, return maximum penalty (1.0).
    // -------------------------------------------------------------------------
    return 1.0;
  }
}
