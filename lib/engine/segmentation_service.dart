library engine.segmentation_service;

import 'sherpa_engine.dart';
import '../utils/normalizer.dart';

class PhonemeWord {
  final String text;
  final double startTime;
  final double endTime;

  const PhonemeWord({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  @override
  String toString() =>
      '$text (${startTime.toStringAsFixed(2)} → ${endTime.toStringAsFixed(2)} s)';
}

class SegmentationService {
  List<PhonemeWord> groupPhonemesToWords(TranscriptionResult result) {
    if (result.text.isEmpty) return [];

    final String text = Normalizer.normalizeArabic(result.text);
    // Since we normalized the text (e.g., collapsed multiple spaces), the original
    // sherpa timestamps may be slightly misaligned if spaces were removed.
    // However, since we just need the start/end time of each word, we can approximate
    // or map the timestamps linearly. For exactness, we apply spaces to mark word boundaries.
    final List<double> timestamps = result.timestamps;

    final List<PhonemeWord> words = [];
    final StringBuffer currentWord = StringBuffer();
    double? wordStart;
    double? wordEnd;

    int charPos = 0;
    int tokenIdx = 0;

    // Normalizing may change length, but let's map directly to sherpa tokens if we assume 1:1 roughly
    // Actually, Sherpa output text matches timestamps list closely, but space is a token too.
    while (charPos < result.text.length) {
      final String token = result.text.substring(charPos, charPos + 1);
      charPos += 1;

      final double time = tokenIdx < timestamps.length
          ? timestamps[tokenIdx]
          : 0.0;
      tokenIdx++;

      if (token == ' ') {
        if (currentWord.isNotEmpty) {
          words.add(
            PhonemeWord(
              text: Normalizer.normalizeArabic(currentWord.toString()),
              startTime: wordStart ?? time,
              endTime: wordEnd ?? time,
            ),
          );
          currentWord.clear();
          wordStart = null;
          wordEnd = null;
        }
      } else {
        if (currentWord.isEmpty) wordStart = time;
        currentWord.write(token);
        wordEnd = time;
      }
    }

    if (currentWord.isNotEmpty) {
      words.add(
        PhonemeWord(
          text: Normalizer.normalizeArabic(currentWord.toString()),
          startTime: wordStart ?? 0.0,
          endTime: wordEnd ?? 0.0,
        ),
      );
    }

    // Filter out completely empty words due to normalization
    return words.where((w) => w.text.isNotEmpty).toList();
  }

  List<String> parseWords(String text) {
    return groupPhonemesToWords(
      TranscriptionResult(text: text, timestamps: []),
    ).map((w) => w.text).toList();
  }
}
