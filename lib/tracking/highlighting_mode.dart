// lib/tracking/highlighting_mode.dart

enum HighlightingMode {
  /// Option 1: Current index doesn't move unless the exact word is matched.
  /// Skips/lookaheads are disabled. 
  strict,

  /// Option 2: Current index doesn't move unless a word within max lookahead is matched.
  /// If a lookahead word matches, skipped words are marked as wrong/skipped.
  lookahead,
}
