// lib/tracking/ayah_search/voice_search_controller.dart
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

import '../../engine/sherpa_engine.dart';
import 'phonetic_search.dart';
import '../../utils/debug_logger.dart';

import 'package:flutter/foundation.dart';

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
  
  /// Exposes the loading state for the UI to show a loading indicator.
  final ValueNotifier<bool> isIndexLoading = ValueNotifier(false);
  
  Future<void>? _loadFuture;

  VoiceSearchController({required this.engine});

  // ── Lazy Index Loading ───────────────────────────────────────────────────

  /// Loads the phonetic index from bundled assets the first time it's needed.
  /// Returns immediately if already loaded. If a load is in progress, awaits it.
  Future<void> preloadIndex() {
    if (_search != null) return Future.value();
    if (_loadFuture != null) return _loadFuture!;

    _loadFuture = () async {
      isIndexLoading.value = true;
      try {
        DebugLogger.logSimple('VoiceSearch', 'Loading PhoneticSearch index...');
        final search = PhoneticSearch();
        await search.load();
        _search = search;
        DebugLogger.logSimple('VoiceSearch', 'Index loaded. Ready for search.');
      } catch (e) {
        DebugLogger.logSimple('VoiceSearch', 'ERROR: Failed to load phonetic search assets: $e');
        _search = null;
      } finally {
        isIndexLoading.value = false;
        _loadFuture = null;
      }
    }();
    return _loadFuture!;
  }

  // ── Search Lifecycle ─────────────────────────────────────────────────────

  /// Called when the user starts a long-press.
  /// Pre-loads the index (no-op if already loaded) and resets the ASR buffer
  /// so no old audio bleeds into the search.
  Future<void> startSearch() async {
    await preloadIndex();
    engine.resetBuffer();
  }

  bool _isSearching = false;
  String? _queuedText;

  /// Called continuously as new partial text is streamed from the ASR.
  /// If the engine finds exactly ONE unique Ayah that matches the input,
  /// it returns the [AnchorResult] immediately (bypassing VAD silence wait).
  Future<AnchorResult?> processRealtime(String partialText) async {
    if (_search == null) return null;

    final text = partialText.trim();
    
    // Safety guard: Don't run search on very short strings (e.g. just "بسم")
    // as it will match thousands of verses and is too ambiguous.
    if (text.length < 8) return null;

    if (_isSearching) {
      _queuedText = text;
      return null;
    }
    
    _isSearching = true;
    AnchorResult? finalResult;

    try {
      String textToSearch = text;
      
      while (true) {
        final results = await _search!.searchIsolated(textToSearch, errorRatio: 0.18);
        
        if (results.isNotEmpty) {
          final uniqueAyahs = <String>{};
          for (var r in results) {
            uniqueAyahs.add('${r.mid.surahIdx}-${r.mid.ayahIdx}');
          }

          if (uniqueAyahs.length == 1) {
            // Perfect unique match found!
            results.sort((a, b) => a.distance.compareTo(b.distance));
            final bestMatch = results.first;
            
            DebugLogger.log('VoiceSearch', '⚡ REALTIME UNIQUE MATCH FOUND! Surah ${bestMatch.mid.surahIdx}, Ayah ${bestMatch.mid.ayahIdx}');
            
            finalResult = AnchorResult(
              surah: bestMatch.mid.surahIdx,
              ayah: bestMatch.mid.ayahIdx,
            );
            break;
          }
        }

        // If another update came in while we were searching, process it now
        if (_queuedText != null) {
          textToSearch = _queuedText!;
          _queuedText = null;
        } else {
          break; // No more updates waiting
        }
      }
    } finally {
      _isSearching = false;
    }
    
    return finalResult;
  }

  /// Called when the user releases the long-press, OR when VAD silence is detected.
  ///
  /// Takes the raw ASR text accumulated during the press
  /// and runs fuzzy phonetic search to find the best match.
  ///
  /// Returns the matched [AnchorResult] (surah + ayah), or null if:
  ///   - The index failed to load
  ///   - The input text is empty / too short
  ///   - No Ayah got enough votes
  Future<AnchorResult?> stopSearch(String finalAsrText) async {
    if (_search == null) {
      DebugLogger.logSimple('VoiceSearch', 'Search failed: index not loaded.');
      return null;
    }

    final text = finalAsrText.trim();
    DebugLogger.log('VoiceSearch', 'Search input: "$text"');
    
    // If we're forcing a stop (VAD/button), we still want to guard against completely empty/garbage searches
    if (text.length < 4) {
      DebugLogger.log('VoiceSearch', 'Search aborted: input too short.');
      return null;
    }

    // Run PhoneticSearch (allow ~18% error ratio to account for ASR misrecognitions)
    final results = await _search!.searchIsolated(text, errorRatio: 0.18);

    if (results.isEmpty) {
      DebugLogger.log('VoiceSearch', 'No match found.');
      return null;
    }

    // Sort by distance to get the best match first
    results.sort((a, b) => a.distance.compareTo(b.distance));
    final bestMatch = results.first;

    // Surah and Ayah indices from Python are already 1-based.
    // Using `mid` ensures we don't fall into the previous ayah due to boundary matching jitter.
    final result = AnchorResult(
      surah: bestMatch.mid.surahIdx,
      ayah: bestMatch.mid.ayahIdx,
    );

    DebugLogger.log('VoiceSearch', 'Result: Surah ${result.surah}, Ayah ${result.ayah}');
    return result;
  }
}


