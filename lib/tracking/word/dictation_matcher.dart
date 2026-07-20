import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import 'phoneme_matrix.dart';

///
/// FILE ROLE: Core Engine / DP Algorithm
/// ALGORITHM: Forward Substring DP (Levenshtein / Smith-Waterman variant)
/// DEPENDENCIES: phoneme_matrix.dart (Penalty Lookup)
/// RESPONSIBILITY:
/// - Compares ASR phoneme streams against Reference target text.
/// - Calculates insertion, deletion, and substitution costs.
/// - Determines the optimal mathematical alignment path (bestScore).
/// - Extracts the exact traceback (PhonemeGroupAlignment array) required by Tajweed rules.
/// AI NOTE: This file is purely mathematical. Do NOT add UI logic, app state, or buffer management here.
/// That belongs in `phoneme_alignment_isolate.dart`.
///

/// ────────────────────────────────────────────────────────────────────────────
/// [AlignmentResult] - The Output Payload
/// ────────────────────────────────────────────────────────────────────────────
/// This class holds the final results of a successful Dynamic Programming match.
/// When the matcher finishes chewing through thousands of possibilities, it
/// bundles the "best path" into this neat package to send back to the Orchestrator.
class WordMatch {
  final int wordId;
  final double score;

  WordMatch({required this.wordId, required this.score});
}

class AlignmentResult {
  /// The index where the ASR audio slice ENDED.
  /// This tells us exactly how much of the buffer we successfully consumed.
  final int bestI;

  /// The index where the Reference Text ENDED.
  /// If bestJ equals the total length of the target window, it means we
  /// successfully read the entire target word(s).
  final int bestJ;

  /// The index where the ASR audio slice BEGAN.
  /// Because we allow the user to have "garbage" sounds before they start reading
  /// the correct word, this index tells us exactly where the "garbage" stopped
  /// and the "real reading" began.
  final int bestStartI;

  /// The index where the Reference Text BEGAN.
  /// Usually this is 0 (the start of the word we are looking for).
  final int bestStartJ;

  /// The normalized penalty score for this match (between 0.0 and 1.0).
  /// This includes the artificial 'position prior' penalty, used by the engine
  /// to penalize jumping ahead too many words.
  final double bestScore;

  /// The pure acoustic penalty score (between 0.0 and 1.0) WITHOUT any artificial
  /// position penalties. This is passed to the Tajweed ErrorExplainer so it can accurately
  /// judge the microphone/audio quality without being contaminated by position jumps.
  final double pureAcousticScore;

  /// The exact step-by-step path the engine took to align the two strings.
  /// Each item in this list tells us: "At this phoneme, the user was equal,
  /// substituted, inserted, or deleted".
  /// This trace is the lifeblood of the Tajweed system.
  final List<PhonemeGroupAlignment> trace;

  /// The words that were successfully matched and passed the strictness threshold.
  final List<WordMatch> words;

  AlignmentResult({
    required this.bestI,
    required this.bestJ,
    required this.bestStartI,
    required this.bestStartJ,
    required this.bestScore,
    required this.pureAcousticScore,
    required this.trace,
    required this.words,
  });
}

/// ────────────────────────────────────────────────────────────────────────────
/// [ForwardDictationMatcher] - The Mathematical Brain
/// ────────────────────────────────────────────────────────────────────────────
/// This is the most computationally intense part of the entire application.
/// It uses a highly optimized variant of the Smith-Waterman / Levenshtein
/// Dynamic Programming algorithm.
///
/// Its job is to take a stream of raw, messy acoustic phonemes (ASR) and a clean
/// target string (Reference text), and find the optimal path that aligns them
/// with the lowest possible penalty score.
///
/// Why is it called "Forward"?
/// Because unlike old systems that allowed "wrap around" or "jumping backwards"
/// across Ayahs, this engine strictly forces the user to move forward in time.
/// This prevents the highlight from jumping wildly around the screen.
class ForwardDictationMatcher {
  /// The static penalty for completely dropping/skipping a required sound.
  /// E.g. The reference says 'ب', but the user never said anything.
  final double costDel = 1.0;

  /// The static penalty for the ASR hallucinating an extra sound.
  /// E.g. The reference says 'ب', but the ASR heard 'ب س'. The 'س' is an insertion.
  final double costIns = 1.0;

