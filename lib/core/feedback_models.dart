enum WordStatus { correct, mispronounced, missed, extra, skipped, pending }

class WordFeedback {
  final int wordIndex;
  final WordStatus status;
  final double accuracy;

  final String expected;
  final String actual;

  WordFeedback({
    required this.wordIndex,
    required this.status,
    required this.accuracy,
    required this.expected,
    required this.actual,
  });
}

class SessionFeedback {
  final List<WordFeedback> words;
  final double overallScore;

  SessionFeedback({required this.words, required this.overallScore});
}
