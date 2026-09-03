import 'dart:convert';
import 'package:flutter/services.dart';

/// Supported canonical Quranic counting systems (مذاهب العدّ الستة المعتمدة).
enum QuranCountingSystem {
  kufi('kufi', 'الكوفي', 6236),
  madaniLast('madani-last', 'المدني الأخير', 6214),
  madaniFirst('madani-first', 'المدني الأول', 6214),
  makki('makki', 'المكي', 6219),
  basri('basri', 'البصري', 6204),
  dimashqi('dimashqi', 'الدمشقي', 6226);

  final String id;
  final String arabicName;
  final int totalAyahs;

  const QuranCountingSystem(this.id, this.arabicName, this.totalAyahs);

  static QuranCountingSystem fromId(String id) {
    final clean = id.toLowerCase().replaceAll('_', '-').trim();
    return QuranCountingSystem.values.firstWhere(
      (s) => s.id == clean,
      orElse: () => QuranCountingSystem.kufi,
    );
  }

  /// Maps any canonical Rawi or Qira'a name to its corresponding counting tradition.
  static QuranCountingSystem fromRawiOrQiraa(String rawiOrQiraa) {
    final clean = rawiOrQiraa.toLowerCase().replaceAll('_', '-').trim();
    switch (clean) {
      // 1. Nafi' -> Madani Last
      case 'warsh':
      case 'qalun':
      case 'nafi':
      case 'nafi-warsh':
      case 'nafi-qalun':
        return QuranCountingSystem.madaniLast;

      // 2. Abu Ja'far -> Madani First
      case 'ibn-wardan':
      case 'wardan':
      case 'ibn-jammaz':
      case 'jammaz':
      case 'abu-jafar':
        return QuranCountingSystem.madaniFirst;

      // 3. Ibn Kathir -> Makki
      case 'bazzi':
      case 'al-bazzi':
      case 'qunbul':
      case 'ibn-kathir':
        return QuranCountingSystem.makki;

      // 4. Abu 'Amr & Ya'qub -> Basri
      case 'duri':
      case 'al-duri':
      case 'susi':
      case 'al-susi':
      case 'abu-amr':
      case 'ruways':
      case 'rawh':
      case 'yaqub':
        return QuranCountingSystem.basri;

      // 5. Ibn 'Amir -> Damascene / Shami
      case 'hisham':
      case 'ibn-dhakwan':
      case 'dhakwan':
      case 'ibn-amir':
        return QuranCountingSystem.dimashqi;

      // 6. Asim, Hamza, Kisai, Khalaf -> Kufi (Default reference)
      case 'hafs':
      case 'shuba':
      case 'asim':
      case 'khalaf':
      case 'khallad':
      case 'hamza':
      case 'abu-al-harith':
      case 'duri-kisai':
      case 'kisai':
      case 'ishaq':
      case 'idris':
      default:
        return QuranCountingSystem.kufi;
    }
  }
}

/// Bidirectional cross-riwaya ayah mapper linking any counting madhhab to Kufi (Hafs).
/// Sourced from Quranpedia (موسوعة القرآن): https://github.com/quranpedia/qiraat-ayah-map
class QiraatAyahMapper {
  final QuranCountingSystem system;
  final Map<String, dynamic>? _data;
  final Map<int, Map<int, List<int>>> _sourceToHafs = {};
  final Map<int, Map<int, List<int>>> _hafsToSource = {};
  final Map<int, Map<int, String>> _statusMap = {};
  final Map<int, int> _sourceCounts = {};
  final Map<int, int> _hafsCounts = {};

  static final Map<QuranCountingSystem, QiraatAyahMapper> _cache = {};

  QiraatAyahMapper._(this.system, [this._data]) {
    if (_data != null) {
      _init();
    }
  }

  void _init() {
    final surahs = _data?['surahs'] as Map<String, dynamic>? ?? {};
    for (final entry in surahs.entries) {
      final surahNum = int.tryParse(entry.key);
      if (surahNum == null) continue;

      final surahData = entry.value as Map<String, dynamic>;
      _sourceCounts[surahNum] = surahData['source_ayah_count'] as int? ?? 0;
      _hafsCounts[surahNum] = surahData['hafs_ayah_count'] as int? ?? 0;

      _sourceToHafs[surahNum] = {};
      _hafsToSource[surahNum] = {};
      _statusMap[surahNum] = {};

      final ayahs = surahData['ayahs'] as Map<String, dynamic>? ?? {};
      for (final ayahEntry in ayahs.entries) {
        final srcAyah = int.tryParse(ayahEntry.key);
        if (srcAyah == null) continue;

        final ayahData = ayahEntry.value as Map<String, dynamic>;
        final status = ayahData['status'] as String? ?? 'mapped';
        _statusMap[surahNum]![srcAyah] = status;

        List<int> hafsList = [];
        if (ayahData.containsKey('hafs_ayahs')) {
          hafsList = List<int>.from(ayahData['hafs_ayahs']);
        } else if (ayahData.containsKey('hafs_ayah')) {
          hafsList = [ayahData['hafs_ayah'] as int];
        }

        _sourceToHafs[surahNum]![srcAyah] = hafsList;

        for (final h in hafsList) {
          _hafsToSource[surahNum]!.putIfAbsent(h, () => []).add(srcAyah);
        }
      }
    }
  }