  /// The core mathematical function.
  /// Returns an [AlignmentResult] if a match was found below the threshold.
  /// Returns `null` if the user's speech was too different from the target text.
  AlignmentResult? align({
    /// The incoming phonemes from the microphone.
    required List<String> currentAsrChunks,

    /// The target phonemes the user is supposed to be reading.
    required List<String> targetWindow,

    /// A boolean array mapping which chunks represent the start of a new word.
    required List<bool> targetStartBd,

    /// A boolean array mapping which chunks represent the end of a word.
    required List<bool> targetEndBd,

    /// An array mapping every chunk to its specific Word ID in the Ayah.
    required List<int> targetWordIds,

    /// The exact Word ID we are actively hoping the user is reading right now.
    required int expectedWord,

    /// The maximum allowable penalty score. If the best path's score is higher
    /// than this threshold, we reject the match.
    required double threshold,

    bool requireStableTail = false,

    /// A callback function to print debug information to the Isolate console.
    void Function(String)? debugLog,
  }) {
    // -------------------------------------------------------------------------
    // Dimension Setup
    // m = Length of ASR string.
    // n = Length of Reference string.
    // The DP matrix will theoretically be (m) rows by (n) columns.
    // -------------------------------------------------------------------------
    int m = currentAsrChunks.length;
    int n = targetWindow.length;

    // Prior weight ensures we heavily favor matching the `expectedWord` rather than
    // accidentally matching a similar-sounding word 10 words ahead in the lookahead window.
    // Setting this higher prevents the engine from skipping the current word just because
    // it found a weak substring match for a future word inside a block of ASR noise.
    double priorWeight = 0.10;

    // -------------------------------------------------------------------------
    // Instant Integer Encoding
    // String comparisons in Dart are extremely slow. We instantly convert the
    // entire ASR and Reference strings into raw 32-bit Integer Arrays using
    // the high-speed PhonemeMatrix encoder.
    // -------------------------------------------------------------------------
    Int32List pIds = Int32List(m);
    for (int i = 0; i < m; i++) {
      pIds[i] = PhonemeMatrix.encode(currentAsrChunks[i]);
    }

    Int32List rIds = Int32List(n);
    for (int j = 0; j < n; j++) {
      rIds[j] = PhonemeMatrix.encode(targetWindow[j]);
    }

    // -------------------------------------------------------------------------
    // O(n) Memory Allocation (The Rolling Rows Technique)
    // -------------------------------------------------------------------------
    // Normally, a DP algorithm allocates an M x N matrix. If M=100 and N=100,
    // that's 10,000 floats. That is terrible for CPU cache locality.
    //
    // Because a DP algorithm only ever looks at the "Current Row" and the
    // "Previous Row", we don't need a full 2D grid!
    // We only allocate TWO rows. When we finish calculating the current row,
    // we swap them, and the current row becomes the previous row.
    // This reduces memory complexity from O(M*N) down to O(N). Extremely fast!

    // prevCost holds the DP float penalties for the previous ASR chunk
    Float64List prevCost = Float64List(n + 1);
    // currCost holds the DP float penalties being computed for the current ASR chunk
    Float64List currCost = Float64List(n + 1);

    // We also track the "origin" of every cell. This answers the question:
    // "Where did this specific alignment path originally start?"
    // This allows Substring matching, where the user can start matching the word
    // AFTER saying some garbage acoustic sounds.
    Int32List prevStartI = Int32List(n + 1);
    Int32List prevStartJ = Int32List(n + 1);
    Int32List currStartI = Int32List(n + 1);
    Int32List currStartJ = Int32List(n + 1);

    // -------------------------------------------------------------------------
    // [Tajweed] The 1-Byte Traceback Array
    // -------------------------------------------------------------------------
    // While the cost calculations can be crushed into just 2 rows, we still need
    // to remember the EXACT path we took if we want to extract Tajweed errors later.
    //
    // Instead of storing heavy 64-bit class objects for the path, we allocate a
    // massive but extremely lightweight 8-bit array (`Uint8List`).
    // Every cell in this M*N grid will store exactly 1 byte:
    // 0 = Substitution (Diagonal move)
    // 1 = Insertion (Vertical move)
    // 2 = Deletion (Horizontal move)
    // This allows native Tajweed Error checking without needing a second DP function.
    Uint8List op = Uint8List((m + 1) * (n + 1));

    // -------------------------------------------------------------------------
    // Initialization: Row 0
    // -------------------------------------------------------------------------
    // We initialize the topmost row. If the target string represents the start of
    // a valid word (`targetStartBd`), we allow a path to start here with 0.0 cost.
    // Otherwise, we block the path by assigning infinity.
    for (int j = 0; j <= n; j++) {
      if (targetStartBd[j]) {
        prevCost[j] = 0.0;
        prevStartI[j] = 0;
        prevStartJ[j] = j;
      } else {
        // [BUG FIX] Allow horizontal moves (Insertions) along Row 0. 
        // This is critical. If the user misses the first letter of a word, the path 
        // MUST be able to step horizontally from the word boundary to the second letter 
        // before consuming any ASR audio.
        if (j > 0 && prevCost[j - 1] < double.infinity) {
          prevCost[j] = prevCost[j - 1] + costIns;
          prevStartI[j] = prevStartI[j - 1];
          prevStartJ[j] = prevStartJ[j - 1];
          // Record '2' (Insertion) in the 1-byte traceback grid for Row 0
          op[j] = 2;
        } else {
          prevCost[j] = double.infinity;
          prevStartI[j] = -1;
          prevStartJ[j] = -1;
        }
      }
    }

    // Trackers for the absolute best path found in the entire matrix.
    int bestI = -1;
    int bestJ = -1;
    int bestStartI = -1;
    int bestStartJ = -1;
    double bestScore = double.infinity;
    double bestNormDist = double.infinity;

    // -------------------------------------------------------------------------
    // THE CORE DP LOOP
    // -------------------------------------------------------------------------
    // We iterate over every incoming ASR chunk (i).
    for (int i = 1; i <= m; i++) {
      // Initialize the first column of the current row.
      // Same logic as Row 0: If it's a valid word start boundary, allow a path to start.
      if (targetStartBd[0]) {
        currCost[0] = 0.0;
        currStartI[0] = i;
        currStartJ[0] = 0;
      } else {
        currCost[0] = double.infinity;
        currStartI[0] = -1;
        currStartJ[0] = -1;
      }

      // Grab the Integer ID of the current ASR phoneme.
      int pId = pIds[i - 1];

      // Inner loop: Iterate over every reference chunk (j).
      for (int j = 1; j <= n; j++) {
        // We have 3 possible paths to reach the current cell (i, j):

        // Path 1: Deletion. The ASR hallucinates a sound. We move vertically.
        // Cost = The penalty of the cell directly above us + Deletion Penalty.
        double delOpt = prevCost[j] + costDel;

        // Path 2: Insertion. The ASR missed a sound. We move horizontally.
        // Cost = The penalty of the cell directly to our left + Insertion Penalty.
        double insOpt = currCost[j - 1] + costIns;

        // Path 3: Substitution. The sounds match (or partially match). We move diagonally.
        // Cost = The penalty of the top-left cell + The dynamic PhonemeMatrix penalty.
        double subOpt =
            prevCost[j - 1] + PhonemeMatrix.getCost(pId, rIds[j - 1]);

        // ---------------------------------------------------------------------
        // Decision Making
        // ---------------------------------------------------------------------
        // We evaluate the 3 possible paths and pick the cheapest one.
        if (subOpt <= delOpt && subOpt <= insOpt) {
          // Substitution is the cheapest path.
          // Inherit the origin coordinates from the diagonal cell.
          currCost[j] = subOpt;
          currStartI[j] = prevStartI[j - 1];
          currStartJ[j] = prevStartJ[j - 1];
          // [Tajweed] Record '0' (Substitution) in the massive 1-byte grid.
          op[i * (n + 1) + j] = 0;
        } else if (delOpt <= insOpt) {
          // Deletion is the cheapest path.
          // Inherit the origin coordinates from the top cell.
          currCost[j] = delOpt;
          currStartI[j] = prevStartI[j];
          currStartJ[j] = prevStartJ[j];
          // [Tajweed] Record '1' (Deletion) in the massive 1-byte grid.
          op[i * (n + 1) + j] = 1;
        } else {
          // Insertion is the cheapest path.
          // Inherit the origin coordinates from the left cell.
          currCost[j] = insOpt;
          currStartI[j] = currStartI[j - 1];
          currStartJ[j] = currStartJ[j - 1];
          // [Tajweed] Record '2' (Insertion) in the massive 1-byte grid.
          op[i * (n + 1) + j] = 2;
        }
      }

      // -----------------------------------------------------------------------
      // End-of-Row Scoring Evaluation
      // -----------------------------------------------------------------------
      // After processing the entire row for this specific ASR chunk, we check
      // if any cell in the row represents a completed word (targetEndBd).
      for (int j = 1; j <= n; j++) {
        if (targetEndBd[j] && currCost[j] < double.infinity) {
          int stI = currStartI[j];
          int stJ = currStartJ[j];

          if (stI < 0 || stJ < 0) continue;

          // Calculate how many phonemes were consumed by both strings in this path.
          int refLen = j - stJ;
          int asrLen = i - stI;

          // CRITICAL: A valid word match MUST consume at least one reference character.
          // We cannot match against an empty string.
          if (refLen == 0) continue;

          // Normalize the penalty distance by dividing it by the length of the string.
          // This prevents long words from automatically accumulating too much penalty.
          int denom = max(asrLen, max(refLen, 1));

          // Protect short words (1-3 phonemes) from failing instantly on a single ASR glitch.
          if (denom < 4) denom = 4;

          double normDist = currCost[j] / denom;

          // Apply the Prior Weight.
          // If this path matched Word ID 5, but we were expecting Word ID 1,
          // we add a heavy penalty to discourage jumping ahead unnecessarily.
          int startWord = targetWordIds[stJ < n ? stJ : j - 1];
          double prior = priorWeight * (startWord - expectedWord).abs();

          // The Final Score is the combination of acoustic distance + prior penalty.
          double score = normDist + prior;

          // If the final score beats the strictness threshold...
          if (score <= threshold) {
            debugLog?.call(
              'Math: score=$score (normDist=$normDist [cost=${currCost[j]}/denom=$denom], prior=$prior)',
            );

            // [EDGE-BOUND TAIL STABILITY RULE]
            // We check if the tail of the word is mathematically stable before committing.
            bool isStable = true;
            if (requireStableTail) {
              // What happens if the user reads a word like "نَسْتَعِينُ" and holds the Madd?
              // The ASR will output "نَسْتَعِ" (missing the N) and pause while the Madd is held.
              // Without this rule, the DP engine would eagerly commit "نَسْتَعِ" as a match
              // (accepting a Deletion penalty for the N) because it falls below the threshold.
              //
              // To prevent this "early commit", we look at the exact Edge of the ASR buffer (i == m).
              // If the best mathematical path is pinned exactly against the live edge (i == m),
              // AND that path ends in a Deletion (op == 2, meaning "I am missing the final letter"),
              // it means the tail has NOT arrived yet! We force the engine to wait for more audio.
              //
              // Note: We used to have an exception here that skipped this rule for the last word
              // of the Ayah (j < n). That was a bug. It caused the engine to prematurely commit
              // incomplete words at the end of the Ayah. We removed it so this protection now
              // applies to EVERY word equally.
              if (i == m && op[i * (n + 1) + j] == 2) {
                isStable = false;
              }
            }

            // ...and it is better than any previous score we found in this matrix...
            if (isStable && score <= bestScore) {
              // ...we have a new reigning champion!
              bestScore = score;
              bestNormDist =
                  normDist; // Store the pure acoustic score for Tajweed
              bestI = i;
              bestJ = j;
              bestStartI = stI;
              bestStartJ = stJ;
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // Row Swapping (The Magic of O(n) Memory)
      // -----------------------------------------------------------------------
      // Before moving to the next ASR chunk (i+1), we swap the pointers.
      // The current row becomes the previous row. The previous row is overwritten.
      final tmpC = prevCost;
      prevCost = currCost;
      currCost = tmpC;

      final tmpSI = prevStartI;
      prevStartI = currStartI;
      currStartI = tmpSI;

      final tmpSJ = prevStartJ;
      prevStartJ = currStartJ;
      currStartJ = tmpSJ;
    }

    // -------------------------------------------------------------------------
    // Matrix Finished. Traceback Extraction.
    // -------------------------------------------------------------------------
    // If we survived the nested loops and found a valid champion path (bestI != -1),
    // we need to extract the exact step-by-step trace so the Tajweed engine can
    // analyze the user's specific phonetic mistakes.
    if (bestI != -1) {
      String matchedAsr = currentAsrChunks.sublist(bestStartI, bestI).join('');
      String matchedRef = targetWindow.sublist(bestStartJ, bestJ).join('');
      debugLog?.call(
        '✅ [DP SUCCESS] Matched: "$matchedAsr" ➔ "$matchedRef" | Score: ${bestScore.toStringAsFixed(3)} <= $threshold',
      );

      List<PhonemeGroupAlignment> trace = [];
      int currI = bestI;
      int currJ = bestJ;

      // [Tajweed] Native Traceback from the 1-byte array.
      // We start at the end of the winning path (bestI, bestJ).
      // We walk completely backward through the grid until we hit the origin (bestStartI, bestStartJ).
      while (currI > bestStartI || currJ > bestStartJ) {
        // Grab the 1-byte directional indicator we saved earlier.
        int opType = op[currI * (n + 1) + currJ];

        if (currI > bestStartI && currJ > bestStartJ && opType == 0) {
          // Op 0: Substitution or Exact Match (Diagonal step backward)
          double sc = PhonemeMatrix.getCost(pIds[currI - 1], rIds[currJ - 1]);
          trace.add(
            PhonemeGroupAlignment(
              // If the penalty score is practically zero (<=0.25), it's a valid match.
              // Otherwise, it was heavily penalized, meaning it is a 'replace' error for Tajweed.
              opType: sc <= 0.25 ? 'equal' : 'replace',
              refIdx: (currJ - 1) - bestStartJ,
              predIdx: (currI - 1) - bestStartI,
            ),
          );
          currI--;
          currJ--;
        } else if (currI > bestStartI && opType == 1) {
          // Op 1: Deletion / ASR-Insertion (Vertical step backward)
          // The ASR hallucinates a sound not in the text.
          trace.add(
            PhonemeGroupAlignment(
              opType: 'insert',
              refIdx: currJ > bestStartJ ? currJ - 1 : -1,
              predIdx: (currI - 1) - bestStartI,
            ),
          );
          currI--;
        } else if (currJ > bestStartJ) {
          // Op 2: Insertion / ASR-Deletion (Horizontal step backward)
          // The user swallowed a letter and the ASR missed it.
          trace.add(
            PhonemeGroupAlignment(
              opType: 'delete',
              refIdx: currJ - 1,
              predIdx: currI > bestStartI ? (currI - 1) - bestStartI : -1,
            ),
          );
          currJ--;
        } else {
          // Safety break in case of an invalid matrix state.
          break;
        }
      }

      // We built the list by walking backwards, so we must reverse it before returning!
      List<PhonemeGroupAlignment> finalTrace = trace.reversed.toList();

      // ═════════════════════════════════════════════════════════════════════════
      // [POST-PROCESSING] NATIVE WORD PARSING & STRICTNESS CHECK
      // ═════════════════════════════════════════════════════════════════════════
      // The DP matrix computes one overall `bestScore` for the entire path.
      // However, if the user reads a long phrase (e.g., Word 2 + Word 3), the DP
      // might "average out" a mumbled Word 2 with a perfectly spoken Word 3.
      //
      // To prevent this, we natively segment the DP traceback by word boundaries.
      // We calculate the exact penalty for each individual word. If a word's
      // individual score fails the `threshold`, we explicitly drop it from the
      // `verifiedWords` list, forcing the UI to highlight it as skipped (Red).

      // Trackers for individual word statistics
      Map<int, int> asrLens =
          {}; // How many ASR phonemes were assigned to each word
      Map<int, int> refLens =
          {}; // How many Reference phonemes belong to each word
      Map<int, double> penalties =
          {}; // Total penalty score (insertions, deletions, replacements) for each word
      Map<int, double> wordTailCost =
          {}; // [Tail Anchor] Tracks the cost of the final reference phoneme for each word

      // Determine the Word ID where the winning path started.
      int matchedWordStart = targetWordIds[bestStartJ < n ? bestStartJ : n - 1];

      // `currentWId` tracks which word the current traceback operation belongs to.
      int currentWId = matchedWordStart;

      // ── Step 1: Iterate the traceback and distribute penalties ──
      for (var align in finalTrace) {
        if (align.refIdx >= 0) {
          int absRefIdx = bestStartJ + align.refIdx;
          if (absRefIdx < targetWordIds.length) {
            currentWId = targetWordIds[absRefIdx];
          }
          
          // [Tail Anchor] Constantly overwrite the tail cost for the current word.
          // Since the trace is sequential, this will ultimately hold the cost of the FINAL reference phoneme.
          // We ignore 'insert' because insertions don't consume reference phonemes.
          if (align.opType == 'delete') {
            wordTailCost[currentWId] = costDel;
          } else if (align.predIdx >= 0 && align.opType != 'insert') {
            wordTailCost[currentWId] = PhonemeMatrix.getCost(
              pIds[bestStartI + align.predIdx],
              rIds[bestStartJ + align.refIdx],
            );
          }
        }

        if (align.predIdx >= 0)
          asrLens[currentWId] = (asrLens[currentWId] ?? 0) + 1;
        if (align.refIdx >= 0)
          refLens[currentWId] = (refLens[currentWId] ?? 0) + 1;

        if (align.opType == 'insert') {
          penalties[currentWId] = (penalties[currentWId] ?? 0.0) + costIns;
        } else if (align.opType == 'delete') {
          penalties[currentWId] = (penalties[currentWId] ?? 0.0) + costDel;
        } else if (align.opType == 'replace') {
          double exactCost = PhonemeMatrix.getCost(
            pIds[bestStartI + align.predIdx],
            rIds[bestStartJ + align.refIdx],
          );
          penalties[currentWId] = (penalties[currentWId] ?? 0.0) + exactCost;
        }
      }

      // ── Step 2: Evaluate individual word strictness ──
      List<WordMatch> verifiedWords = [];
      for (int wId in asrLens.keys) {
        int asrLen = asrLens[wId] ?? 0;
        int refLen = refLens[wId] ?? 0;
        double penalty = penalties[wId] ?? 0.0;

        // The individual word score is calculated exactly like the segment score:
        // Penalty / max(Length).
        int denom = max(asrLen, max(refLen, 1));

        // Protect short words from failing due to a single 1.0 penalty.
        if (denom < 4) denom = 4;

        double wordScore = penalty / denom;
        double tailCost = wordTailCost[wId] ?? 1.0;

        // [Tail Anchor] If Tajweed mode is on, enforce that the word's final phoneme
        // must be a perfect match (0.0 cost) to prevent fabricated matches on short words.
        bool passesTailAnchor = !requireStableTail || tailCost == 0.0;

        // If the word passes the strictness threshold on its own, it is verified!
        if (wordScore <= threshold && passesTailAnchor) {
          verifiedWords.add(WordMatch(wordId: wId, score: wordScore));
        } else {
          // If the word score is too high, it was a "mumbled" word that the DP
          // tried to drag across the finish line. We drop it here!
          String dropWordStr = '';
          for (int k = 0; k < targetWindow.length; k++) {
            if (targetWordIds[k] == wId) dropWordStr += targetWindow[k];
          }
          String reason = wordScore > threshold
              ? '(Score: ${wordScore.toStringAsFixed(3)} > $threshold)'
              : '(Failed Tail Anchor: TailCost=$tailCost)';
          debugLog?.call(
            '⚠️ [DP STRICTNESS] Dropping Word "$dropWordStr" ($wId) $reason',
          );
        }
      }

      // If the match was so poor that EVERY single word inside it failed the
      // strictness evaluation, then this entire segment match is likely just
      // ASR hallucination or background noise. We must abort and return null
      // so the Sequencer doesn't accidentally advance the cursor and mark them red.
      if (verifiedWords.isEmpty) {
        debugLog?.call(
          '⚠️ [DP STRICTNESS] All matched words failed strictness. Aborting segment match. Waiting for better audio...',
        );
        return null;
      }

      return AlignmentResult(
        bestI: bestI,
        bestJ: bestJ,
        bestStartI: bestStartI,
        bestStartJ: bestStartJ,
        bestScore: bestScore,
        pureAcousticScore: bestNormDist,
        trace: finalTrace,
        words: verifiedWords,
      );
    }

    // If no path beat the strictness threshold, return null. The user must keep reading.
    return null;
  }
}
