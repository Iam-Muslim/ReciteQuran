/// Shared primitive types used across all features.
///
/// Kept dependency-free so any feature package can import this
/// without pulling in Flutter widgets or heavy dependencies.
library core.types;

import '../data/models/quran_data.dart';

// ---------------------------------------------------------------------------
// Tracker state machine
// ---------------------------------------------------------------------------

/// The two states the live recitation tracker can be in.
///
/// [discovery] — engine is scanning audio looking for a matching verse.
/// [tracking]  — a verse has been identified; engine is now aligning words.
enum TrackerState { discovery, tracking }

// ---------------------------------------------------------------------------
// Verse match result
// ---------------------------------------------------------------------------

/// A matched verse together with its confidence score (0.0 – 1.0).
class VerseMatch {
  /// The matched [QuranVerse].
  final QuranVerse verse;

  /// Levenshtein-ratio similarity between the accumulated phoneme string
  /// and the verse's reference phoneme string.
  final double score;

  VerseMatch({required this.verse, required this.score});

  /// Subscript access for legacy code that treats this as a map.
  dynamic operator [](String key) {
    if (key == 'surah') return verse.surah;
    if (key == 'ayah') return verse.ayah;
    if (key == 'score') return score;
    if (key == 'text' || key == 'text_uthmani') return verse.textUthmani;
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

/// Engine-wide tuning constants.
class TrackerConstants {
  /// Minimum Levenshtein ratio for a verse to be considered a match.
  static const double verseMatchThreshold = 0.70;

  /// How many consecutive low-score cycles before the tracker resets to
  /// [TrackerState.discovery].
  static const int staleCycleLimit = 4;
}
