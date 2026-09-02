import 'dart:math';

/// Result of evaluating whether a word was omitted from a verse recitation.
class OmissionResult {
  /// Whether an omission was detected with high likelihood.
  final bool isOmissionDetected;

  /// The 0-based word index within the ayah of the nominated omitted word (if detected).
  final int? omittedWordIndex;

  /// Phoneme character shortfall count (`refLength - lcsLength`).
  final int shortfall;

  /// Difference between top-1 drop score and top-2 drop score.
  final int confidenceGap;

  /// Ratio of top-1 LCS score relative to emitted text length.
  final double scoreRatio;

  const OmissionResult({
    required this.isOmissionDetected,
    this.omittedWordIndex,
    required this.shortfall,
    required this.confidenceGap,
    required this.scoreRatio,
  });

  @override
  String toString() {
    return 'OmissionResult(detected: $isOmissionDetected, omittedWordIndex: $omittedWordIndex, '
        'shortfall: $shortfall, gap: $confidenceGap, scoreRatio: ${scoreRatio.toStringAsFixed(3)})';
  }
}

/// Dynamic-programming Longest Common Subsequence (LCS) omission locator
/// based on the Best-Drop algorithm from the `tasmee3-muaalem-findings` benchmark.
class LcsOmissionDetector {
  /// Computes the Longest Common Subsequence (LCS) length between two strings.
  static int lcsLength(String s1, String s2) {
    final n = s1.length;
    final m = s2.length;
    if (n == 0 || m == 0) return 0;

    // Use 2-row DP buffer to minimize memory allocations
    List<int> previousRow = List<int>.filled(m + 1, 0);
    List<int> currentRow = List<int>.filled(m + 1, 0);

    for (int i = n - 1; i >= 0; i--) {
      final c1 = s1.codeUnitAt(i);
      for (int j = m - 1; j >= 0; j--) {
        if (c1 == s2.codeUnitAt(j)) {
          currentRow[j] = previousRow[j + 1] + 1;
        } else {
          currentRow[j] = max(previousRow[j], currentRow[j + 1]);
        }
      }
      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[0];
  }

  /// Evaluates an emitted phoneme string against expected phonemes for each word in a verse.
  ///
  /// [phonemesPerWord]: List of phoneme strings for each word in the ayah in order.
  /// [emittedPhonemes]: Raw phoneme string produced by the recitation ASR engine.
  static OmissionResult detectOmission({
    required List<String> phonemesPerWord,
    required String emittedPhonemes,
  }) {
    if (phonemesPerWord.isEmpty) {
      return const OmissionResult(
        isOmissionDetected: false,
        shortfall: 0,
        confidenceGap: 0,
        scoreRatio: 0.0,
      );
    }

    final emittedLen = emittedPhonemes.length;
    final refFull = phonemesPerWord.join('');
    final refLen = refFull.length;

    if (emittedLen == 0) {
      return OmissionResult(
        isOmissionDetected: true,
        omittedWordIndex: 0,
        shortfall: refLen,
        confidenceGap: 0,
        scoreRatio: 0.0,
      );
    }

    final lcsFull = lcsLength(refFull, emittedPhonemes);
    final shortfall = refLen - lcsFull;

    // Length Gate: If shortfall is 0, the utterance matches full reference or is an insertion
    if (shortfall <= 0) {
      return OmissionResult(
        isOmissionDetected: false,
        shortfall: shortfall,
        confidenceGap: 0,
        scoreRatio: lcsFull / emittedLen,
      );
    }

    // Best-Drop Calculation: Score reference with each word removed
    final scores = <int>[];
    final refWithoutLengths = <int>[];

    for (int wi = 0; wi < phonemesPerWord.length; wi++) {
      final buffer = StringBuffer();
      for (int i = 0; i < phonemesPerWord.length; i++) {
        if (i != wi) {
          buffer.write(phonemesPerWord[i]);
        }
      }
      final refWithout = buffer.toString();
      refWithoutLengths.add(refWithout.length);
      final score = lcsLength(refWithout, emittedPhonemes);
      scores.add(score);
    }

    // If every dropped LCS score strictly equals refWithout length, it indicates
    // a substitution/vowel error rather than a missing word
    bool allEqualRefWithout = true;
    for (int i = 0; i < scores.length; i++) {
      if (scores[i] != refWithoutLengths[i]) {
        allEqualRefWithout = false;
        break;
      }
    }

    if (allEqualRefWithout && scores.length > 1) {
      return OmissionResult(
        isOmissionDetected: false,
        shortfall: shortfall,
        confidenceGap: 0,
        scoreRatio: (scores.isNotEmpty ? scores.first : 0) / emittedLen,
      );
    }

    // Find the highest score (best drop)
    int maxScore = -1;
    int bestIndex = -1;
    for (int i = 0; i < scores.length; i++) {
      if (scores[i] > maxScore) {
        maxScore = scores[i];
        bestIndex = i;
      }
    }

    // Calculate gap between top 1 and top 2
    final sortedScores = List<int>.from(scores)..sort((a, b) => b.compareTo(a));
    final top1 = sortedScores[0];
    final top2 = sortedScores.length > 1 ? sortedScores[1] : 0;
    final gap = top1 - top2;

    return OmissionResult(
      isOmissionDetected: bestIndex >= 0,
      omittedWordIndex: bestIndex >= 0 ? bestIndex : null,
      shortfall: shortfall,
      confidenceGap: gap,
      scoreRatio: emittedLen > 0 ? maxScore / emittedLen : 0.0,
    );
  }
}