  /// Factory for creating an identity mapper (e.g. for Hafs, Shu'ba, and Kufan recitations).
  factory QiraatAyahMapper.kufiIdentity() {
    return _cache.putIfAbsent(
      QuranCountingSystem.kufi,
      () => QiraatAyahMapper._(QuranCountingSystem.kufi),
    );
  }

  /// Creates a mapper from a parsed JSON map for a specific counting system.
  factory QiraatAyahMapper.fromJson(
    Map<String, dynamic> json, {
    QuranCountingSystem? system,
  }) {
    final detectedSystem = system ??
        QuranCountingSystem.fromId(json['_source'] as String? ?? 'madani-last');
    return QiraatAyahMapper._(detectedSystem, json);
  }

  /// Loads the mapping table for a given counting system from bundled assets with caching.
  static Future<QiraatAyahMapper> loadForCountingSystem(
    QuranCountingSystem system, {
    String? customAssetPath,
  }) async {
    if (system == QuranCountingSystem.kufi) {
      return QiraatAyahMapper.kufiIdentity();
    }

    if (_cache.containsKey(system) && customAssetPath == null) {
      return _cache[system]!;
    }

    final filename = '${system.id}-to-kufi.json';
    final assetPath = customAssetPath ?? 'assets/json/$filename';

    String jsonString;
    try {
      jsonString = await rootBundle.loadString('packages/recite_quran/$assetPath');
    } catch (_) {
      try {
        jsonString = await rootBundle.loadString(assetPath);
      } catch (_) {
        if (system == QuranCountingSystem.madaniLast) {
          jsonString = await rootBundle.loadString('packages/recite_quran/assets/json/warsh-to-hafs.json');
        } else {
          rethrow;
        }
      }
    }

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final mapper = QiraatAyahMapper.fromJson(json, system: system);
    if (customAssetPath == null) {
      _cache[system] = mapper;
    }
    return mapper;
  }

  /// Automatically resolves the correct counting system and loads the mapping table for any Rawi.
  static Future<QiraatAyahMapper> loadForRawi(String rawiOrQiraa) async {
    final system = QuranCountingSystem.fromRawiOrQiraa(rawiOrQiraa);
    return loadForCountingSystem(system);
  }

  /// Returns corresponding Hafs ayah number(s) for a given source ayah in the active counting tradition.
  List<int> getHafsAyahs(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return [sourceAyah];
    return _sourceToHafs[surahNumber]?[sourceAyah] ?? [sourceAyah];
  }

  /// Returns the primary single Hafs ayah number for a given source ayah.
  int getPrimaryHafsAyah(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return sourceAyah;
    final list = _sourceToHafs[surahNumber]?[sourceAyah];
    return (list != null && list.isNotEmpty) ? list.first : sourceAyah;
  }

  /// Returns corresponding source ayah number(s) in the active counting tradition for a given Hafs ayah.
  List<int> getSourceAyahs(int surahNumber, int hafsAyah) {
    if (system == QuranCountingSystem.kufi) return [hafsAyah];
    return _hafsToSource[surahNumber]?[hafsAyah] ?? [hafsAyah];
  }

  /// Returns mapping status (e.g. 'mapped', 'covers_multiple', 'split').
  String getMappingStatus(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return 'mapped';
    return _statusMap[surahNumber]?[sourceAyah] ?? 'mapped';
  }

  /// Total ayah count for the surah in the source counting system.
  int getSourceAyahCount(int surahNumber) {
    if (system == QuranCountingSystem.kufi) return _hafsCounts[surahNumber] ?? 0;
    return _sourceCounts[surahNumber] ?? 0;
  }

  /// Total ayah count for the surah in Hafs (Kufi).
  int getHafsAyahCount(int surahNumber) => _hafsCounts[surahNumber] ?? 0;
}
