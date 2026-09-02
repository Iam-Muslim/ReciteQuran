import 'dart:convert';
import 'package:flutter/services.dart';

/// Service for mapping and aligning verse boundaries between Warsh (Madani-last)
/// and Hafs (Kufi) numbering systems.
class WarshHafsMapper {
  final Map<String, dynamic> _data;
  final Map<int, Map<int, List<int>>> _warshToHafs = {};
  final Map<int, Map<int, List<int>>> _hafsToWarsh = {};
  final Map<int, Map<int, String>> _statusMap = {};
  final Map<int, int> _warshCounts = {};
  final Map<int, int> _hafsCounts = {};

  WarshHafsMapper._(this._data) {
    _init();
  }

  void _init() {
    final surahs = _data['surahs'] as Map<String, dynamic>? ?? {};
    for (final entry in surahs.entries) {
      final surahNum = int.tryParse(entry.key);
      if (surahNum == null) continue;

      final surahData = entry.value as Map<String, dynamic>;
      _warshCounts[surahNum] = surahData['source_ayah_count'] as int? ?? 0;
      _hafsCounts[surahNum] = surahData['hafs_ayah_count'] as int? ?? 0;

      _warshToHafs[surahNum] = {};
      _hafsToWarsh[surahNum] = {};
      _statusMap[surahNum] = {};

      final ayahs = surahData['ayahs'] as Map<String, dynamic>? ?? {};
      for (final ayahEntry in ayahs.entries) {
        final warshAyah = int.tryParse(ayahEntry.key);
        if (warshAyah == null) continue;

        final ayahData = ayahEntry.value as Map<String, dynamic>;
        final status = ayahData['status'] as String? ?? 'mapped';
        _statusMap[surahNum]![warshAyah] = status;

        List<int> hafsList = [];
        if (ayahData.containsKey('hafs_ayahs')) {
          hafsList = List<int>.from(ayahData['hafs_ayahs']);
        } else if (ayahData.containsKey('hafs_ayah')) {
          hafsList = [ayahData['hafs_ayah'] as int];
        }

        _warshToHafs[surahNum]![warshAyah] = hafsList;

        for (final h in hafsList) {
          _hafsToWarsh[surahNum]!.putIfAbsent(h, () => []).add(warshAyah);
        }
      }
    }
  }

  /// Creates a mapper instance from a parsed JSON map.
  factory WarshHafsMapper.fromJson(Map<String, dynamic> json) {
    return WarshHafsMapper._(json);
  }

  static WarshHafsMapper? _cachedInstance;

  /// Loads the bundled Warsh-to-Hafs mapping JSON asset.
  /// Subsequent calls return the cached in-memory instance to avoid re-parsing JSON.
  static Future<WarshHafsMapper> loadFromBundle({
    String assetPath = 'assets/json/warsh-to-hafs.json',
  }) async {
    if (_cachedInstance != null) {
      return _cachedInstance!;
    }
    String jsonString;
    try {
      jsonString = await rootBundle.loadString('packages/recite_quran/$assetPath');
    } catch (_) {
      jsonString = await rootBundle.loadString(assetPath);
    }
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    _cachedInstance = WarshHafsMapper._(json);
    return _cachedInstance!;
  }

  /// Returns the corresponding Hafs ayah number(s) for a given Warsh ayah.
  List<int> getHafsAyahs(int surahNumber, int warshAyah) {
    return _warshToHafs[surahNumber]?[warshAyah] ?? [warshAyah];
  }

  /// Returns the primary single Hafs ayah number for a given Warsh ayah.
  int getPrimaryHafsAyah(int surahNumber, int warshAyah) {
    final list = _warshToHafs[surahNumber]?[warshAyah];
    return (list != null && list.isNotEmpty) ? list.first : warshAyah;
  }

  /// Returns the corresponding Warsh ayah number(s) for a given Hafs ayah.
  List<int> getWarshAyahs(int surahNumber, int hafsAyah) {
    return _hafsToWarsh[surahNumber]?[hafsAyah] ?? [hafsAyah];
  }

  /// Returns the mapping status for a Warsh ayah (e.g. 'mapped', 'covers_multiple', 'split').
  String getMappingStatus(int surahNumber, int warshAyah) {
    return _statusMap[surahNumber]?[warshAyah] ?? 'mapped';
  }

  /// Total ayah count for the surah in Warsh (Madani-last).
  int getWarshAyahCount(int surahNumber) => _warshCounts[surahNumber] ?? 0;

  /// Total ayah count for the surah in Hafs (Kufi).
  int getHafsAyahCount(int surahNumber) => _hafsCounts[surahNumber] ?? 0;
}
