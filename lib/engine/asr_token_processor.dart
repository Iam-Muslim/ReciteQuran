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

  /// Returns durations distributed across characters.
  /// Guarantees that `text.length == charDurations.length` for DTW alignment.
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

/// Ingests raw CTC tokens and timestamps from Sherpa-ONNX, filters special/blank tokens,
/// and computes accurate acoustic phoneme durations reflecting real recitation articulation.
class AsrTokenProcessor {
  TrackerConfig config;

  AsrTokenProcessor({this.config = const TrackerConfig()});

  /// Standard CTC lookahead delay for causal Zipformer streaming models.
  static const double ctcLookaheadDelay = 0.140;

  double get lookaheadDelay => ctcLookaheadDelay;
  double get maxTokenDuration => config.maxTokenDurationAllowed;

  List<String> _lastRawTokens = [];

  final List<String> _filteredTokens = [];
  final List<double> _filteredSpikeTimes = [];
  final List<double> _tokenDurations = [];

  void reset() {
    _lastRawTokens.clear();
    _filteredTokens.clear();
    _filteredSpikeTimes.clear();
    _tokenDurations.clear();
  }

  /// Determines if a token is a prolonged vocalic Madd sound (ا, و, ي, ۦ, ۥ).
  static bool isMaddToken(String tok) {
    if (tok.isEmpty) return false;
    for (int i = 0; i < tok.length; i++) {
      final int c = tok.codeUnitAt(i);
      if (c == 0x0627 || // ا
          c == 0x0648 || // و
          c == 0x064A || // ي
          c == 0x06E5 || // ۥ
          c == 0x06E6 || // ۦ
          c == 0x0672) {
        // ٲ
        return true;
      }
    }
    return false;
  }

  /// Determines if a token represents an acoustic Ghunnah (held nasal sound).
  static bool isGhunnahToken(String tok) {
    if (tok.isEmpty) return false;
    if (tok.startsWith('مم') ||
        tok.startsWith('نن') ||
        tok.contains('ں') ||
        tok.contains('۾')) {
      return true;
    }
    return false;
  }

  /// Ingests a new [TranscriptionResult] from the ASR recognizer,
  /// updates filtered tokens and recomputes continuous acoustic durations.
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

    // Ingest newly arrived non-blank tokens into filtered arrays
    for (int i = commonLen; i < maxCount; i++) {
      final String tok = result.tokens[i];
      final double rawTs = result.timestamps[i];

      // Defensively filter empty or special CTC blank / epsilon tokens.
      if (tok.isEmpty ||
          tok == '<blank>' ||
          tok == '<blk>' ||
          tok == '<eps>' ||
          tok == 'eps') {
        continue;
      }

      _filteredTokens.add(tok);
      _filteredSpikeTimes.add(rawTs);
    }

    // Recompute accurate acoustic durations across all filtered tokens
    _recomputeDurations();

    return ProcessedAudioStream(
      tokens: _filteredTokens,
      durations: _tokenDurations,
    );
  }

  /// Recomputes acoustic durations for all tokens in `_filteredTokens`.
  ///
  /// In continuous speech CTC:
  /// - A spike marks peak posterior probability, NOT instantaneous sound boundaries.
  /// - The sound for token `i` starts during the transition from token `i-1` and continues
  ///   through the transition into token `i+1`.
  /// - Taking `max(backward, forward)` artificially discards half the acoustic envelope.
  /// - Standard consonants use boundary midpoint partitioning:
  ///     duration = (Δ_prev + Δ_next) / 2
  /// - Prolonged Madd vowels and Ghunnah use the full vocalic hold between consonant boundaries:
  ///     duration = (Δ_prev - consonant_offset) + Δ_next
  void _recomputeDurations() {
    final int count = _filteredTokens.length;
    _tokenDurations.clear();
    if (count == 0) {
      return;
    }

    for (int i = 0; i < count; i++) {
      final String tok = _filteredTokens[i];
      final double curSpike = _filteredSpikeTimes[i];

      final bool isMadd = isMaddToken(tok);
      final bool isGhunnah = isGhunnahToken(tok);
      final bool isElongated = isMadd || isGhunnah;

      // ── Backward interval (time elapsed from previous token) ──
      double deltaPrev;
      if (i > 0) {
        deltaPrev = max(0.04, curSpike - _filteredSpikeTimes[i - 1]);
      } else {
        deltaPrev = 0.12; // Initial utterance onset default
      }

      // ── Forward interval (time until next token) ──
      double deltaNext;
      if (i < count - 1) {
        deltaNext = max(0.04, _filteredSpikeTimes[i + 1] - curSpike);
      } else {
        // Latest token: forward interval not yet followed by a spike.
        // Provide a realistic sustain estimate based on backward pace.
        deltaNext = isElongated ? min(0.30, deltaPrev) : min(0.12, deltaPrev);
      }

      // ── Cap huge inter-verse pauses ──
      final double effectiveDeltaPrev = min(maxTokenDuration, deltaPrev);
      final double effectiveDeltaNext = min(maxTokenDuration, deltaNext);

      double duration;
      if (isElongated) {
        // Prolonged vowel / Ghunnah:
        // Preceding consonant closure lasts ~0.06s.
        // The reciter holds the vowel across both the backward onset and the forward sustain.
        final bool prevIsVowel = (i > 0 && isMaddToken(_filteredTokens[i - 1]));
        final double consonantOffset = prevIsVowel ? 0.0 : 0.06;
        final double backwardVocalic =
            max(0.04, effectiveDeltaPrev - consonantOffset);

        // If followed by another vowel frame (multi-token Madd), split forward interval;
        // otherwise vowel sustains until the next consonant closure.
        final bool nextIsVowel =
            (i < count - 1 && isMaddToken(_filteredTokens[i + 1]));
        final double forwardVocalic =
            nextIsVowel ? (effectiveDeltaNext * 0.5) : effectiveDeltaNext;

        duration = backwardVocalic + forwardVocalic;
      } else {
        // Standard consonant / short syllable:
        // Midpoint boundary partition assigns half the preceding transition
        // and half the succeeding transition to this phoneme.
        duration = (effectiveDeltaPrev + effectiveDeltaNext) * 0.5;
      }

      _tokenDurations.add(duration.clamp(0.04, maxTokenDuration));
    }
  }
}
