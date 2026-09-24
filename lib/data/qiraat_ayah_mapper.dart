import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ayah_mapping_downloader.dart';

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

  /// Resolves counting system from identifier string with fallback to Kufi.
  static QuranCountingSystem fromId(String id) {
    final clean = id.toLowerCase().replaceAll('_', '-').trim();
    for (final s in QuranCountingSystem.values) {
      if (s.id == clean) return s;
    }
    return QuranCountingSystem.kufi;
  }

  /// Resolves counting system directly from a strongly-typed [QuranRiwayah].
  static QuranCountingSystem fromRiwayah(QuranRiwayah riwayah) => riwayah.countingSystem;

  /// Resolves counting system from a [QuranRawi].
  static QuranCountingSystem fromRawi(QuranRiwayah rawi) => rawi.countingSystem;

  /// Resolves counting system directly from a strongly-typed [QuranQiraa].
  static QuranCountingSystem fromQiraa(QuranQiraa qiraa) => qiraa.countingSystem;

  /// Universal lookup accepting [QuranRiwayah], [QuranQiraa], [QuranCountingSystem], or string.
  static QuranCountingSystem fromRawiOrQiraa(dynamic input) {
    if (input is QuranRiwayah) return input.countingSystem;
    if (input is QuranQiraa) return input.countingSystem;
    if (input is QuranCountingSystem) return input;
    return QuranRiwayah.parse(input.toString()).countingSystem;
  }
}

/// Canonical 10 Qira'at (الأئمة العشرة القراء) with their counting tradition.
enum QuranQiraa {
  nafi('nafi', 'نافع المدني', 'Nafi al-Madani', QuranCountingSystem.madaniLast),
  ibnKathir('ibn-kathir', 'ابن كثير المكي', 'Ibn Kathir al-Makki', QuranCountingSystem.makki),
  abuAmr('abu-amr', 'أبو عمرو البصري', 'Abu Amr al-Basri', QuranCountingSystem.basri),
  ibnAmir('ibn-amir', 'ابن عامر الشامي', 'Ibn Amir ad-Dimashqi', QuranCountingSystem.dimashqi),
  asim('asim', 'عاصم الكوفي', 'Asim al-Kufi', QuranCountingSystem.kufi),
  hamza('hamza', 'حمزة الكوفي', 'Hamza al-Kufi', QuranCountingSystem.kufi),
  kisai('kisai', 'الكسائي الكوفي', 'Al-Kisai al-Kufi', QuranCountingSystem.kufi),
  abuJafar('abu-jafar', 'أبو جعفر المدني', 'Abu Ja\'far al-Madani', QuranCountingSystem.madaniFirst),
  yaqub('yaqub', 'يعقوب الحضرمي البصري', 'Ya\'qub al-Hadrami al-Basri', QuranCountingSystem.basri),
  khalafAlAshir('khalaf-al-ashir', 'خلف العاشر الكوفي', 'Khalaf al-Ashir al-Kufi', QuranCountingSystem.kufi);

  final String id;
  final String nameAr;
  final String nameEn;
  final QuranCountingSystem countingSystem;

  const QuranQiraa(this.id, this.nameAr, this.nameEn, this.countingSystem);
}

/// Canonical 20 Riwayat (الروايات العشرون) of the 10 Mutawatir Qira'at.
enum QuranRiwayah {
  // ── 1. Nafi' (Madani Last) ──
  qaloon('qaloon', 'قالون', 'Qaloon', QuranQiraa.nafi, aliases: ['qalun', 'qaloon-an-nafi', 'قالون عن نافع']),
  warsh('warsh', 'ورش', 'Warsh', QuranQiraa.nafi, aliases: ['warsh-an-nafi', 'ورش عن نافع', 'nafi', 'نافع']),

  // ── 2. Ibn Kathir (Makki) ──
  bazzi('bazzi', 'البزي', 'Al-Bazzi', QuranQiraa.ibnKathir, aliases: ['al-bazzi', 'البزي عن ابن كثير']),
  qunbul('qunbul', 'قنبل', 'Qunbul', QuranQiraa.ibnKathir, aliases: ['قنبل عن ابن كثير']),

  // ── 3. Abu 'Amr (Basri) ──
  duri('duri', 'الدوري', 'Al-Duri', QuranQiraa.abuAmr, aliases: ['al-duri', 'duri-abu-amr', 'الدوري عن أبي عمرو']),
  susi('susi', 'السوسي', 'Al-Susi', QuranQiraa.abuAmr, aliases: ['al-susi', 'susi-abu-amr', 'السوسي عن أبي عمرو']),

