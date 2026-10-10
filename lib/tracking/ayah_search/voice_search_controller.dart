// lib/tracking/ayah_search/voice_search_controller.dart
//
// VoiceSearchController — "Recite to Navigate" feature.
//
// Allows users to recite any Ayah or phrase to search across all 6,236 Ayahs.
// Uses Gene Myers' 64-bit Bit-Parallel fuzzy phonetic substring search on
// background isolates, streaming live candidate Ayahs in real time as the reciter
// speaks, and auto-detecting unique verses.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/quran_data.dart';
import '../../engine/sherpa_engine.dart';
import '../../utils/debug_logger.dart';
import 'phonetic_search.dart';

/// Represents a single candidate Ayah match produced by phonetic search.
class AyahSearchMatch {
  /// The 1-indexed Surah (chapter) number.
  final int surah;

  /// The 1-indexed Ayah (verse) number within [surah].
  final int ayah;

  /// Match confidence score from 0.0 (low) to 1.0 (exact phonetic match).
  final double score;

  /// Levenshtein edit distance between the normalized query and reference phonemes.
  final int distance;

  /// 0-indexed word offset within the matched Ayah where alignment began.
  final int uthmaniWordIdx;

  /// Arabic Surah name (e.g. "الفاتحة"), populated if [QuranRepository] was provided.
  final String? surahNameAr;

  /// English transliterated Surah name (e.g. "Al-Fatihah").
  final String? surahNameEn;

  /// Full Arabic Uthmani text of this Ayah, populated if [QuranRepository] was provided.
  final String? textUthmani;

  const AyahSearchMatch({
    required this.surah,
    required this.ayah,
    required this.score,
    required this.distance,
    this.uthmaniWordIdx = 0,
    this.surahNameAr,
    this.surahNameEn,
    this.textUthmani,
  });

  /// Converts this match to a standalone [AnchorResult].
  AnchorResult toAnchorResult() => AnchorResult(
        surah: surah,
        ayah: ayah,
        score: score,
        candidates: [this],
        isUnique: true,
      );

  @override
  String toString() =>
      'AyahSearchMatch(surah: $surah, ayah: $ayah, score: ${(score * 100).toStringAsFixed(1)}%, dist: $distance)';
}

/// Represents the real-time search state containing the current query,
/// all ranked candidate Ayahs, and uniqueness detection.
class VoiceSearchResult {
  /// The transcribed speech string that produced this search result.
  final String queryText;

  /// Ranked list of candidate Ayahs matching the current query (best matches first).
  final List<AyahSearchMatch> candidates;

  /// Whether the search has narrowed down definitively to exactly one target Ayah.
  final bool isUnique;

  /// The top-ranking candidate match, if any.
  final AyahSearchMatch? topMatch;

  const VoiceSearchResult({
    required this.queryText,
    required this.candidates,
    required this.isUnique,
    this.topMatch,
  });

  /// Backward-compatible conversion to [AnchorResult].
  AnchorResult? toAnchorResult() {
    if (topMatch == null) return null;
    return AnchorResult(
      surah: topMatch!.surah,
      ayah: topMatch!.ayah,
      score: topMatch!.score,
      candidates: candidates,
      isUnique: isUnique,
    );
  }

  @override
  String toString() =>
      'VoiceSearchResult(query: "$queryText", candidates: ${candidates.length}, isUnique: $isUnique, top: $topMatch)';
}

/// Primary anchor result model representing the resolved or best-matching Ayah.
class AnchorResult {
  /// The 1-indexed Surah (chapter) number.
  final int surah;

  /// The 1-indexed Ayah (verse) number within [surah].
  final int ayah;

  /// Acoustic phonetic match confidence score (0.0 to 1.0).
  final double score;

  /// All candidate Ayahs evaluated during this search pass.
  final List<AyahSearchMatch> candidates;

  /// Indicates if this match is uniquely distinguished from all other verses.
  final bool isUnique;

