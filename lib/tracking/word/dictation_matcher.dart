import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import '../tracker_config.dart';

export '../tracker_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Per-Word Semi-Global DTW Matcher (Direct Character-Level Alignment)
//
// Each word is matched independently against the unconsumed ASR buffer.
// Free-start: leading noise characters are free (handles Wasl and CTC jitter).
// First-valid-endpoint: consumes the minimum number of ASR characters.
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of aligning ASR characters against a single word's reference.
class WordMatchResult {
  /// Total edit cost normalized by reference length.
  final double pathCost;

  /// How many ASR characters this match consumed from the buffer.
  final int tokensConsumed;

  /// Substring of ASR phonemes that aligned to the word.
  final String cleanAsr;

  /// Timestamps of the aligned ASR characters.
  final List<double> timestamps;

  /// Full alignment trace for Tajweed evaluation.
  final List<PhonemeGroupAlignment> trace;

  /// Indicates if this is a partial match (word is still being spoken).
  final bool isPartial;

  const WordMatchResult({
    required this.pathCost,
    required this.tokensConsumed,
    required this.cleanAsr,
    required this.timestamps,
    required this.trace,
    this.isPartial = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Matcher configuration type alias for backwards compatibility.
// ═══════════════════════════════════════════════════════════════════════════════

/// Type alias pointing legacy AlignmentConfig references to the unified TrackerConfig.
typedef AlignmentConfig = TrackerConfig;

// ═══════════════════════════════════════════════════════════════════════════════
// PHONETIC & TAJWEED COST ENGINE (MODEL-SPECIFIC ACOUSTIC MATRIX)
// ═══════════════════════════════════════════════════════════════════════════════

class PhoneticCostEngine {
  // ── 1. Zero-Cost Tajweed & Auxiliary Markers ──
  static bool _isZeroCostMarker(int codeUnit) {
    return codeUnit == 0x0686 || // 'ڇ' - Qalqalah release burst
           codeUnit == 0x06DC || // 'ۜ' - Sakt
           codeUnit == 0x0619 || // 'ؙ' - Ishmam
           codeUnit == 0x06EA || // '۪' - Imalah
           codeUnit == 0x0640;   // 'ـ' - Tatweel
  }

  // ── 2. Interchangeable Quranic Glyphs (Cost = 0.0) ──
  static bool isEquivalentGlyph(int asrCode, int refCode) {
    if (asrCode == refCode) return true;

    // Swap to ensure 'asrCode' is always the smaller code unit
    if (asrCode > refCode) {
      final int temp = asrCode;
      asrCode = refCode;
      refCode = temp;
    }

    if (asrCode == 0x0645 && refCode == 0x06FE) return true; // م <-> ۾ (Iqlab)
    if (asrCode == 0x0646 && refCode == 0x06BA) return true; // ن <-> ں (Ikhfaa)
    if (asrCode == 0x0648 && refCode == 0x06E5) return true; // و <-> ۥ (Waw)
    if (asrCode == 0x064A && refCode == 0x06E6) return true; // ي <-> ۦ (Yaa)

    if (_isHamzaVariant(asrCode) && _isHamzaVariant(refCode)) return true;
    
    // Ta-Marbuta (ة) can sound like Haa (ه) or Taa (ت), but Haa and Taa cannot match each other!
    if (asrCode == 0x0629 && refCode == 0x0647) return true; // ة <-> ه
    if (asrCode == 0x062A && refCode == 0x0629) return true; // ت <-> ة

    return false;
  }

  static bool _isHamzaVariant(int code) =>
      code == 0x0621 || code == 0x0622 || code == 0x0623 || code == 0x0625 || code == 0x0672;

  // ── 3. Model Acoustic Confusion Matrix (Cost = 0.25) ──
  static bool _isAcousticConfusion(int asrCode, int refCode) {
    if (asrCode > refCode) {
      final int temp = asrCode;
      asrCode = refCode;
      refCode = temp;
    }

    switch (asrCode) {
      // Vowels vs Harakat (Short vs Long vowel duration confusion)
      case 0x0627: // ا (Alif)
        return refCode == 0x064E; // َ (Fatha)
      case 0x0648: // و (Waw)
        return refCode == 0x064F; // ُ (Damma)
      case 0x064F: // ُ (Damma) (smaller than Small Waw 0x06E5)
        return refCode == 0x06E5; // ۥ (Small Waw)
      case 0x064A: // ي (Yaa)
        return refCode == 0x0650; // ِ (Kasra)
      case 0x0650: // ِ (Kasra) (smaller than Small Yaa 0x06E6)
        return refCode == 0x06E6; // ۦ (Small Yaa)

      // Consonant acoustic confusions
      case 0x062A: // ت
        return refCode == 0x0637; // ط
      case 0x062C: // ج
        return refCode == 0x0632; // ز
      case 0x062E: // خ
        return refCode == 0x063A; // غ
      case 0x062F: // د
        return refCode == 0x0636; // ض
      case 0x0630: // ذ
        return refCode == 0x0632 || refCode == 0x0638; // ز, ظ
      case 0x0633: // س
        return refCode == 0x0635; // ص
      case 0x0642: // ق
        return refCode == 0x0643; // ك
      default:
        return false;
    }
  }

  // ── 4. Tashkeel / Short Vowel Detection (Cost = 1.0) ──
  static bool isTashkeel(int code) =>
      code == 0x064E || code == 0x064F || code == 0x0650; // Fatha, Damma, Kasra

  // ── 5. Substitution Cost Evaluation ──
  static double getSubstitutionCost(
    int asrCodeUnit,
    int refCodeUnit, [
    double acousticConfusionCost = 0.25,
  ]) {
    if (asrCodeUnit == refCodeUnit) return 0.0;

    if (isEquivalentGlyph(asrCodeUnit, refCodeUnit)) {
      return 0.0;
    }

    // CHECK CONFUSIONS FIRST: (Allows Fatha <-> Alif to pass with acousticConfusionCost)
    if (_isAcousticConfusion(asrCodeUnit, refCodeUnit)) {
      return acousticConfusionCost;
    }

    // STRICT HARAKAT PENALTY: (If it involves a Harakat but wasn't in the matrix above, it's a 1.0 error)
    if (isTashkeel(asrCodeUnit) || isTashkeel(refCodeUnit)) {
      return 1.00;
    }

    return 1.00;
  }

  // ── 6. Deletion Cost (Expected phoneme missing from stream) ──
  static double getDeletionCost(
    String fullPhonemes,
    int gRefIdx, [
    double standardDeletionCost = 1.0,
    double acousticConfusionCost = 0.25,
  ]) {
    if (gRefIdx < 0 || gRefIdx >= fullPhonemes.length) return standardDeletionCost;
    final int code = fullPhonemes.codeUnitAt(gRefIdx);

    if (_isZeroCostMarker(code)) return 0.0;

    if (gRefIdx > 0 && code == fullPhonemes.codeUnitAt(gRefIdx - 1)) {
      // In CTC, repeated phonetic features (like Madd vowels or Shaddah consonants)
      // are often emitted as a single acoustic spike by the ASR model unless heavily emphasized.
      // We apply an acoustic confusion discount so a single 'ب' can align with 'بب'.
      return acousticConfusionCost;
    }

    return standardDeletionCost;
  }

  // ── 7. Insertion Cost (Extra phoneme in ASR stream) ──
  static double getInsertionCost(
    String asrText,
    int asrIdx, [
    double standardInsertionCost = 1.0,
    double acousticConfusionCost = 0.25,
  ]) {
    if (asrIdx < 0 || asrIdx >= asrText.length) return standardInsertionCost;
    final int code = asrText.codeUnitAt(asrIdx);

    if (_isZeroCostMarker(code)) return 0.0;

    if (asrIdx > 0 && code == asrText.codeUnitAt(asrIdx - 1)) {
      if (code == 0x0627 || code == 0x0648 || code == 0x064A || code == 0x06E5 || code == 0x06E6) {
        return acousticConfusionCost;
      }
    }

    return standardInsertionCost;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Per-word semi-global DTW matcher operating directly on character strings.
// ═══════════════════════════════════════════════════════════════════════════════

class QuranDictationMatcher {
  Float64List _dp = Float64List(2048);
  Uint8List _bt = Uint8List(2048);

  /// Aligns [asrText] against the reference slice [refStart, refEnd) in [fullPhonemes].
  ///
  /// Returns the best match or null if no alignment meets the threshold.
  WordMatchResult? matchWord({
    required String asrText,
    required List<double> asrTimestamps,
    required String fullPhonemes,
    required int refStart,
    required int refEnd,
    TrackerConfig config = const TrackerConfig(),
    bool isTajweed = false,
  }) {
    final int m = asrText.length;
    final int n = refEnd - refStart;
    if (m == 0 || n <= 0) return null;

    // ═════════════════════════════════════════════════════════════════════════
    // 1. BUFFER MANAGEMENT
    // ═════════════════════════════════════════════════════════════════════════
    final int stride = n + 1;
    final int cells = (m + 1) * stride;
    if (_dp.length < cells) {
      final int sz = max(cells, _dp.length * 2);
      _dp = Float64List(sz);
      _bt = Uint8List(sz);
    }

    final dp = _dp;
    final bt = _bt;

    // ═════════════════════════════════════════════════════════════════════════
    // 2. MATRIX INITIALIZATION
    // ═════════════════════════════════════════════════════════════════════════
    // Row 0: reference deletions (word phonemes with no ASR)
    dp[0] = 0.0;
    bt[0] = 0;
    for (int j = 1; j <= n; j++) {
      final double delCost = PhoneticCostEngine.getDeletionCost(
        fullPhonemes,
        refStart + j - 1,
        config.standardDeletionCost,
        config.acousticConfusionCost,
      );
      dp[j] = dp[j - 1] + delCost;
      bt[j] = 1; // delete
    }

    // Column 0: FREE START (skip leading ASR noise characters at zero cost)
    for (int i = 1; i <= m; i++) {
      dp[i * stride] = 0.0;
      bt[i * stride] = 2; // free insert
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 3. CORE DP FILL (DYNAMIC TIME WARPING WITH PHONETIC COST MATRIX)
    // ═════════════════════════════════════════════════════════════════════════
    for (int i = 1; i <= m; i++) {
      final int aCode = asrText.codeUnitAt(i - 1);
      final int row = i * stride;
      final int prev = (i - 1) * stride;
      final double insCost = PhoneticCostEngine.getInsertionCost(
        asrText,
        i - 1,
        config.standardInsertionCost,
        config.acousticConfusionCost,
      );

      for (int j = 1; j <= n; j++) {
        final int rRef = refStart + j - 1;
        final int rCode = fullPhonemes.codeUnitAt(rRef);

        final double subCost = PhoneticCostEngine.getSubstitutionCost(
          aCode,
          rCode,
          config.acousticConfusionCost,
        );
        final double delCost = PhoneticCostEngine.getDeletionCost(
          fullPhonemes,
          rRef,
          config.standardDeletionCost,
          config.acousticConfusionCost,
        );

        final double sub = dp[prev + j - 1] + subCost;
        final double del = dp[row + j - 1] + delCost;
        final double ins = dp[prev + j] + insCost;

        // We use `sub < del` instead of `sub <= del` to break ties in favor of deletions.
        // This forces the DP to match EARLY and delete LATE, ensuring trailing omissions
        // are correctly represented as `op == 1` (Deletion) at the end of the path,
        // which makes the Strict Frontier rule work reliably.
        if (sub < del && sub <= ins) {
          dp[row + j] = sub;
          bt[row + j] = 0; // match/sub
        } else if (del <= ins) {
          dp[row + j] = del;
          bt[row + j] = 1; // delete
        } else {
          dp[row + j] = ins;
          bt[row + j] = 2; // insert
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 4. ENDPOINT DETECTION (CALIBRATED DYNAMIC THRESHOLD)
    // ═════════════════════════════════════════════════════════════════════════
    int bestI = -1;
    double bestCost = double.infinity;

    // Effective length: collapse consecutive identical Madd vowels (ا, و, ي, ۥ, ۦ)
    // and skip zero-cost markers so the error budget reflects real word content.
    int effN = 0;
    for (int j = 0; j < n; j++) {
      final int code = fullPhonemes.codeUnitAt(refStart + j);
      if (PhoneticCostEngine._isZeroCostMarker(code)) continue;
      if (j > 0 && code == fullPhonemes.codeUnitAt(refStart + j - 1) &&
          (code == 0x0627 || code == 0x0648 || code == 0x064A || code == 0x06E5 || code == 0x06E6)) {
        continue;
      }
      effN++;
    }
    if (effN < 1) effN = 1;

    // Dynamic threshold: scaled to guarantee matching at >= 70% accuracy (up to 30% error)
    // while preventing random acoustic noise from triggering false greens on short words.
    double threshold = config.defaultMaxPathCost;
    if (effN <= 3) {
      threshold = min(threshold, config.shortWordPathCost);
    } else if (effN <= 7) {
      threshold = min(threshold, config.mediumWordPathCost);
    } else {
      threshold = min(threshold, config.defaultMaxPathCost);
    }

    for (int i = 1; i <= m; i++) {
      final double norm = dp[i * stride + n] / effN;
      if (norm <= threshold) {
        if (norm <= bestCost) { // Changed to <= to consume trailing vowels on tie
          bestI = i;
          bestCost = norm;
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 5. PARTIAL MATCHING LOGIC
    // ═════════════════════════════════════════════════════════════════════════
    bool isPartial = false;
    // Strict Frontier Rule: If Tajweed is ON, and we consumed the entire buffer (bestI == m),
    // we ONLY wait if a core consonant or vowel is missing/incomplete at the trailing edge.
    // If the trailing error is merely Tashkeel/Waqf, the word is complete and commits immediately.
    if (isTajweed && bestI > 0 && bestI == m) {
      int curJ = n;
      int curI = bestI;
      bool hasCoreConsonantMissing = false;

      // 1. Check all trailing deletions at the stream frontier
      while (curJ > 0 && curI == bestI && bt[curI * stride + curJ] == 1) {
        final int rCode = fullPhonemes.codeUnitAt(refStart + curJ - 1);
        final bool isRepeated = curJ > 1 && rCode == fullPhonemes.codeUnitAt(refStart + curJ - 2);
        
        // If the trailing deleted character is a core non-repeated consonant, the word is incomplete.
        if (!PhoneticCostEngine.isTashkeel(rCode) &&
            !PhoneticCostEngine._isZeroCostMarker(rCode) &&
            !isRepeated) {
          hasCoreConsonantMissing = true;
          break;
        }
        curJ--;
      }

      if (hasCoreConsonantMissing) {
        isPartial = true;
      } else if (curJ > 0 && bt[curI * stride + curJ] == 0) {
        // 2. Trailing substitution at the frontier
        final int asrCode = asrText.codeUnitAt(bestI - 1);
        final int refCode = fullPhonemes.codeUnitAt(refStart + curJ - 1);

        // If both are Tashkeel (e.g. 'ُ' vs 'ِ'), it's a Tashkeel error on a completed word, NOT a partial stream
        if (PhoneticCostEngine.isTashkeel(asrCode) &&
            PhoneticCostEngine.isTashkeel(refCode)) {
          isPartial = false;
        } else if (PhoneticCostEngine.getSubstitutionCost(asrCode, refCode) > 0.0) {
          isPartial = true;
        }
      }
    } else if (bestI < 0) {
      // ── 1. Prefix Match (For words that failed the full cost threshold) ──
      int minJ = n > 2 ? 2 : 1;
      int startI = max(1, m - 2);
      for (int i = startI; i <= m; i++) {
        for (int j = minJ; j < n; j++) {
          if (dp[i * stride + j] / j <= threshold) {
            isPartial = true;
            break;
          }
        }
        if (isPartial) break;
      }
    }
    
    if (isPartial) {
      return const WordMatchResult(
        pathCost: 0.0,
        tokensConsumed: 0,
        cleanAsr: '',
        timestamps: [],
        trace: [],
        isPartial: true,
      );
    }

    // If no full match was found and prefix match also failed, it's a complete mismatch
    if (bestI < 0) {
      return null;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 6. TRACEBACK & RESULTS
    // ═════════════════════════════════════════════════════════════════════════
    int ci = bestI, cj = n;
    final List<PhonemeGroupAlignment> rawTrace = [];
    final List<double> ts = [];

    while (cj > 0) {
      if (ci == 0) {
        rawTrace.add(
          PhonemeGroupAlignment(
            opType: 'delete',
            refIdx: refStart + cj - 1,
            predIdx: -1,
          ),
        );
        cj--;
        continue;
      }

      final int op = bt[ci * stride + cj];
      final int gRef = refStart + cj - 1;

      if (op == 0) {
        final int asrCode = asrText.codeUnitAt(ci - 1);
        final int refCode = fullPhonemes.codeUnitAt(gRef);
        final bool isMatch = PhoneticCostEngine.getSubstitutionCost(asrCode, refCode) == 0.0;
        rawTrace.add(
          PhonemeGroupAlignment(
            opType: isMatch ? 'match' : 'replace',
            refIdx: gRef,
            predIdx: ci - 1,
          ),
        );
        if (ci - 1 < asrTimestamps.length) ts.add(asrTimestamps[ci - 1]);
        ci--;
        cj--;
      } else if (op == 1) {
        rawTrace.add(
          PhonemeGroupAlignment(opType: 'delete', refIdx: gRef, predIdx: -1),
        );
        cj--;
      } else {
        rawTrace.add(
          PhonemeGroupAlignment(opType: 'insert', refIdx: gRef, predIdx: ci - 1),
        );
        ci--;
      }
    }

    return WordMatchResult(
      pathCost: bestCost,
      tokensConsumed: bestI,
      cleanAsr: asrText.substring(0, bestI),
      timestamps: ts.reversed.toList(),
      trace: rawTrace.reversed.toList(),
    );
  }
}