  // ── 4. Ibn 'Amir (Dimashqi) ──
  hisham('hisham', 'هشام', 'Hisham', QuranQiraa.ibnAmir, aliases: ['هشام عن ابن عامر']),
  ibnDhakwan('ibn-dhakwan', 'ابن ذكوان', 'Ibn Dhakwan', QuranQiraa.ibnAmir, aliases: ['dhakwan', 'ibn_dhakwan', 'ابن ذكوان عن ابن عامر']),

  // ── 5. 'Asim (Kufi) ──
  shubah('shubah', 'شعبة', 'Shu\'bah', QuranQiraa.asim, aliases: ['shuba', 'شعبة عن عاصم']),
  hafs('hafs', 'حفص', 'Hafs', QuranQiraa.asim, aliases: ['hafs-an-asim', 'حفص عن عاصم', 'asim', 'عاصم']),

  // ── 6. Hamza (Kufi) ──
  khalaf('khalaf', 'خلف', 'Khalaf', QuranQiraa.hamza, aliases: ['خلف عن حمزة']),
  khallad('khallad', 'خلاد', 'Khallad', QuranQiraa.hamza, aliases: ['خلاد عن حمزة']),

  // ── 7. Al-Kisa'i (Kufi) ──
  abuAlHarith('abu-al-harith', 'أبو الحارث', 'Abu al-Harith', QuranQiraa.kisai, aliases: ['abu-harith', 'أبو الحارث عن الكسائي']),
  duriKisai('duri-kisai', 'الدوري عن الكسائي', 'Al-Duri (al-Kisai)', QuranQiraa.kisai, aliases: ['الدوري عن الكسائي']),

  // ── 8. Abu Ja'far (Madani First) ──
  ibnWardan('ibn-wardan', 'ابن وردان', 'Ibn Wardan', QuranQiraa.abuJafar, aliases: ['wardan', 'ibn_wardan', 'ابن وردان عن أبي جعفر']),
  ibnJammaz('ibn-jammaz', 'ابن جماز', 'Ibn Jammaz', QuranQiraa.abuJafar, aliases: ['jammaz', 'ibn_jammaz', 'ابن جماز عن أبي جعفر']),

  // ── 9. Ya'qub (Basri) ──
  ruways('ruways', 'رويس', 'Ruways', QuranQiraa.yaqub, aliases: ['رويس عن يعقوب']),
  rawh('rawh', 'روح', 'Rawh', QuranQiraa.yaqub, aliases: ['روح عن يعقوب']),

  // ── 10. Khalaf al-'Ashir (Kufi) ──
  ishaq('ishaq', 'إسحاق', 'Ishaq', QuranQiraa.khalafAlAshir, aliases: ['إسحاق عن خلف العاشر']),
  idris('idris', 'إدريس', 'Idris', QuranQiraa.khalafAlAshir, aliases: ['إدريس عن خلف العاشر']);

  final String id;
  final String nameAr;
  final String nameEn;
  final QuranQiraa qiraa;
  final List<String> aliases;

  const QuranRiwayah(
    this.id,
    this.nameAr,
    this.nameEn,
    this.qiraa, {
    this.aliases = const [],
  });

  /// The verse counting tradition is inherited directly from the Imam's Qira'a tradition.
  QuranCountingSystem get countingSystem => qiraa.countingSystem;

  static final Map<String, QuranRiwayah> _lookupIndex = _buildLookupIndex();

  static Map<String, QuranRiwayah> _buildLookupIndex() {
    final map = <String, QuranRiwayah>{};
    for (final riwayah in QuranRiwayah.values) {
      map[_normalize(riwayah.id)] = riwayah;
      map[_normalize(riwayah.name)] = riwayah;
      map[_normalize(riwayah.nameEn)] = riwayah;
      map[_normalize(riwayah.nameAr)] = riwayah;
      for (final alias in riwayah.aliases) {
        map[_normalize(alias)] = riwayah;
      }
    }
    // Also index Imam names to resolve to their primary riwayah
    for (final qiraa in QuranQiraa.values) {
      final defaultRiwayah = QuranRiwayah.values.firstWhere((r) => r.qiraa == qiraa);
      map.putIfAbsent(_normalize(qiraa.id), () => defaultRiwayah);
      map.putIfAbsent(_normalize(qiraa.nameAr), () => defaultRiwayah);
      map.putIfAbsent(_normalize(qiraa.nameEn), () => defaultRiwayah);
      final firstArWord = qiraa.nameAr.split(' ').first;
      map.putIfAbsent(_normalize(firstArWord), () => defaultRiwayah);
      final firstEnWord = qiraa.nameEn.split(' ').first;
      map.putIfAbsent(_normalize(firstEnWord), () => defaultRiwayah);
    }
    return Map.unmodifiable(map);
  }

