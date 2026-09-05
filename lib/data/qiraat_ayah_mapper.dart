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

  /// Resolves counting system from identifier string with fallback to Kufi.
  static QuranCountingSystem fromId(String id) {
    final clean = id.toLowerCase().replaceAll('_', '-').trim();
    for (final s in QuranCountingSystem.values) {
      if (s.id == clean) return s;
    }
    return QuranCountingSystem.kufi;
  }

  /// Resolves counting system directly from a strongly-typed [QuranRawi].
  static QuranCountingSystem fromRawi(QuranRawi rawi) => rawi.countingSystem;

  /// Resolves counting system directly from a strongly-typed [QuranQiraa].
  static QuranCountingSystem fromQiraa(QuranQiraa qiraa) => qiraa.countingSystem;

  /// Backwards-compatible lookup accepting [QuranRawi], [QuranQiraa], [QuranCountingSystem], or name string.
  static QuranCountingSystem fromRawiOrQiraa(dynamic input) {
    if (input is QuranRawi) return input.countingSystem;
    if (input is QuranQiraa) return input.countingSystem;
    if (input is QuranCountingSystem) return input;
    return QuranRawi.parse(input.toString()).countingSystem;
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

/// Canonical 20 Rawis (الرواة العشرون) of the 10 Mutawatir Qira'at.
enum QuranRawi {
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
  ibnDhakwan('ibn-dhakwan', 'ابن ذكوان', 'Ibn Dhakwan', QuranQiraa.ibnAmir, aliases: ['dhakwan', 'ابن ذكوان عن ابن عامر']),

  // ── 5. 'Asim (Kufi) ──
  shubah('shubah', 'شعبة', 'Shu\'bah', QuranQiraa.asim, aliases: ['شعبة عن عاصم']),
  hafs('hafs', 'حفص', 'Hafs', QuranQiraa.asim, aliases: ['hafs-an-asim', 'حفص عن عاصم', 'asim', 'عاصم']),

  // ── 6. Hamza (Kufi) ──
  khalaf('khalaf', 'خلف', 'Khalaf', QuranQiraa.hamza, aliases: ['خلف عن حمزة']),
  khallad('khallad', 'خلاد', 'Khallad', QuranQiraa.hamza, aliases: ['خلاد عن حمزة']),

  // ── 7. Al-Kisa'i (Kufi) ──
  abuAlHarith('abu-al-harith', 'أبو الحارث', 'Abu al-Harith', QuranQiraa.kisai, aliases: ['abu-harith', 'أبو الحارث عن الكسائي']),
  duriKisai('duri-kisai', 'الدوري عن الكسائي', 'Al-Duri (al-Kisai)', QuranQiraa.kisai, aliases: ['الدوري عن الكسائي']),

  // ── 8. Abu Ja'far (Madani First) ──
  ibnWardan('ibn-wardan', 'ابن وردان', 'Ibn Wardan', QuranQiraa.abuJafar, aliases: ['wardan', 'ابن وردان عن أبي جعفر']),
  ibnJammaz('ibn-jammaz', 'ابن جماز', 'Ibn Jammaz', QuranQiraa.abuJafar, aliases: ['jammaz', 'ابن جماز عن أبي جعفر']),

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

  const QuranRawi(
    this.id,
    this.nameAr,
    this.nameEn,
    this.qiraa, {
    this.aliases = const [],
  });

  /// The verse counting tradition is inherited directly from the Imam's Qira'a tradition.
  QuranCountingSystem get countingSystem => qiraa.countingSystem;

  static final Map<String, QuranRawi> _lookupIndex = _buildLookupIndex();

  static Map<String, QuranRawi> _buildLookupIndex() {
    final map = <String, QuranRawi>{};
    for (final rawi in QuranRawi.values) {
      map[_normalize(rawi.id)] = rawi;
      map[_normalize(rawi.name)] = rawi;
      map[_normalize(rawi.nameEn)] = rawi;
      map[_normalize(rawi.nameAr)] = rawi;
      for (final alias in rawi.aliases) {
        map[_normalize(alias)] = rawi;
      }
    }
    // Also index Imam names to resolve to their primary rawi
    for (final qiraa in QuranQiraa.values) {
      final defaultRawi = QuranRawi.values.firstWhere((r) => r.qiraa == qiraa);
      map.putIfAbsent(_normalize(qiraa.id), () => defaultRawi);
      map.putIfAbsent(_normalize(qiraa.nameAr), () => defaultRawi);
      map.putIfAbsent(_normalize(qiraa.nameEn), () => defaultRawi);
      final firstArWord = qiraa.nameAr.split(' ').first;
      map.putIfAbsent(_normalize(firstArWord), () => defaultRawi);
      final firstEnWord = qiraa.nameEn.split(' ').first;
      map.putIfAbsent(_normalize(firstEnWord), () => defaultRawi);
    }
    return Map.unmodifiable(map);
  }

  /// Resolves a [QuranRawi] by its exact identifier or alias, with optional fallback.
  static QuranRawi fromId(String id, {QuranRawi fallback = QuranRawi.hafs}) {
    return tryFromId(id) ?? fallback;
  }

  /// Resolves a [QuranRawi] by its exact identifier or alias, returning null if not found.
  static QuranRawi? tryFromId(String id) {
    final clean = _normalize(id);
    return _lookupIndex[clean];
  }

  /// Parses any string (Arabic/English name, alias, or Imam name) into a [QuranRawi] in O(1) time.
  static QuranRawi parse(String input, {QuranRawi fallback = QuranRawi.hafs}) {
    return tryParse(input) ?? fallback;
  }

  /// Parses any string into a [QuranRawi], returning null if unrecognized.
  static QuranRawi? tryParse(String input) {
    final clean = _normalize(input);
    if (clean.isEmpty) return null;
    return _lookupIndex[clean];
  }

  static String _normalize(String input) {
    var s = input.toLowerCase().replaceAll('_', '-').replaceAll('\'', '').trim();
    // Remove Arabic diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalize Alefs
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    // Remove Tatweel
    s = s.replaceAll('ـ', '');
    return s;
  }
}

/// Type alias for [QuranRawi] to support both naming styles seamlessly.
typedef QuranRiwayah = QuranRawi;

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

  /// Loads the mapping table directly for a strongly-typed [QuranRawi] enum.
  static Future<QiraatAyahMapper> loadForRawi(QuranRawi rawi) =>
      loadForCountingSystem(rawi.countingSystem);

  /// Loads the mapping table directly for a strongly-typed [QuranQiraa] enum.
  static Future<QiraatAyahMapper> loadForQiraa(QuranQiraa qiraa) =>
      loadForCountingSystem(qiraa.countingSystem);

  /// Automatically resolves the correct counting system and loads the mapping table for any Rawi enum or string.
  static Future<QiraatAyahMapper> loadForRawiOrQiraa(dynamic input) {
    if (input is QuranRawi) return loadForRawi(input);
    if (input is QuranQiraa) return loadForQiraa(input);
    if (input is QuranCountingSystem) return loadForCountingSystem(input);
    final rawi = QuranRawi.parse(input.toString());
    return loadForRawi(rawi);
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
