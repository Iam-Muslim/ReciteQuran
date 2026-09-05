import 'qiraat_ayah_mapper.dart';

export 'qiraat_ayah_mapper.dart';

/// Backwards-compatible facade for Warsh (Madani-last) ayah mapping.
/// Delegates to [QiraatAyahMapper] backed by verified Quranpedia dataset.
class WarshHafsMapper {
  final QiraatAyahMapper _inner;

  WarshHafsMapper._(this._inner);

  /// Creates a Warsh mapper instance from a parsed JSON map.
  factory WarshHafsMapper.fromJson(Map<String, dynamic> json) {
    return WarshHafsMapper._(
      QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.madaniLast),
    );
  }

  /// Loads the bundled Warsh-to-Hafs mapping JSON asset with caching.
  static Future<WarshHafsMapper> loadFromBundle({
    String assetPath = 'assets/json/warsh-to-hafs.json',
  }) async {
    final inner = await QiraatAyahMapper.loadForCountingSystem(
      QuranCountingSystem.madaniLast,
      customAssetPath: assetPath,
    );
    return WarshHafsMapper._(inner);
  }

  /// Returns the corresponding Hafs ayah number(s) for a given Warsh ayah.
  List<int> getHafsAyahs(int surahNumber, int warshAyah) =>
      _inner.getHafsAyahs(surahNumber, warshAyah);

  /// Returns the primary single Hafs ayah number for a given Warsh ayah.
  int getPrimaryHafsAyah(int surahNumber, int warshAyah) =>
      _inner.getPrimaryHafsAyah(surahNumber, warshAyah);

  /// Returns the corresponding Warsh ayah number(s) for a given Hafs ayah.
  List<int> getWarshAyahs(int surahNumber, int hafsAyah) =>
      _inner.getSourceAyahs(surahNumber, hafsAyah);

  /// Returns the mapping status for a Warsh ayah (e.g. 'mapped', 'covers_multiple', 'split').
  String getMappingStatus(int surahNumber, int warshAyah) =>
      _inner.getMappingStatus(surahNumber, warshAyah);

  /// Total ayah count for the surah in Warsh (Madani-last).
  int getWarshAyahCount(int surahNumber) => _inner.getSourceAyahCount(surahNumber);

  /// Total ayah count for the surah in Hafs (Kufi).
  int getHafsAyahCount(int surahNumber) => _inner.getHafsAyahCount(surahNumber);
}