  /// Resolves a [QuranRiwayah] by its exact identifier or alias, with optional fallback.
  static QuranRiwayah fromId(String id, {QuranRiwayah fallback = QuranRiwayah.hafs}) {
    return tryFromId(id) ?? fallback;
  }

  /// Resolves a [QuranRiwayah] by its exact identifier or alias, returning null if not found.
  static QuranRiwayah? tryFromId(String id) {
    final clean = _normalize(id);
    return _lookupIndex[clean];
  }

  /// Parses any string (Arabic/English name, alias, or Imam name) into a [QuranRiwayah] in O(1) time.
  static QuranRiwayah parse(String input, {QuranRiwayah fallback = QuranRiwayah.hafs}) {
    return tryParse(input) ?? fallback;
  }

  /// Parses any string into a [QuranRiwayah], returning null if unrecognized.
  static QuranRiwayah? tryParse(String input) {
    final clean = _normalize(input);
    if (clean.isEmpty) return null;
    return _lookupIndex[clean];
  }

  static String _normalize(String input) {
    var s = input.toLowerCase().replaceAll('_', '-').replaceAll("'", '').trim();
    // Remove Arabic diacritics
    s = s.replaceAll(RegExp(r'[ً-ٰٟ]'), '');
    // Normalize Alefs
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    // Remove Tatweel
    s = s.replaceAll('ـ', '');
    return s;
  }
}

/// Backward-compatible alias for [QuranRiwayah].
typedef QuranRawi = QuranRiwayah;

/// Bidirectional cross-riwaya ayah mapper linking any Riwayah to Hafs (Kufi reference).
/// Sourced from official verified ayah mappings: https://github.com/M97Chahboun/quran-database-verifier
class QiraatAyahMapper {
  final QuranRiwayah riwayah;
  final Map<String, dynamic>? _data;
  final Map<int, Map<int, List<int>>> _sourceToHafs = {};
  final Map<int, Map<int, List<int>>> _hafsToSource = {};
  final Map<int, Map<int, Map<String, dynamic>>> _sourceAyahData = {};
  final Map<int, Map<int, String>> _statusMap = {};
  final Map<int, int> _sourceCounts = {};
  final Map<int, int> _hafsCounts = {};

  QuranCountingSystem get system => riwayah.countingSystem;

  static final Map<QuranRiwayah, QiraatAyahMapper> _cache = {};

