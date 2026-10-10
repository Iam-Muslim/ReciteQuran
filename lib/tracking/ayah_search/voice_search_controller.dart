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
import 'fuzzy_search.dart';
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

  /// 0-indexed word offset within the matched Ayah (midpoint of alignment).
  final int uthmaniWordIdx;

  /// 0-indexed word offset within the matched Ayah where alignment began.
  final int startWordIdx;

  /// 0-indexed word offset within the matched Ayah where alignment ended.
  final int endWordIdx;

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
    this.startWordIdx = 0,
    this.endWordIdx = 0,
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
      'AyahSearchMatch(surah: $surah, ayah: $ayah, score: ${(score * 100).toStringAsFixed(1)}%, dist: $distance, words: $startWordIdx..$endWordIdx)';
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

  /// Whether at least one candidate Ayah was found.
  bool get hasCandidates => candidates.isNotEmpty;

  /// Whether multiple candidates match and none is definitively unique yet.
  bool get isAmbiguous => candidates.length > 1 && !isUnique;

  /// Backward-compatible conversion to [AnchorResult].
  /// If [requireUnique] is true, returns null if [isUnique] is false.
  AnchorResult? toAnchorResult({bool requireUnique = false}) {
    if (topMatch == null) return null;
    if (requireUnique && !isUnique) return null;
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

  /// Resets the current search result and pending queues.
  void clear() {
    currentResult.value = null;
    _queuedText = null;
    _isSearching = false;
  }

  /// Resets the engine audio buffer, clears current candidate results, and ensures the index is ready.
  Future<void> startSearch() async {
    clear();
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

    final normText = PhoneticSearch.normalizeQuery(partialText);
    if (normText.length < minLength) return null;

    if (_isSearching) {
      _queuedText = normText;
      return null;
    }

    _isSearching = true;
    AnchorResult? uniqueAnchor;

    try {
      String textToSearch = normText;

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
  /// If [requireUnique] is true and multiple candidate Ayahs match ([isUnique] is false),
  /// returns null to prevent auto-navigating to an ambiguous verse.
  Future<AnchorResult?> stopSearch(
    String finalAsrText, {
    double errorRatio = 0.22,
    int maxCandidates = 8,
    bool requireUnique = false,
  }) async {
    if (_search == null) {
      DebugLogger.logSimple('VoiceSearch', 'Search failed: index not loaded.');
      return null;
    }

    final normText = PhoneticSearch.normalizeQuery(finalAsrText);
    DebugLogger.log('VoiceSearch', 'Search input: "$normText"');

    if (normText.length < 4) {
      DebugLogger.log('VoiceSearch', 'Search aborted: input too short.');
      currentResult.value = null;
      return null;
    }

    final searchResult = await _executeSearch(
      normText,
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

    if (requireUnique && !searchResult.isUnique) {
      DebugLogger.log(
        'VoiceSearch',
        'Result ambiguous (${searchResult.candidates.length} candidates); auto-anchor suppressed.',
      );
      return null;
    }

    final anchor = searchResult.toAnchorResult();
    DebugLogger.log(
      'VoiceSearch',
      'Result: Surah ${anchor?.surah}, Ayah ${anchor?.ayah} (Candidates: ${searchResult.candidates.length}, isUnique: ${searchResult.isUnique})',
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

  // Normalized Preamble Reference Constants (from detector.py)
  static const String _basmalahPh = 'بسملاهرحمانرحۦم';
  static const String _istiaadhaPh = 'ءعۥذبلاهمنشيطانرجۦم';

  /// Scales error tolerance dynamically with length to prevent short-phrase false matches (from detector.py).
  static double _adaptiveErrorRatio(int qLen, {required double baseRatio}) {
    if (qLen < 16) {
      return 0.15; // Strict: prevents short phrases from falsely matching
    } else if (qLen < 28) {
      return 0.20; // Standard tolerance for medium phrases
    }
    return baseRatio.clamp(0.20, 0.25); // Long recitations: allows up to baseRatio (max 0.25)
  }

  Future<VoiceSearchResult?> _executeSearch(
    String text, {
    required double errorRatio,
    required int maxCandidates,
  }) async {
    final String normText = PhoneticSearch.normalizeQuery(text);
    final int qLen = normText.length;
    if (qLen < 4) return null;

    // 1. Preamble Slicing: If recitation begins with Basmalah or Isti'adha
    // followed by an Ayah (e.g. "بسم الله الرحمن الرحيم قل هو الله أحد"),
    // check if searching the verse text after the preamble yields an exact match.
    String textToSearch = normText;
    if (qLen > 18) {
      final basMatches = findNearMatches(_basmalahPh, normText, 3);
      if (basMatches.isNotEmpty && basMatches.first.start <= 3) {
        final suf = normText.substring(basMatches.first.end).trim();
        if (suf.length >= 6) {
          textToSearch = suf;
        }
      } else {
        final istMatches = findNearMatches(_istiaadhaPh, normText, 4);
        if (istMatches.isNotEmpty && istMatches.first.start <= 3) {
          final suf = normText.substring(istMatches.first.end).trim();
          if (suf.length >= 6) {
            textToSearch = suf;
          }
        }
      }
    }

    final int searchLen = textToSearch.length;
    final double effectiveRatio =
        _adaptiveErrorRatio(searchLen, baseRatio: errorRatio);

    // 2. Primary search over searchInput
    List<PhonemesSearchResult> rawMatches =
        await _search!.searchIsolated(textToSearch, errorRatio: effectiveRatio);

    // 3. Fallback: If stripped text returned nothing, try full normalized input
    if (rawMatches.isEmpty && textToSearch != normText) {
      rawMatches =
          await _search!.searchIsolated(normText, errorRatio: effectiveRatio);
    }

    // 4. Fallback Probe Slicing: If full input fails due to leading noise, hesitation,
    // or coughing, probe trailing suffix slices (from detector.py probe_offsets).
    if (rawMatches.isEmpty && searchLen >= 12) {
      final List<int> probeCuts = [
        (searchLen * 0.25).toInt(),
        (searchLen * 0.45).toInt(),
        (searchLen * 0.65).toInt(),
      ];
      for (final cut in probeCuts) {
        final suffix = textToSearch.substring(cut).trim();
        if (suffix.length >= 8) {
          final double sufRatio =
              _adaptiveErrorRatio(suffix.length, baseRatio: errorRatio);
          final suffixMatches =
              await _search!.searchIsolated(suffix, errorRatio: sufRatio);
          if (suffixMatches.isNotEmpty) {
            rawMatches = suffixMatches;
            break;
          }
        }
      }
    }

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
          (1.0 - (r.distance / max(1, searchLen))).clamp(0.0, 1.0);

      candidates.add(
        AyahSearchMatch(
          surah: s,
          ayah: a,
          score: score,
          distance: r.distance,
          uthmaniWordIdx: r.mid.uthmaniWordIdx,
          startWordIdx: r.start.uthmaniWordIdx,
          endWordIdx: r.end.uthmaniWordIdx,
          surahNameAr: verse?.surahName,
          surahNameEn: verse?.surahNameEn,
          textUthmani: verse?.textUthmani,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    // Uniqueness criteria:
    // If top candidate is an exact match (distance == 0) and the phrase is sufficiently long (>= 20 chars),
    // a distance gap of >= 2 to the runner-up is conclusive evidence of uniqueness.
    final int minGap = (searchLen >= 20) ? 2 : 3;
    bool isUnique = candidates.length == 1 ||
        (candidates.length > 1 &&
            candidates[0].distance == 0 &&
            candidates[1].distance >= minGap);

    // Inter-Surah Basmalah Disambiguation (from detector.py):
    // Surah 1:1 is "بسم الله الرحمن الرحيم", which precedes 113 chapters.
    // If Candidate 0 is 1:1 and other candidates exist, do not declare it unique.
    if (isUnique &&
        candidates.length > 1 &&
        candidates[0].surah == 1 &&
        candidates[0].ayah == 1) {
      isUnique = false;
    }

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
