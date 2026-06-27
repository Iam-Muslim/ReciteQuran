import 'dart:typed_data';

class FuzzyMatch {
  final int start;
  final int end;
  final int dist;

  FuzzyMatch({required this.start, required this.end, required this.dist});

  @override
  String toString() => 'FuzzyMatch(start: $start, end: $end, dist: $dist)';
}

/// Finds all occurrences of [query] in [text] with Levenshtein distance <= [maxDist].
/// This uses a dynamic programming approach optimized for substring search.
List<FuzzyMatch> findNearMatches(String query, String text, int maxDist) {
  List<FuzzyMatch> matches = [];
  int n = query.length;
  int m = text.length;

  if (n == 0 || m == 0) return matches;

  // We keep two arrays for DP:
  // prevDist[i] = min distance to match query[0..i] ending at text[j-1]
  // prevStart[i] = start index of that match
  Int32List prevDist = Int32List(n + 1);
  Int32List prevStart = Int32List(n + 1);
  Int32List currDist = Int32List(n + 1);
  Int32List currStart = Int32List(n + 1);

  for (int i = 0; i <= n; i++) {
    prevDist[i] = i;
    prevStart[i] = 0;
  }

  // Cache code units for massive speedup in Dart VM (avoids String indexing overhead in loop)
  final List<int> queryUnits = query.codeUnits;
  final List<int> textUnits = text.codeUnits;

  for (int j = 1; j <= m; j++) {
    // A match can start anywhere in the text, so cost for prefix 0 is 0.
    currDist[0] = 0;
    currStart[0] = j;
    
    final int textChar = textUnits[j - 1];

    for (int i = 1; i <= n; i++) {
      int cost = queryUnits[i - 1] == textChar ? 0 : 1;

      // Option 1: Replace / Match
      int replaceDist = prevDist[i - 1] + cost;
      int replaceStart = prevStart[i - 1];

      // Option 2: Delete from query (Insert in text)
      int deleteQueryDist = prevDist[i] + 1;
      int deleteQueryStart = prevStart[i];

      // Option 3: Insert into query (Delete from text)
      int insertQueryDist = currDist[i - 1] + 1;
      int insertQueryStart = currStart[i - 1];

      int minDist = replaceDist;
      int bestStart = replaceStart;

      if (deleteQueryDist < minDist || (deleteQueryDist == minDist && deleteQueryStart > bestStart)) {
        minDist = deleteQueryDist;
        bestStart = deleteQueryStart;
      }
      if (insertQueryDist < minDist || (insertQueryDist == minDist && insertQueryStart > bestStart)) {
        minDist = insertQueryDist;
        bestStart = insertQueryStart;
      }

      // If distances are equal, we prefer the one that starts LATER (shorter match)
      // Actually, python's fuzzysearch might have its own preferences, but this is usually fine.
      currDist[i] = minDist;
      currStart[i] = bestStart;
    }

    if (currDist[n] <= maxDist) {
      // Found a match ending at j.
      // The start index is currStart[n].
      int matchStart = currStart[n];
      int matchEnd = j; // exclusive

      // We might have multiple overlapping matches.
      // To mimic fuzzysearch.find_near_matches, we can just yield all local minimums or filter overlaps later.
      // For now, let's just collect all and we can filter overlaps if needed.
      matches.add(
        FuzzyMatch(start: matchStart, end: matchEnd, dist: currDist[n]),
      );
    }

    // Swap curr and prev in O(1) time
    Int32List tempDist = prevDist;
    prevDist = currDist;
    currDist = tempDist;

    Int32List tempStart = prevStart;
    prevStart = currStart;
    currStart = tempStart;
  }

  return _filterOverlapping(matches);
}

List<FuzzyMatch> _filterOverlapping(List<FuzzyMatch> matches) {
  if (matches.isEmpty) return [];

  // Sort by start index, then by end index, then by distance
  matches.sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    if (a.end != b.end) return a.end.compareTo(b.end);
    return a.dist.compareTo(b.dist);
  });

  List<FuzzyMatch> filtered = [];
  FuzzyMatch current = matches[0];

  for (int i = 1; i < matches.length; i++) {
    FuzzyMatch next = matches[i];

    // Two matches overlap if one starts before the other ends.
    // We want to keep the one with the smallest distance.
    if (next.start < current.end) {
      if (next.dist < current.dist) {
        current = next;
      } else if (next.dist == current.dist) {
        // If distances are equal, prefer the one that is shorter
        int currentLen = current.end - current.start;
        int nextLen = next.end - next.start;
        if (nextLen < currentLen) {
          current = next;
        }
      }
    } else {
      filtered.add(current);
      current = next;
    }
  }
  filtered.add(current);
  return filtered;
}
