import 'dart:math';

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
  List<int> prevDist = List.generate(n + 1, (i) => i);
  List<int> prevStart = List.generate(n + 1, (i) => 0); // Start doesn't matter for top row
  
  List<int> currDist = List.filled(n + 1, 0);
  List<int> currStart = List.filled(n + 1, 0);

  for (int j = 1; j <= m; j++) {
    // A match can start anywhere in the text, so cost for prefix 0 is 0.
    // And its start index is j (the current character we are considering to start from)
    currDist[0] = 0;
    currStart[0] = j;

    for (int i = 1; i <= n; i++) {
      int cost = (query[i - 1] == text[j - 1]) ? 0 : 1;
      
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

      if (deleteQueryDist < minDist) {
        minDist = deleteQueryDist;
        bestStart = deleteQueryStart;
      }
      if (insertQueryDist < minDist) {
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
      // The start index is currStart[n] - 1 (since our j is 1-based, currStart[0] = j, which means index j-1).
      int matchStart = currStart[n] - 1;
      int matchEnd = j; // exclusive
      
      // We might have multiple overlapping matches.
      // To mimic fuzzysearch.find_near_matches, we can just yield all local minimums or filter overlaps later.
      // For now, let's just collect all and we can filter overlaps if needed.
      matches.add(FuzzyMatch(start: matchStart, end: matchEnd, dist: currDist[n]));
    }

    // Swap curr and prev
    for (int i = 0; i <= n; i++) {
      prevDist[i] = currDist[i];
      prevStart[i] = currStart[i];
    }
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
