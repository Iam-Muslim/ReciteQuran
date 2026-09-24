import 'package:flutter/foundation.dart';

@immutable
class VerseAlignmentException {
  const VerseAlignmentException({
    required this.soraId,
    required this.ayaId,
    required this.dbWordCount,
    required this.artifactWordCount,
    this.dropLeadingDbWords = 0,
    required this.reason,
  });

  final int soraId;
  final int ayaId;
  final int dbWordCount;
  final int artifactWordCount;
  final int dropLeadingDbWords;
  final String reason;
}

/// Known exceptions keyed by riwaya id, mapping "soraId:ayaId" to its exception definition.
const Map<String, Map<String, VerseAlignmentException>> kVerseAlignmentExceptions = {
  'hafs': {
    '9:1': VerseAlignmentException(
      soraId: 9,
      ayaId: 1,
      dbWordCount: 11,
      artifactWordCount: 9,
      dropLeadingDbWords: 2,
      reason: 'Database carries Surah At-Tawbah title prefix before verse text',
    ),
    '15:7': VerseAlignmentException(
      soraId: 15,
      ayaId: 7,
      dbWordCount: 7,
      artifactWordCount: 8,
      reason: 'Database joins لَّوۡمَا where artifact splits لَّوْ مَا',
    ),
    '27:20': VerseAlignmentException(
      soraId: 27,
      ayaId: 20,
      dbWordCount: 11,
      artifactWordCount: 12,
      reason: 'Database joins مَالِيَ where artifact splits مَا لِىَ',
    ),
    '36:22': VerseAlignmentException(
      soraId: 36,
      ayaId: 22,
      dbWordCount: 7,
      artifactWordCount: 8,
      reason: 'Database joins وَمَالِيَ where artifact splits وَمَا لِىَ',
    ),
  },
  'warsh': {},
  'qalun': {},
  'qaloon': {},
};
