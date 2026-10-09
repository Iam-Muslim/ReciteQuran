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
    return c0 == c1 &&
        c0 >= 0x0621 &&
        c0 <= 0x064A &&
        c0 != 0x0627 && // not alif
        c0 != 0x0648 && // not waw
        c0 != 0x064A;   // not yaa
  }

  /// Determines if a token is any held or elongated acoustic sound (Madd, Ghunnah, or Shaddah).
  static bool isElongatedToken(String tok) {
    return isMaddToken(tok) || isGhunnahToken(tok) || isShaddahToken(tok);
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
      starts: _tokenStarts,
      ends: _tokenEnds,
      spikeTimes: _filteredSpikeTimes,
    );
  }

  /// Recomputes acoustic durations for all tokens in `_filteredTokens` using
  /// an explicit contiguous acoustic boundary partition (derived from Tajweed sonorant physics).
  ///
  /// Guarantees:
  /// 1. start_k = end_{k-1} (strictly contiguous in speech, zero lost milliseconds).
  /// 2. Consonants before Madd end at their physical release (~0.05-0.06s),
  ///    transferring the remaining vocalic onset into the Madd.
  /// 3. Shaddah consonants receive their physical closure interval (the hold prior
  ///    to release burst) instead of being cut in half by midpoint crossover.
  /// 4. Madd vowels sustain continuously until the succeeding consonant closure (~0.05s).
  /// 5. Pauses/breaths (> 0.60s) decouple the boundary so inter-verse silence
  ///    does not artificially inflate token durations.
  void _recomputeDurations() {
    final int count = _filteredTokens.length;
    _tokenDurations.clear();
    _tokenStarts.clear();
    _tokenEnds.clear();
    if (count == 0) return;

    if (count == 1) {
      final bool isElongated = isElongatedToken(_filteredTokens[0]);
      final double dur = isElongated ? 0.30 : 0.12;
      _tokenDurations.add(dur);
      _tokenStarts.add(_filteredSpikeTimes[0] - (isElongated ? 0.15 : 0.06));
      _tokenEnds.add(_filteredSpikeTimes[0] + (isElongated ? 0.15 : 0.06));
      return;
    }

    // Token start and end boundaries
    final List<double> starts = List.filled(count, 0.0);
    final List<double> ends = List.filled(count, 0.0);

    // Initial token onset: starts ~80-120ms before peak
    final double firstStep = _filteredSpikeTimes[1] - _filteredSpikeTimes[0];
    final bool isFirstElongated = isElongatedToken(_filteredTokens[0]);
    starts[0] = max(
      0.0,
      _filteredSpikeTimes[0] -
          (isFirstElongated ? min(0.20, max(0.08, firstStep * 0.50)) : min(0.10, max(0.04, firstStep * 0.35))),
    );

    for (int k = 1; k < count; k++) {
      final double tPrev = _filteredSpikeTimes[k - 1];
      final double tCurr = _filteredSpikeTimes[k];
      final double step = max(0.04, tCurr - tPrev);

      final String prevTok = _filteredTokens[k - 1];
      final String currTok = _filteredTokens[k];

      final bool isPrevSonorant = isMaddToken(prevTok) || isGhunnahToken(prevTok);
      final bool isCurrSonorant = isMaddToken(currTok) || isGhunnahToken(currTok);

      final bool isPrevShaddah = isShaddahToken(prevTok);
      final bool isCurrShaddah = isShaddahToken(currTok);

      final bool isPrevElongated = isPrevSonorant || isPrevShaddah;
      final bool isCurrElongated = isCurrSonorant || isCurrShaddah;

      // Check for inter-verse silence / breathing pause.
      final double pauseThreshold =
          (isPrevElongated || isCurrElongated) ? 1.50 : 0.90;
      final bool isPause = step > pauseThreshold;

      if (isPause) {
        // Discontinuous pause: token k-1 releases, token k onsets after breath
        ends[k - 1] =
            tPrev + (isPrevElongated ? min(0.60, maxTokenDuration) : 0.10);
        starts[k] = max(ends[k - 1], tCurr - (isCurrElongated ? 0.30 : 0.10));
      } else {
        // Continuous speech: strictly contiguous (ends[k-1] == starts[k] == boundary)
        double boundary;

        if (isPrevSonorant && isCurrShaddah) {
          // Madd/Ghunnah -> Shaddah: e.g. الضَّآلِّينَ (Madd into Shaddah للِ).
          // Shaddah geminate closure must be preserved (~150-180ms before burst spike).
          boundary = max(tPrev + 0.15, tCurr - min(0.18, step * 0.50));
        } else if (isPrevShaddah && isCurrSonorant) {
          // Shaddah -> Madd/Ghunnah: e.g. إِيَّاكَ (Shaddah into Madd اا).
          // Shaddah releases and transfers into the vowel onset (~70-80ms).
          boundary = tPrev + min(0.08, step * 0.35);
        } else if (isPrevShaddah && !isCurrSonorant) {
          // Shaddah -> Normal Consonant: e.g. رَبِّكَ (Shaddah into كَ).
          // Shaddah burst & vowel sustain until ~50ms before next consonant closure.
          boundary = tCurr - min(0.05, step * 0.25);
        } else if (!isPrevSonorant && isCurrShaddah) {
          // Normal Consonant/Vowel -> Shaddah: e.g. رَبِّ (رَ into Shaddah ببِ).
          // Preceding short vowel releases quickly (~50ms); Shaddah gets the closure phase up to tCurr!
          boundary = tPrev + min(0.06, step * 0.25);
        } else if (!isPrevSonorant && isCurrSonorant) {
          // Normal Consonant -> Madd: consonant ends at physical release (~50-60ms).
          boundary = tPrev + min(0.06, step * 0.25);
        } else if (isPrevSonorant && !isCurrSonorant) {
          // Madd -> Normal Consonant: Madd sustains continuously until consonant closure (~50ms before peak).
          boundary = tCurr - min(0.05, step * 0.25);
        } else if (step > 0.16) {
          // Normal Consonant -> Normal Consonant with elongated gap:
          // A pre-spike acoustic closure (possible single-spike Shaddah uttered in audio).
          // Preceding short vowel ends at ~50-60ms; succeeding consonant gets the closure hold!
          boundary = tPrev + min(0.06, step * 0.25);
        } else {
          // Standard short consonant-to-consonant midpoint crossover
          boundary = (tPrev + tCurr) * 0.5;
        }

        // Safety clamp: boundary must strictly lie between the two peaks
        final double lowerBound = min(tPrev, tCurr);
        final double upperBound = max(tPrev, tCurr);
        if (upperBound > lowerBound + 0.02) {
          boundary = boundary.clamp(lowerBound + 0.01, upperBound - 0.01);
        } else {
          boundary = (lowerBound + upperBound) * 0.5;
        }

        ends[k - 1] = boundary;
        starts[k] = boundary;
      }
    }

    // Final token offset
    final double lastStep = count > 1
        ? _filteredSpikeTimes[count - 1] - _filteredSpikeTimes[count - 2]
        : 0.20;
    final bool isLastElongated = isElongatedToken(_filteredTokens[count - 1]);
    ends[count - 1] = _filteredSpikeTimes[count - 1] +
        (isLastElongated ? min(0.60, max(0.18, lastStep * 0.6)) : 0.10);

    // Compute durations
    for (int i = 0; i < count; i++) {
      final double dur = ends[i] - starts[i];
      _tokenDurations.add(dur.clamp(0.04, maxTokenDuration));
      _tokenStarts.add(starts[i]);
      _tokenEnds.add(ends[i]);
    }
  }
}
