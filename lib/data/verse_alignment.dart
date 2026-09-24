import 'riwaya_descriptor.dart';
import 'verse_key_map.dart';

class VerseAlignment {
  final RiwayaDescriptor riwaya;
  final Map<String, VerseAlignmentException> _exceptions;

  VerseAlignment(this.riwaya)
      : _exceptions = kVerseAlignmentExceptions[riwaya.id] ?? const {};

  /// Artifact key formatted as "surah:ayah".
  String artifactKey(int soraId, int ayaId) => '$soraId:$ayaId';

  /// Maps the database word index to the corresponding index in the artifact phoneme word list.
  int artifactWordIndex(int soraId, int ayaId, int dbWordIndex) {
    final key = artifactKey(soraId, ayaId);
    final exception = _exceptions[key];
    if (exception == null) {
      return dbWordIndex;
    }

    if (exception.dropLeadingDbWords > 0) {
      final adjusted = dbWordIndex - exception.dropLeadingDbWords;
      return adjusted < 0 ? 0 : adjusted;
    }

    return dbWordIndex;
  }

  /// Expected word count in the phoneme artifact given the database word count.
  int expectedArtifactWordCount(int soraId, int ayaId, int dbWordCount) {
    final key = artifactKey(soraId, ayaId);
    final exception = _exceptions[key];
    if (exception != null) {
      return exception.artifactWordCount;
    }
    return dbWordCount;
  }
}