  AnchorResult({
    required this.surah,
    required this.ayah,
    this.score = 1.0,
    this.candidates = const [],
    this.isUnique = true,
  });

  @override
  String toString() =>
      'AnchorResult(surah: $surah, ayah: $ayah, candidates: ${candidates.length}, isUnique: $isUnique)';
}

/// Controller managing real-time speech-to-text Quran search and navigation.
class VoiceSearchController {
  final SherpaEngine engine;

  /// Optional Quran repository for enriching candidate Ayahs with Arabic Uthmani text.
  QuranRepository? repository;

  // The pre-built PhoneticSearch index.
  PhoneticSearch? _search;

  /// Exposes the loading state for the UI to show an asset loading indicator.
  final ValueNotifier<bool> isIndexLoading = ValueNotifier(false);

  /// Emits real-time search results (candidates, uniqueness) as new speech is transcribed.
  final StreamController<VoiceSearchResult> _resultsController =
      StreamController<VoiceSearchResult>.broadcast();

  /// Stream of live voice search results containing ranked candidate Ayahs.
  Stream<VoiceSearchResult> get onSearchResult => _resultsController.stream;

  /// ValueNotifier holding the most recent search result for easy UI listening.
  final ValueNotifier<VoiceSearchResult?> currentResult = ValueNotifier(null);

  Future<void>? _loadFuture;
  bool _isSearching = false;
  String? _queuedText;

  VoiceSearchController({
    required this.engine,
    this.repository,
  });

  // ── 1. Lazy Index Loading ──────────────────────────────────────────────────

