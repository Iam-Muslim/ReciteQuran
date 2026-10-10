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
  final List<double> starts;
  final List<double> ends;
  final List<double> spikeTimes;

  ProcessedAudioStream({
    required this.tokens,
    required this.durations,
    this.starts = const [],
    this.ends = const [],
    this.spikeTimes = const [],
  });

  bool get isEmpty => tokens.isEmpty;
  bool get isNotEmpty => tokens.isNotEmpty;

  /// Returns the continuous phoneme text without CTC blanks.
  String get text => tokens.join('');

  /// Maps every character in [text] to its source token index in [tokens].
  List<int> get charTokenIndices {
    final List<int> result = [];
    for (int i = 0; i < tokens.length; i++) {
      final int len = tokens[i].length;
      for (int c = 0; c < len; c++) {
        result.add(i);
      }
    }
    return result;
  }

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
  final List<double> _tokenStarts = [];
  final List<double> _tokenEnds = [];

  void reset() {
    _lastRawTokens.clear();
    _filteredTokens.clear();
    _filteredSpikeTimes.clear();
    _tokenDurations.clear();
    _tokenStarts.clear();
    _tokenEnds.clear();
  }

  /// Determines if a token is a prolonged vocalic Madd sound (ا, آ, و, ي, ى, ۥ, ۦ, ٰ, ٱ, ٲ).
  static bool isMaddToken(String tok) {
    if (tok.isEmpty) return false;
    // Any token carrying an active vowel or consonant mark (Fathah, Dammah, Kasrah, Tanween, Sukoon, Shaddah)
    // is an articulated consonant syllable, NOT a pure unvoweled Madd vowel.
    for (int i = 0; i < tok.length; i++) {
      final int c = tok.codeUnitAt(i);
      if (c >= 0x064B && c <= 0x0652) { // ً ٌ ٍ َ ُ ِ ّ ْ
        return false;
      }
    }
    // Shaddah doubled consonants (e.g. ييَ, ووَ) without Madd markings are not Madd.
    if (isShaddahToken(tok) || isGhunnahToken(tok)) {
      return false;
    }
    for (int i = 0; i < tok.length; i++) {
      final int c = tok.codeUnitAt(i);
      if (c == 0x0627 || // ا
          c == 0x0622 || // آ
          c == 0x0648 || // و
          c == 0x064A || // ي
          c == 0x0649 || // ى
          c == 0x0670 || // ٰ
          c == 0x0671 || // ٱ
          c == 0x06E5 || // ۥ
          c == 0x06E6 || // ۦ
          c == 0x0672) { // ٲ
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

  /// Determines if a token represents an acoustic Shaddah (doubled consonant).
  static bool isShaddahToken(String tok) {
    if (tok.length < 2) return false;
    final int c0 = tok.codeUnitAt(0);
    final int c1 = tok.codeUnitAt(1);
    if (c0 != c1) return false;
    // Cannot be Alif (اا is Madd)
    if (c0 == 0x0627) return false;
    // Bare unvoweled وو or يي (length 2 without harakah) could be Madd.
    // But if it has harakah (e.g. ييَ as in "إياك", or ووَ as in "توابا"), it is 100% Shaddah!
    if ((c0 == 0x0648 || c0 == 0x064A) && tok.length == 2) {
      return false;
    }
    return c0 >= 0x0621 && c0 <= 0x064A;
  }

  /// Identifies sounds that can absorb acoustic prolongation (Madd vowels, Shaddah gemination, Ghunnah).
  static bool isElasticContinuant(String tok) {
    return isMaddToken(tok) || isShaddahToken(tok) || isGhunnahToken(tok);
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

    final bool hasNewTokens = commonLen < maxCount;

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

    // Debug prints:
    if (hasNewTokens && _filteredTokens.isNotEmpty) {
      final int startPrint = max(0, _filteredTokens.length - (maxCount - commonLen + 1));
      for (int i = startPrint; i < _filteredTokens.length; i++) {
        // ignore: avoid_print
        print(
          '⏱️ [SHERPA TOKEN] #$i "${_filteredTokens[i]}" | Pure Sherpa Ts: ${_filteredSpikeTimes[i].toStringAsFixed(3)}s | Grading Dur: ${_tokenDurations[i].toStringAsFixed(3)}s [start: ${_tokenStarts[i].toStringAsFixed(3)}s -> end: ${_tokenEnds[i].toStringAsFixed(3)}s]',
        );
      }
    }

    return ProcessedAudioStream(
      tokens: _filteredTokens,
      durations: _tokenDurations,
      starts: _tokenStarts,
      ends: _tokenEnds,
      spikeTimes: _filteredSpikeTimes,
    );
  }

  /// Recomputes acoustic durations using one proven fact from aligner ground truth:
  ///
  /// **The Sherpa CTC peak timestamp marks the END of the token's acoustic presence.**
  ///
  /// Therefore:
  ///   end[k]      = peak[k]
  ///   start[k]    = peak[k-1]  (= end[k-1], contiguous)
  ///   duration[k] = peak[k] - peak[k-1]
  ///
  /// After an inter-ayah pause (silence gap), start[k] is decoupled from the
  /// previous token and estimated from the current peak.
  void _recomputeDurations() {
    final int count = _filteredTokens.length;
    _tokenDurations.clear();
    _tokenStarts.clear();
    _tokenEnds.clear();
    if (count == 0) return;

    final List<double> starts = List.filled(count, 0.0);
    final List<double> ends = List.filled(count, 0.0);
    final List<double> durs = List.filled(count, 0.0);

    for (int k = 0; k < count; k++) {
      final double peak = _filteredSpikeTimes[k];

      // The CTC peak IS the end boundary of token k.
      ends[k] = peak;

      if (k == 0) {
        // First token: no previous peak. Estimate start from peak minus a small window.
        starts[k] = max(0.0, peak - 0.16);
      } else {
        final double peakPrev = _filteredSpikeTimes[k - 1];
        final double gap = peak - peakPrev;

        // Accurate acoustic pause detection:
        // Prolonged vocalic sounds (Madd vowels) naturally span up to 3.5s without pausing.
        // Geminated consonants (Shaddah) or nasal holds (Ghunnah) span up to 0.90s.
        // Letters following a prolonged Madd or Waqf letter span up to 1.30s.
        // A true inter-ayah breath pause is a substantial silence gap (> 1.25s).
        final double pauseThreshold;
        if (isMaddToken(_filteredTokens[k])) {
          pauseThreshold = 3.50;
        } else if (isShaddahToken(_filteredTokens[k]) ||
            isGhunnahToken(_filteredTokens[k])) {
          pauseThreshold = 0.90;
        } else if (isMaddToken(_filteredTokens[k - 1]) ||
            _filteredTokens[k - 1].length >= 2) {
          pauseThreshold = 1.30;
        } else {
          pauseThreshold = 1.25;
        }

        if (gap > pauseThreshold) {
          // After a genuine breath pause: start is decoupled. Estimate onset before peak.
          starts[k] = max(peakPrev + 0.04, peak - 0.16);
        } else {
          // Continuous articulation: start[k] = end[k-1] = peak[k-1]
          starts[k] = peakPrev;
        }
      }

      // Duration = end - start
      durs[k] = max(0.04, ends[k] - starts[k]);
    }

    _tokenStarts.addAll(starts);
    _tokenEnds.addAll(ends);
    _tokenDurations.addAll(durs);
  }
}