  QiraatAyahMapper._(this.riwayah, [this._data]) {
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
  factory QiraatAyahMapper.kufiIdentity([QuranRiwayah riwayah = QuranRiwayah.hafs]) {
    return _cache.putIfAbsent(
      riwayah,
      () => QiraatAyahMapper._(riwayah),
    );
  }

  /// Creates a mapper from a parsed JSON map for a specific Riwayah or counting system.
  factory QiraatAyahMapper.fromJson(
    Map<String, dynamic> json, {
    QuranRiwayah? riwayah,
    QuranCountingSystem? system,
  }) {
    QuranRiwayah resolvedRiwayah;
    if (riwayah != null) {
      resolvedRiwayah = riwayah;
    } else {
      final rawiStr = json['_rawi'] as String? ?? json['source_riwaya'] as String?;
      if (rawiStr != null) {
        resolvedRiwayah = QuranRiwayah.parse(rawiStr);
      } else {
        final sysStr = json['_source'] as String? ?? 'madani-last';
        final sys = system ?? QuranCountingSystem.fromId(sysStr);
        resolvedRiwayah = QuranRiwayah.values.firstWhere(
          (r) => r.countingSystem == sys,
          orElse: () => QuranRiwayah.warsh,
        );
      }
    }
    return QiraatAyahMapper._(resolvedRiwayah, json);
  }

  /// Primary loader: loads the mapping table for a given Riwayah (enum, id, or name).
  static Future<QiraatAyahMapper> load(
    dynamic riwayah, {
    String? customAssetPath,
    String? customStoragePath,
    bool downloadIfMissing = true,
  }) =>
      loadForRiwayah(
        riwayah,
        customAssetPath: customAssetPath,
        customStoragePath: customStoragePath,
        downloadIfMissing: downloadIfMissing,
      );

  /// Loads the mapping table for a strongly-typed [QuranRiwayah] enum, id, or name.
  /// Priority:
  /// 1. Kufi identity (immediate 1:1, no file or network needed)
  /// 2. In-memory cache
  /// 3. Local disk storage (e.g. downloaded to documents directory)
  /// 4. Bundled Flutter assets (if packaged in app)
  /// 5. On-demand network download from official release (if enabled)
  static Future<QiraatAyahMapper> loadForRiwayah(
    dynamic riwayah, {
    String? customAssetPath,
    String? customStoragePath,
    bool downloadIfMissing = true,
  }) async {
    final QuranRiwayah target;
    if (riwayah is QuranRiwayah) {
      target = riwayah;
    } else {
      target = QuranRiwayah.parse(riwayah.toString());
    }

    // 1. Hafs, Shu'bah, and Kufi recitations use standard 1:1 Kufi ayah numbering (6,236 ayahs)
    if (target.countingSystem == QuranCountingSystem.kufi) {
      return QiraatAyahMapper.kufiIdentity(target);
    }

    // 2. In-memory cache
    if (_cache.containsKey(target) && customAssetPath == null) {
      return _cache[target]!;
    }

    final filename = '${target.id}-to-hafs.json';

    // 3. Try custom file / local documents directory on disk
    try {
      final downloader = AyahMappingDownloader(customStoragePath: customStoragePath);
      final localFile = await downloader.getMappingFile(target);
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final mapper = QiraatAyahMapper.fromJson(json, riwayah: target);
        if (customAssetPath == null) _cache[target] = mapper;
        return mapper;
      }

      // Also check app-level documents/mappings folder if present
      final appDir = await getApplicationDocumentsDirectory();
      final altFile = File(p.join(appDir.path, 'mappings', filename));
      if (await altFile.exists()) {
        final content = await altFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final mapper = QiraatAyahMapper.fromJson(json, riwayah: target);
        if (customAssetPath == null) _cache[target] = mapper;
        return mapper;
      }
    } catch (_) {}

    // 4. Try bundled assets (package assets or app assets)
    final assetPath = customAssetPath ?? 'assets/json/$filename';
    String? jsonString;
    try {
      jsonString = await rootBundle.loadString('packages/recite_quran/$assetPath');
    } catch (_) {
      try {
        jsonString = await rootBundle.loadString(assetPath);
      } catch (_) {
        if (target == QuranRiwayah.qaloon) {
          try {
            jsonString = await rootBundle.loadString('packages/recite_quran/assets/json/qalun-to-hafs.json');
          } catch (_) {
            try {
              jsonString = await rootBundle.loadString('assets/json/qalun-to-hafs.json');
            } catch (_) {}
          }
        } else if (target == QuranRiwayah.warsh) {
          try {
            jsonString = await rootBundle.loadString('packages/recite_quran/assets/json/warsh-to-hafs.json');
          } catch (_) {
            try {
              jsonString = await rootBundle.loadString('assets/json/warsh-to-hafs.json');
            } catch (_) {}
          }
        }
      }
    }

    if (jsonString != null) {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: target);
      if (customAssetPath == null) _cache[target] = mapper;
      return mapper;
    }

    // 5. On-demand download from official release if missing
    if (downloadIfMissing && !kIsWeb) {
      try {
        final downloader = AyahMappingDownloader(customStoragePath: customStoragePath);
        final downloadedFile = await downloader.downloadMapping(target);
        if (downloadedFile != null && await downloadedFile.exists()) {
          final content = await downloadedFile.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final mapper = QiraatAyahMapper.fromJson(json, riwayah: target);
          if (customAssetPath == null) _cache[target] = mapper;
          return mapper;
        }
      } catch (_) {}
    }

