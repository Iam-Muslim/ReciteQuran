// lib/tracking/matchers/anchor.dart

import 'dart:math';

class NgramIndex {
  final int ngramSize;
  final Map<String, List<AyahLocation>> ngramPositions;
  final Map<String, int> ngramCounts;

  NgramIndex({
    required this.ngramSize,
    required this.ngramPositions,
    required this.ngramCounts,
  });

  factory NgramIndex.fromJson(Map<String, dynamic> json) {
    final int size = json['ngramSize'] as int;
    final Map<String, int> counts = Map<String, int>.from(json['ngramCounts'] as Map);
    
    final Map<String, List<AyahLocation>> positions = {};
    final rawPositions = json['ngramPositions'] as Map<String, dynamic>;
    
    rawPositions.forEach((ngram, locs) {
      final List<dynamic> locList = locs as List<dynamic>;
      positions[ngram] = locList.map((l) {
        return AyahLocation(l['s'] as int, l['a'] as int);
      }).toList();
    });

    return NgramIndex(
      ngramSize: size,
      ngramPositions: positions,
      ngramCounts: counts,
    );
  }
}

class AyahLocation {
  final int surah;
  final int ayah;

  AyahLocation(this.surah, this.ayah);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AyahLocation &&
          runtimeType == other.runtimeType &&
          surah == other.surah &&
          ayah == other.ayah;

  @override
  int get hashCode => surah.hashCode ^ ayah.hashCode;
}

class AnchorResult {
  final int surah;
  final int ayah;

  AnchorResult(this.surah, this.ayah);
}

class Anchor {
  static AnchorResult findAnchorByVoting({
    required List<List<String>> phonemeTexts,
    required NgramIndex ngramIndex,
    int segments = 10,
    bool rarityWeighting = true,
    int topCandidates = 3,
    double runTrimRatio = 0.1,
  }) {
    List<String> combined = [];
    for (int i = 0; i < min(segments, phonemeTexts.length); i++) {
      if (phonemeTexts[i].isNotEmpty) {
        combined.addAll(phonemeTexts[i]);
      }
    }

    int n = ngramIndex.ngramSize;
    if (combined.length < n) return AnchorResult(0, 0);

    List<String> asrNgrams = [];
    for (int i = 0; i <= combined.length - n; i++) {
      asrNgrams.add(combined.sublist(i, i + n).join('|'));
    }

    Map<AyahLocation, double> votes = {};
    for (String ng in asrNgrams) {
      if (!ngramIndex.ngramPositions.containsKey(ng)) continue;

      double weight = 1.0;
      if (rarityWeighting) {
        weight = 1.0 / (ngramIndex.ngramCounts[ng] ?? 1);
      }

      for (var loc in ngramIndex.ngramPositions[ng]!) {
        votes[loc] = (votes[loc] ?? 0.0) + weight;
      }
    }

    if (votes.isEmpty) return AnchorResult(0, 0);

    Map<int, Map<int, double>> surahAyahVotes = {};
    votes.forEach((loc, w) {
      surahAyahVotes.putIfAbsent(loc.surah, () => {});
      surahAyahVotes[loc.surah]![loc.ayah] = w;
    });

    int bestSurah = 0;
    int bestRunStart = 0;
    double bestRunWeight = -1.0;

    surahAyahVotes.forEach((s, ayahWeights) {
      var runResult = _findBestContiguousRun(ayahWeights, runTrimRatio);
      if (runResult.weight > bestRunWeight) {
        bestRunWeight = runResult.weight;
        bestSurah = s;
        bestRunStart = runResult.start;
      }
    });

    return AnchorResult(bestSurah, bestRunStart);
  }

  static RunResult _findBestContiguousRun(Map<int, double> ayahWeights, double runTrimRatio) {
    if (ayahWeights.isEmpty) return RunResult(0, 0, 0.0);

    var sortedAyahs = ayahWeights.keys.toList()..sort();
    
    List<RunResult> runs = [];
    int runStart = sortedAyahs[0];
    int runEnd = sortedAyahs[0];
    double runWeight = ayahWeights[sortedAyahs[0]]!;

    for (int i = 1; i < sortedAyahs.length; i++) {
      int ayah = sortedAyahs[i];
      if (ayah == runEnd + 1) {
        runEnd = ayah;
        runWeight += ayahWeights[ayah]!;
      } else {
        runs.add(RunResult(runStart, runEnd, runWeight));
        runStart = ayah;
        runEnd = ayah;
        runWeight = ayahWeights[ayah]!;
      }
    }
    runs.add(RunResult(runStart, runEnd, runWeight));

    var bestRun = runs.reduce((a, b) => a.weight > b.weight ? a : b);
    
    int bestStart = bestRun.start;
    int bestEnd = bestRun.end;
    double bestWeight = bestRun.weight;

    double maxW = 0;
    for (int a = bestStart; a <= bestEnd; a++) {
      if ((ayahWeights[a] ?? 0) > maxW) maxW = ayahWeights[a]!;
    }
    
    double threshold = runTrimRatio * maxW;

    while (bestStart < bestEnd && (ayahWeights[bestStart] ?? 0) < threshold) {
      bestWeight -= ayahWeights[bestStart]!;
      bestStart++;
    }

    while (bestEnd > bestStart && (ayahWeights[bestEnd] ?? 0) < threshold) {
      bestWeight -= ayahWeights[bestEnd]!;
      bestEnd--;
    }

    return RunResult(bestStart, bestEnd, bestWeight);
  }
}

class RunResult {
  final int start;
  final int end;
  final double weight;

  RunResult(this.start, this.end, this.weight);
}
