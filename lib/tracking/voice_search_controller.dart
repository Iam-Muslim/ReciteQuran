// lib/tracking/voice_search_controller.dart
//
// VoiceSearchController — "Recite to Navigate" feature.
//
// When the user HOLDS the mic button (long-press), this controller takes over
// from the normal HighlightingController. It:
//   1. Resets the ASR buffer
//   2. Starts listening via SherpaEngine
//   3. Accumulates the transcription text
//   4. On release, runs TF-IDF N-gram search across ALL 6,236 Ayahs
//   5. Returns the (surah, ayah) of the best match
//
// first uses this feature. After that, it stays in memory.
//
//
// See also: docs/voice_navigation.md

import 'package:the_great_quran/tracking/quran_normalizer.dart';
import '../engine/sherpa_engine.dart';
import 'matchers/phonetic_search.dart';

class AnchorResult {
  final int surah;
  final int ayah;
  AnchorResult({required this.surah, required this.ayah});

  @override
  String toString() => 'AnchorResult(surah: $surah, ayah: $ayah)';
}

class VoiceSearchController {
  final SherpaEngine engine;

  // The pre-built PhoneticSearch index.
  PhoneticSearch? _search;
  bool _isIndexLoading = false;

  VoiceSearchController({required this.engine});

  // ── Lazy Index Loading ───────────────────────────────────────────────────

  /// Loads the phonetic index from bundled assets the first time it's needed.
  /// Subsequent calls are no-ops (index stays in memory for the session).
  Future<void> _loadIndexIfNeeded() async {
    if (_search != null || _isIndexLoading) return;
    _isIndexLoading = true;
    try {
      print('[VoiceSearch] Loading PhoneticSearch index...');
      _search = PhoneticSearch();
      await _search!.load();
      print('[VoiceSearch] Index loaded. Ready for search.');
    } catch (e) {
      print('[VoiceSearch] ERROR: Failed to load phonetic search assets: $e');
      _search = null;
    } finally {
      _isIndexLoading = false;
    }
  }

  // ── Search Lifecycle ─────────────────────────────────────────────────────

  /// Called when the user starts a long-press.
  /// Pre-loads the index (no-op if already loaded) and resets the ASR buffer
  /// so no old audio bleeds into the search.
  Future<void> startSearch() async {
    await _loadIndexIfNeeded();
    engine.resetBuffer();
  }

  /// Called when the user releases the long-press.
  ///
  /// Takes the raw ASR text accumulated during the press, normalizes it,
  /// and runs fuzzy phonetic search to find the best match.
  ///
  /// Returns the matched [AnchorResult] (surah + ayah), or null if:
  ///   - The index failed to load
  ///   - The input text is empty / too short
  ///   - No Ayah got enough votes
  AnchorResult? stopSearch(String finalAsrText) {
    if (_search == null) {
      print('[VoiceSearch] Search failed: index not loaded.');
      return null;
    }

    // Normalize input text.
    String normText = QuranNormalizer.normalizeWithTashkeel(finalAsrText);
    print('[VoiceSearch] Normalized input: "$normText"');

    // Run PhoneticSearch (allows ~10% error ratio for fuzzy matching)
    final results = _search!.search(normText, errorRatio: 0.1);

    if (results.isEmpty) {
      print('[VoiceSearch] No match found.');
      return null;
    }

    // Sort by distance to get the best match first
    results.sort((a, b) => a.distance.compareTo(b.distance));
    final bestMatch = results.first;

    // Surah and Ayah indices from Python are already 1-based.
    final result = AnchorResult(
      surah: bestMatch.start.surahIdx,
      ayah: bestMatch.start.ayahIdx,
    );

    print('[VoiceSearch] Result: Surah ${result.surah}, Ayah ${result.ayah}');
    return result;
  }
}
