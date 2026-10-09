// lib/engine/asr_token_processor.dart
import 'dart:math';

import '../tracking/tracker_config.dart';
import 'sherpa_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ASR ACOUSTIC TOKEN PROCESSOR & AUDIO STREAM
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents the filtered speech tokens and their acoustic durations.
class ProcessedAudioStream {
  final List<String> tokens;
  final List<double> durations;

  ProcessedAudioStream({required this.tokens, required this.durations});

  bool get isEmpty => tokens.isEmpty;
  bool get isNotEmpty => tokens.isNotEmpty;

  /// Returns the continuous phoneme text without CTC blanks.
  String get text => tokens.join('');

  /// Returns durations distributed evenly across characters.
  /// Guarantees that `text.length == charDurations.length` for Tajweed DTW alignment.
  List<double> get charDurations {
    final List<double> result = [];
    for (int i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      final dur = durations[i] / max(1, tok.length);
      for (int c = 0; c < tok.length; c++) {
        result.add(dur);
      }
    }
    return result;
  }
}

/// Ingests raw CTC tokens and timestamps from Sherpa-ONNX, filters silence/blank tokens,
/// and computes accurate acoustic phoneme durations using max(backward, forward) spike intervals.
class AsrTokenProcessor {
  TrackerConfig config;

  AsrTokenProcessor({this.config = const TrackerConfig()});

  /// Standard CTC blank lookahead delay for the Sherpa-ONNX streaming model.
  static const double ctcLookaheadDelay = 0.320;

  double get lookaheadDelay => ctcLookaheadDelay;
  double get maxTokenDuration => config.maxTokenDurationAllowed;

  List<String> _lastRawTokens = [];

  final List<String> _filteredTokens = [];
  final List<double> _filteredSpikeTimes = [];
  final List<double> _filteredLastBlanks = [];

  final List<double> _tokenDurations = [];

  void reset() {
    _lastRawTokens.clear();
    _filteredTokens.clear();
    _filteredSpikeTimes.clear();
    _filteredLastBlanks.clear();
    _tokenDurations.clear();
  }

  ProcessedAudioStream process(TranscriptionResult result) {
    final int maxCount = min(result.tokens.length, result.timestamps.length);

    int commonLen = 0;
    final int minLen = min(_lastRawTokens.length, maxCount);
    for (int i = 0; i < minLen; i++) {
      if (_lastRawTokens[i] == result.tokens[i]) {
        commonLen++;
      } else {
        break;
      }
    }

    if (commonLen < _lastRawTokens.length) {
      reset();
      commonLen = 0;
    }

    _lastRawTokens = result.tokens.sublist(0, maxCount);

    if (commonLen == maxCount) {
      return ProcessedAudioStream(
        tokens: _filteredTokens,
        durations: _tokenDurations,
      );
    }

    double lastBlankTs =
        _filteredLastBlanks.isNotEmpty ? _filteredLastBlanks.last : -1.0;

    for (int i = commonLen; i < maxCount; i++) {
      final String tok = result.tokens[i];
      final double realTs = max(0.0, result.timestamps[i] - lookaheadDelay);

      if (tok.isEmpty ||
          tok == '<blank>' ||
          tok == '<blk>' ||
          tok == '<eps>' ||
          tok == 'eps') {
        lastBlankTs = realTs;
        continue;
      }

      _filteredTokens.add(tok);
      _filteredSpikeTimes.add(realTs);
      _filteredLastBlanks.add(lastBlankTs);

      final int fIdx = _filteredTokens.length - 1;
      final double curSpike = _filteredSpikeTimes[fIdx];
      final double lastBlankBefore = _filteredLastBlanks[fIdx];

      // ── Max(Backward, Forward) Duration Attribution ──
      //
      // CTC spikes mark peak posterior probability, NOT sound onset.
      // The backward interval (prev_spike → cur_spike) partially
      // overlaps with BOTH the previous token's tail AND the current
      // token's onset delay. Neither interval alone captures a token's
      // full acoustic duration:
      //
      //  - Short Madds (2 Harakat): backward interval is larger because
      //    it captures the onset delay before the CTC spike fired.
      //  - Long Madds (4-6 Harakat): forward interval is larger because
      //    the vowel is held long after the spike until the next sound.
      //
      // Using max(backward, forward) per token provides a robust
      // estimate: whichever interval captured more of the token's
      // actual acoustic time wins.

      // 1. Retroactively update PREVIOUS token with its forward interval.
      //    The previous token's duration becomes max(backward, forward).
      if (fIdx > 0) {
        final int prevIdx = fIdx - 1;
        final double prevSpike = _filteredSpikeTimes[prevIdx];

        // If a blank (silence) occurred between spikes, the previous
        // token's voicing ended at the blank, not at the current spike.
        double prevEnd = curSpike;
        if (lastBlankBefore > prevSpike && lastBlankBefore < curSpike) {
          prevEnd = lastBlankBefore;
        }

        final double forwardInterval =
            min(maxTokenDuration, max(0.04, prevEnd - prevSpike));

        // max(backward already stored, forward just computed)
        _tokenDurations[prevIdx] =
            max(_tokenDurations[prevIdx], forwardInterval);
      }

      // 2. Current token: backward interval as initial estimate.
      //    Will be max'd with its forward interval when the next
      //    token arrives (step 1 above on the next iteration).
      double prevSpikeTime = (fIdx == 0)
          ? max(0.0, curSpike - 0.15)
          : _filteredSpikeTimes[fIdx - 1];

      if (lastBlankBefore > prevSpikeTime) {
        prevSpikeTime = lastBlankBefore;
      }

      final double backwardInterval =
          min(maxTokenDuration, max(0.04, curSpike - prevSpikeTime));
      _tokenDurations.add(backwardInterval);
    }

    return ProcessedAudioStream(
      tokens: _filteredTokens,
      durations: _tokenDurations,
    );
  }
}
