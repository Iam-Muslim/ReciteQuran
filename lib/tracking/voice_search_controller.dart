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
// The N-gram index (ngram_index.json) is loaded LAZILY — only when the user
// first uses this feature. After that, it stays in memory.
//
// This system is a Dart port of the Anchor/NgramIndex from:
//   qua_sdk/components/anchor_matcher/
//
// See also: docs/voice_navigation.md

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:the_great_quran/tracking/quran_normalizer.dart';
import '../engine/sherpa_engine.dart';
import 'matchers/anchor.dart';
import 'matchers/phoneme_chunker.dart';

class VoiceSearchController {
  final SherpaEngine engine;

  // The pre-built N-gram TF-IDF index (loaded once from ngram_index.json).
  NgramIndex? _index;
  bool _isIndexLoading = false;

  VoiceSearchController({required this.engine});

  // ── Lazy Index Loading ───────────────────────────────────────────────────

  /// Loads the N-gram index from bundled JSON the first time it's needed.
  /// Subsequent calls are no-ops (index stays in memory for the session).
  Future<void> _loadIndexIfNeeded() async {
    if (_index != null || _isIndexLoading) return;
    _isIndexLoading = true;
    try {
      print('[VoiceSearch] Loading ngram_index.json...');
      final String jsonStr = await rootBundle.loadString('assets/model/ngram_index.json');
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      _index = NgramIndex.fromJson(data);
      print('[VoiceSearch] Index loaded. Ready for search.');
    } catch (e) {
      print('[VoiceSearch] ERROR: Failed to load ngram_index.json: $e');
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
  /// chunks it into phoneme groups, and runs TF-IDF N-gram voting.
  ///
  /// Returns the matched [AnchorResult] (surah + ayah), or null if:
  ///   - The index failed to load
  ///   - The input text is empty / too short
  ///   - No Ayah got enough votes
  AnchorResult? stopSearch(String finalAsrText) {
    if (_index == null) {
      print('[VoiceSearch] Search failed: index not loaded.');
      return null;
    }

    // Normalize: strip harakat, normalize alef variants → bare consonant skeleton
    final normText = QuranNormalizer.normalizeBare(finalAsrText);
    print('[VoiceSearch] Normalized input: "$normText"');

    // Chunk into phoneme groups (consonant + optional harakat)
    final chunks = PhonemeChunker.chunkPhonemes(normText);
    print('[VoiceSearch] Phoneme chunks: $chunks');

    if (chunks.isEmpty) {
      print('[VoiceSearch] No phoneme chunks found. Returning null.');
      return null;
    }

    // Run TF-IDF N-gram voting across all 6,236 Ayahs
    final result = Anchor.findAnchorByVoting(
      phonemeTexts: [chunks],
      ngramIndex: _index!,
    );

    print('[VoiceSearch] Result: Surah ${result.surah}, Ayah ${result.ayah}');

    // Filter out zero-results (0:0 means no match found)
    if (result.surah == 0 || result.ayah == 0) {
      print('[VoiceSearch] No match found (0:0 returned).');
      return null;
    }

    return result;
  }
}