    throw StateError(
      'Ayah mapping for ${target.id} is not found locally or in bundled assets, and on-demand download could not be completed.',
    );
  }

  /// Backward-compatible loader for [QuranRawi].
  static Future<QiraatAyahMapper> loadForRawi(dynamic rawiOrQiraa) =>
      loadForRiwayah(rawiOrQiraa);

  /// Backward-compatible loader for [QuranCountingSystem].
  static Future<QiraatAyahMapper> loadForCountingSystem(
    QuranCountingSystem system, {
    String? customAssetPath,
  }) async {
    if (system == QuranCountingSystem.kufi) {
      return QiraatAyahMapper.kufiIdentity();
    }
    final riwayah = QuranRiwayah.values.firstWhere(
      (r) => r.countingSystem == system,
      orElse: () => QuranRiwayah.warsh,
    );
    return loadForRiwayah(riwayah, customAssetPath: customAssetPath);
  }

  /// Backward-compatible loader for [QuranQiraa].
  static Future<QiraatAyahMapper> loadForQiraa(QuranQiraa qiraa) =>
      loadForCountingSystem(qiraa.countingSystem);

  /// Alias for [loadForRiwayah].
  static Future<QiraatAyahMapper> loadForRawiOrQiraa(dynamic input) =>
      loadForRiwayah(input);

  /// Returns the corresponding Hafs ayah numbers for a given source Riwayah verse.
  List<int> getHafsAyahs(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return [sourceAyah];
    return _sourceToHafs[surahNumber]?[sourceAyah] ?? [sourceAyah];
  }

  /// Returns the primary (first) Hafs ayah number corresponding to a source verse.
  int getPrimaryHafsAyah(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return sourceAyah;
    final list = getHafsAyahs(surahNumber, sourceAyah);
    return list.isNotEmpty ? list.first : sourceAyah;
  }

  /// Reverse lookup: Returns the source Riwayah ayah numbers corresponding to a Hafs ayah.
  List<int> getSourceAyahs(int surahNumber, int hafsAyah) {
    if (system == QuranCountingSystem.kufi) return [hafsAyah];
    return _hafsToSource[surahNumber]?[hafsAyah] ?? [hafsAyah];
  }

  /// Returns the mapping relationship status ('mapped', 'covers_multiple', 'part_of_multiple').
  String getMappingStatus(int surahNumber, int sourceAyah) {
    if (system == QuranCountingSystem.kufi) return 'mapped';
    return _statusMap[surahNumber]?[sourceAyah] ?? 'mapped';
  }

  /// Returns the total verse count for a surah in this Riwayah's counting tradition.
  int getSourceAyahCount(int surahNumber) {
    if (system == QuranCountingSystem.kufi) return _standardHafsCounts[surahNumber] ?? 0;
    return _sourceCounts[surahNumber] ?? _standardHafsCounts[surahNumber] ?? 0;
  }

  /// Returns the total verse count for a surah in the standard Hafs (Kufi) tradition.
  int getHafsAyahCount(int surahNumber) {
    return _standardHafsCounts[surahNumber] ?? 0;
  }

  /// Clears the internal singleton cache.
  static void clearCache() => _cache.clear();

  static const Map<int, int> _standardHafsCounts = {
    1: 7, 2: 286, 3: 200, 4: 176, 5: 120, 6: 165, 7: 206, 8: 75, 9: 129,
    10: 109, 11: 123, 12: 111, 13: 43, 14: 52, 15: 99, 16: 128, 17: 111,
    18: 110, 19: 98, 20: 135, 21: 112, 22: 78, 23: 118, 24: 64, 25: 77,
    26: 227, 27: 93, 28: 88, 29: 69, 30: 60, 31: 34, 32: 30, 33: 73,
    34: 54, 35: 45, 36: 83, 37: 182, 38: 88, 39: 75, 40: 85, 41: 54,
    42: 53, 43: 89, 44: 59, 45: 37, 46: 35, 47: 38, 48: 29, 49: 18,
    50: 45, 51: 60, 52: 49, 53: 62, 54: 55, 55: 78, 56: 96, 57: 29,
    58: 22, 59: 24, 60: 13, 61: 14, 62: 11, 63: 11, 64: 18, 65: 12,
    66: 12, 67: 30, 68: 52, 69: 52, 70: 44, 71: 28, 72: 28, 73: 20,
    74: 56, 75: 40, 76: 31, 77: 50, 78: 40, 79: 46, 80: 42, 81: 29,
    82: 19, 83: 36, 84: 25, 85: 22, 86: 17, 87: 19, 88: 26, 89: 30,
    90: 20, 91: 15, 92: 21, 93: 11, 94: 8, 95: 8, 96: 19, 97: 5,
    98: 8, 99: 8, 100: 11, 101: 11, 102: 8, 103: 3, 104: 9, 105: 5,
    106: 4, 107: 7, 108: 3, 109: 6, 110: 3, 111: 5, 112: 4, 113: 5,
    114: 6,
  };
}