  /// Loads the 6,236-Ayah phonetic index from bundled assets the first time it's needed.
  /// Returns immediately if already loaded.
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
        DebugLogger.logSimple(
            'VoiceSearch', 'ERROR: Failed to load phonetic search assets: $e');
        _search = null;
      } finally {
        isIndexLoading.value = false;
        _loadFuture = null;
      }
    }();
    return _loadFuture!;
  }

  // ── 2. Search Lifecycle ────────────────────────────────────────────────────

  /// Resets the engine audio buffer, clears current candidate results, and ensures the index is ready.
  Future<void> startSearch() async {
    currentResult.value = null;
    await preloadIndex();
    engine.resetBuffer();
  }

  /// Called continuously as new partial text is streamed from the ASR recognizer.
  ///
  /// - Emits all matching candidates to [onSearchResult] and [currentResult].
  /// - Returns an [AnchorResult] immediately when a unique Ayah is confirmed,
  ///   allowing caller to auto-navigate without waiting for speech silence.
  Future<AnchorResult?> processRealtime(
    String partialText, {
    double errorRatio = 0.20,
    int minLength = 6,
    int maxCandidates = 8,
  }) async {
    if (_search == null) return null;

    final text = partialText.trim();
    if (text.length < minLength) return null;

    if (_isSearching) {
      _queuedText = text;
      return null;
    }

    _isSearching = true;
    AnchorResult? uniqueAnchor;

    try {
      String textToSearch = text;

      while (true) {
        final searchResult = await _executeSearch(
          textToSearch,
          errorRatio: errorRatio,
          maxCandidates: maxCandidates,
        );

        if (searchResult != null) {
          _resultsController.add(searchResult);
          currentResult.value = searchResult;

          if (searchResult.isUnique && searchResult.topMatch != null) {
            DebugLogger.log(
              'VoiceSearch',
              '⚡ REALTIME UNIQUE MATCH: Surah ${searchResult.topMatch!.surah}, Ayah ${searchResult.topMatch!.ayah}',
            );
            uniqueAnchor = searchResult.toAnchorResult();
            break;
          }
        }

        // If another update arrived while searching in background isolate, process latest
        if (_queuedText != null) {
          textToSearch = _queuedText!;
          _queuedText = null;
        } else {
          break;
        }
      }
    } finally {
      _isSearching = false;
    }

    return uniqueAnchor;
  }

  /// Called when the user stops voice search or VAD speech silence is detected.
  ///
  /// Runs final fuzzy phonetic search and returns the best matching [AnchorResult].
  /// The returned result includes all evaluated [AnchorResult.candidates].
  Future<AnchorResult?> stopSearch(
    String finalAsrText, {
    double errorRatio = 0.22,
    int maxCandidates = 8,
  }) async {
    if (_search == null) {
      DebugLogger.logSimple('VoiceSearch', 'Search failed: index not loaded.');
      return null;
    }

    final text = finalAsrText.trim();
    DebugLogger.log('VoiceSearch', 'Search input: "$text"');

    if (text.length < 4) {
      DebugLogger.log('VoiceSearch', 'Search aborted: input too short.');
      currentResult.value = null;
      return null;
    }

    final searchResult = await _executeSearch(
      text,
      errorRatio: errorRatio,
      maxCandidates: maxCandidates,
    );

    if (searchResult == null || searchResult.candidates.isEmpty) {
      DebugLogger.log('VoiceSearch', 'No match found.');
      currentResult.value = null;
      return null;
    }

    _resultsController.add(searchResult);
    currentResult.value = searchResult;

    final anchor = searchResult.toAnchorResult();
    DebugLogger.log(
      'VoiceSearch',
      'Result: Surah ${anchor?.surah}, Ayah ${anchor?.ayah} (Candidates: ${searchResult.candidates.length})',
    );
    return anchor;
  }

  /// Explicit standalone query method returning all ranked candidates.
  Future<VoiceSearchResult?> searchCandidates(
    String query, {
    double errorRatio = 0.22,
    int maxCandidates = 8,
  }) async {
    await preloadIndex();
    if (_search == null) return null;
    return _executeSearch(
      query.trim(),
      errorRatio: errorRatio,
      maxCandidates: maxCandidates,
    );
  }

  // ── 3. Internal Search Execution ──────────────────────────────────────────

  Future<VoiceSearchResult?> _executeSearch(
    String text, {
    required double errorRatio,
    required int maxCandidates,
  }) async {
    final rawMatches =
        await _search!.searchIsolated(text, errorRatio: errorRatio);
    if (rawMatches.isEmpty) return null;

    // Deduplicate matches by (surah, ayah): keep best distance for each distinct verse
    final Map<String, PhonemesSearchResult> bestPerAyah = {};
    for (final r in rawMatches) {
      final key = '${r.mid.surahIdx}:${r.mid.ayahIdx}';
      final existing = bestPerAyah[key];
      if (existing == null || r.distance < existing.distance) {
        bestPerAyah[key] = r;
      }
    }

    // Sort distinct Ayahs by edit distance (ascending)
    final sorted = bestPerAyah.values.toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    final List<AyahSearchMatch> candidates = [];
    for (final r in sorted.take(maxCandidates)) {
      final int s = r.mid.surahIdx;
      final int a = r.mid.ayahIdx;
      final QuranVerse? verse = repository?.getVerse(s, a);

      // Score: 1.0 is exact match, degrades relative to query length
      final double score =
          (1.0 - (r.distance / max(1, text.length))).clamp(0.0, 1.0);

      candidates.add(
        AyahSearchMatch(
          surah: s,
          ayah: a,
          score: score,
          distance: r.distance,
          uthmaniWordIdx: r.mid.uthmaniWordIdx,
          surahNameAr: verse?.surahName,
          surahNameEn: verse?.surahNameEn,
          textUthmani: verse?.textUthmani,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    // Uniqueness criteria:
    // Either exactly 1 candidate exists,
    // OR top candidate has distance 0 (exact match) and runner-up is noticeably further away.
    final bool isUnique = candidates.length == 1 ||
        (candidates.length > 1 &&
            candidates[0].distance == 0 &&
            candidates[1].distance >= 3);

    return VoiceSearchResult(
      queryText: text,
      candidates: candidates,
      isUnique: isUnique,
      topMatch: candidates.first,
    );
  }

  void dispose() {
    _resultsController.close();
    currentResult.dispose();
    isIndexLoading.dispose();
  }
}
