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
/// Uses Gene Myers' 64-bit Bit-Parallel algorithm for queries up to 64 chars,
/// with automatic DP fallback for longer queries.
List<FuzzyMatch> findNearMatches(String query, String text, int maxDist) {
  final int n = query.length;
  final int m = text.length;

  if (n == 0 || m == 0 || maxDist < 0) return const [];

  if (n <= 64) {
    return _bitParallelSearch(query, text, maxDist);
  } else {
    return _dpSearch(query, text, maxDist);
  }
}

/// Myers' 64-bit Bit-Parallel Substring Search.
/// Computes 64 dynamic programming matrix cells per single CPU step.
List<FuzzyMatch> _bitParallelSearch(String query, String text, int maxDist) {
  final int n = query.length;
  final int m = text.length;
  final List<FuzzyMatch> matches = [];

  // Build character pattern bitmasks
  final Map<int, int> charMask = {};
  for (int i = 0; i < n; i++) {
    final int code = query.codeUnitAt(i);
    charMask[code] = (charMask[code] ?? 0) | (1 << i);
  }

  final int fullMask = (1 << n) - 1;
  final int topMask = 1 << (n - 1);

  int vp = fullMask;
  int vn = 0;
  int currDist = n;
  final List<int> textUnits = text.codeUnits;

  for (int j = 0; j < m; j++) {
    final int pm = charMask[textUnits[j]] ?? 0;

    // Step 1: Computing D0
    final int x = pm | vn;
    final int d0 = (((pm & vp) + vp) ^ vp) | x;

    // Step 2: Computing HP and HN
    int hn = vp & d0;
    int hp = vn | (~(vp | d0) & fullMask);

    // Step 3: Check boundary condition
    if ((hp & topMask) != 0) {
      currDist++;
    }
    if ((hn & topMask) != 0) {
      currDist--;
    }

    // Step 4: Advance vectors (for substring search, top boundary delta is 0)
    hp = (hp << 1) & fullMask;
    hn = (hn << 1) & fullMask;
    vp = (hn | (~(d0 | hp) & fullMask)) & fullMask;
    vn = hp & d0;

    if (currDist <= maxDist) {
      final int matchEnd = j + 1;
      final int estimatedStart = (matchEnd - n - currDist).clamp(0, matchEnd);
      matches.add(
        FuzzyMatch(
          start: estimatedStart,
          end: matchEnd,
          dist: currDist,
        ),
      );
    }
  }

  return _filterOverlapping(matches);
}

/// Fallback Dynamic Programming approach for queries longer than 64 phonemes.
List<FuzzyMatch> _dpSearch(String query, String text, int maxDist) {
  final List<FuzzyMatch> matches = [];
  final int n = query.length;
  final int m = text.length;

  Int32List prevDist = Int32List(n + 1);
  Int32List prevStart = Int32List(n + 1);
  Int32List currDist = Int32List(n + 1);
  Int32List currStart = Int32List(n + 1);

  for (int i = 0; i <= n; i++) {
    prevDist[i] = i;
    prevStart[i] = 0;
  }

  final List<int> queryUnits = query.codeUnits;
  final List<int> textUnits = text.codeUnits;

  for (int j = 1; j <= m; j++) {
    currDist[0] = 0;
    currStart[0] = j;

    final int textChar = textUnits[j - 1];

    for (int i = 1; i <= n; i++) {
      final int cost = queryUnits[i - 1] == textChar ? 0 : 1;

      final int replaceDist = prevDist[i - 1] + cost;
      final int replaceStart = prevStart[i - 1];

      final int deleteQueryDist = prevDist[i] + 1;
      final int deleteQueryStart = prevStart[i];

      final int insertQueryDist = currDist[i - 1] + 1;
      final int insertQueryStart = currStart[i - 1];

      int minDist = replaceDist;
      int bestStart = replaceStart;

      if (deleteQueryDist < minDist ||
          (deleteQueryDist == minDist && deleteQueryStart > bestStart)) {
        minDist = deleteQueryDist;
        bestStart = deleteQueryStart;
      }
      if (insertQueryDist < minDist ||
          (insertQueryDist == minDist && insertQueryStart > bestStart)) {
        minDist = insertQueryDist;
        bestStart = insertQueryStart;
      }

      currDist[i] = minDist;
      currStart[i] = bestStart;
    }

    if (currDist[n] <= maxDist) {
      matches.add(
        FuzzyMatch(
          start: currStart[n],
          end: j,
          dist: currDist[n],
        ),
      );
    }

    final Int32List tempDist = prevDist;
    prevDist = currDist;
    currDist = tempDist;

    final Int32List tempStart = prevStart;
    prevStart = currStart;
    currStart = tempStart;
  }

  return _filterOverlapping(matches);
}

List<FuzzyMatch> _filterOverlapping(List<FuzzyMatch> matches) {
  if (matches.isEmpty) return const [];

  matches.sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    if (a.end != b.end) return a.end.compareTo(b.end);
    return a.dist.compareTo(b.dist);
  });

  final List<FuzzyMatch> filtered = [];
  FuzzyMatch current = matches[0];

  for (int i = 1; i < matches.length; i++) {
    final FuzzyMatch next = matches[i];

    if (next.start < current.end) {
      if (next.dist < current.dist) {
        current = next;
      } else if (next.dist == current.dist) {
        final int currentLen = current.end - current.start;
        final int nextLen = next.end - next.start;
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

