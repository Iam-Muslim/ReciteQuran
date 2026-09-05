import 'dart:convert';
import 'package:flutter/services.dart';

/// Supported canonical Quranic verse-numbering traditions (مدارس عد الآي).
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

  static String _normalizeRawiKey(String rawiOrQiraa) {
    var s = rawiOrQiraa.toLowerCase().replaceAll('_', '-').replaceAll('\'', '').trim();
    // Remove Arabic diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalize Alefs
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    // Remove Tatweel
    s = s.replaceAll('ـ', '');
    return s;
  }

  /// Maps any canonical Rawi or Qira'a name (in English or Arabic) to its corresponding counting tradition.
  static QuranCountingSystem fromRawiOrQiraa(String rawiOrQiraa) {
    final clean = _normalizeRawiKey(rawiOrQiraa);
    switch (clean) {
      // 1. Nafi' (Warsh & Qaloon) -> Madani Last
      case 'warsh':
      case 'qalun':
      case 'qaloon':
      case 'nafi':
      case 'nafi-warsh':
      case 'nafi-qalun':
      case 'nafi-qaloon':
      case 'warsh-an-nafi':
      case 'qalun-an-nafi':
      case 'qaloon-an-nafi':
      case 'ورش':
      case 'قالون':
      case 'نافع':
      case 'ورش عن نافع':
      case 'قالون عن نافع':
        return QuranCountingSystem.madaniLast;

      // 2. Abu Ja'far (Ibn Wardan & Ibn Jammaz) -> Madani First
      case 'ibn-wardan':
      case 'wardan':
      case 'ibn-jammaz':
      case 'jammaz':
      case 'abu-jafar':
      case 'abu-jaafar':
      case 'ابن وردان':
      case 'وردان':
      case 'ابن جماز':
      case 'جماز':
      case 'ابو جعفر':
        return QuranCountingSystem.madaniFirst;

      // 3. Ibn Kathir (Al-Bazzi & Qunbul) -> Makki
      case 'bazzi':
      case 'al-bazzi':
      case 'qunbul':
      case 'ibn-kathir':
      case 'kathir':
      case 'البزي':
      case 'بزي':
      case 'قنبل':
      case 'ابن كثير':
        return QuranCountingSystem.makki;

      // 4. Abu 'Amr & Ya'qub (Al-Duri, Al-Susi, Ruways, Rawh) -> Basri
      case 'duri':
      case 'al-duri':
      case 'duri-abu-amr':
      case 'susi':
      case 'al-susi':
      case 'susi-abu-amr':
      case 'abu-amr':
      case 'ruways':
      case 'rawh':
      case 'yaqub':
      case 'yaqub-al-hadrami':
      case 'الدوري':
      case 'الدوري عن ابي عمرو':
      case 'السوسي':
      case 'السوسي عن ابي عمرو':
      case 'ابو عمرو':
      case 'رويس':
      case 'روح':
      case 'يعقوب':
      case 'يعقوب الحضرمي':
        return QuranCountingSystem.basri;

      // 5. Ibn 'Amir (Hisham & Ibn Dhakwan) -> Damascene / Shami
      case 'hisham':
      case 'ibn-dhakwan':
      case 'dhakwan':
      case 'ibn-amir':
      case 'shami':
      case 'damascene':
      case 'هشام':
      case 'ابن ذكوان':
      case 'ذكوان':
      case 'ابن عامر':
        return QuranCountingSystem.dimashqi;

      // 6. Asim, Hamza, Kisai, Khalaf -> Kufi (Default reference)
      case 'hafs':
      case 'hafs-an-asim':
      case 'shuba':
      case 'asim':
      case 'khalaf':
      case 'khallad':
      case 'hamza':
      case 'abu-al-harith':
      case 'duri-kisai':
      case 'kisai':
      case 'al-kisai':
      case 'ishaq':
      case 'idris':
      case 'حفص':
      case 'حفص عن عاصم':
      case 'شعبة':
      case 'شعبة عن عاصم':
      case 'عاصم':
      case 'خلف':
      case 'خلاد':
      case 'حمزة':
      case 'ابو الحارث':
      case 'الدوري عن الكسائي':
      case 'الكسائي':
      case 'اسحاق':
      case 'ادريس':
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
  final Map<int, Map<int, Map<String, dynamic>>> _sourceAyahData = {};
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
      _sourceAyahData[surahNum] = {};

      final ayahs = surahData['ayahs'] as Map<String, dynamic>? ?? {};
      for (final ayahEntry in ayahs.entries) {
        final srcAyah = int.tryParse(ayahEntry.key);
        if (srcAyah == null) continue;

        final ayahData = ayahEntry.value as Map<String, dynamic>;
        _sourceAyahData[surahNum]![srcAyah] = ayahData;
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
          try {
            jsonString = await rootBundle.loadString('packages/recite_quran/assets/json/warsh-to-hafs.json');
          } catch (_) {
            jsonString = await rootBundle.loadString('assets/json/warsh-to-hafs.json');
          }
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

  /// Returns raw metadata map for a specific source ayah if present.
  Map<String, dynamic>? getAyahMetadata(int surahNumber, int sourceAyah) {
    return _sourceAyahData[surahNumber]?[sourceAyah];
  }
}
