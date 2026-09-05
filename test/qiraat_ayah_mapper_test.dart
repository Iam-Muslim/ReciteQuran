import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/qiraat_ayah_mapper.dart';

void main() {
  group('QiraatAyahMapper, QuranQiraa & QuranRawi Enum Tests', () {
    test('Kufi identity mapping requires no JSON load and is 1:1', () {
      final kufi = QiraatAyahMapper.kufiIdentity();
      expect(kufi.system, QuranCountingSystem.kufi);
      expect(kufi.getHafsAyahs(1, 7), [7]);
      expect(kufi.getSourceAyahs(1, 7), [7]);
      expect(kufi.getPrimaryHafsAyah(1, 7), 7);
    });

    test('QuranRawi enum inherits countingSystem directly from QuranQiraa', () {
      // Nafi' -> Madani Last
      expect(QuranRawi.warsh.qiraa, QuranQiraa.nafi);
      expect(QuranRawi.warsh.countingSystem, QuranCountingSystem.madaniLast);
      expect(QuranRawi.qaloon.qiraa, QuranQiraa.nafi);
      expect(QuranRawi.qaloon.countingSystem, QuranCountingSystem.madaniLast);

      // Ibn Kathir -> Makki
      expect(QuranRawi.bazzi.qiraa, QuranQiraa.ibnKathir);
      expect(QuranRawi.bazzi.countingSystem, QuranCountingSystem.makki);
      expect(QuranRawi.qunbul.qiraa, QuranQiraa.ibnKathir);
      expect(QuranRawi.qunbul.countingSystem, QuranCountingSystem.makki);

      // Abu 'Amr -> Basri
      expect(QuranRawi.duri.qiraa, QuranQiraa.abuAmr);
      expect(QuranRawi.duri.countingSystem, QuranCountingSystem.basri);
      expect(QuranRawi.susi.qiraa, QuranQiraa.abuAmr);
      expect(QuranRawi.susi.countingSystem, QuranCountingSystem.basri);

      // 'Asim -> Kufi
      expect(QuranRawi.hafs.qiraa, QuranQiraa.asim);
      expect(QuranRawi.hafs.countingSystem, QuranCountingSystem.kufi);
      expect(QuranRawi.shubah.qiraa, QuranQiraa.asim);
      expect(QuranRawi.shubah.countingSystem, QuranCountingSystem.kufi);
    });

    test('QuranRawi fromId and tryFromId work with aliases', () {
      expect(QuranRawi.tryFromId('hafs'), QuranRawi.hafs);
      expect(QuranRawi.tryFromId('warsh'), QuranRawi.warsh);
      expect(QuranRawi.tryFromId('qalun'), QuranRawi.qaloon);
      expect(QuranRawi.tryFromId('qaloon'), QuranRawi.qaloon);
      expect(QuranRawi.tryFromId('unknown_id'), isNull);
    });

    test('QuranRawi.parse handles Arabic and English strings seamlessly', () {
      expect(QuranRawi.parse('warsh'), QuranRawi.warsh);
      expect(QuranRawi.parse('qalun'), QuranRawi.qaloon);
      expect(QuranRawi.parse('al-susi'), QuranRawi.susi);
      expect(QuranRawi.parse('susi'), QuranRawi.susi);
      expect(QuranRawi.parse('السوسي'), QuranRawi.susi);
      expect(QuranRawi.parse('حفص عن عاصم'), QuranRawi.hafs);
      expect(QuranRawi.parse('ورش عن نافع'), QuranRawi.warsh);
      expect(QuranRawi.parse('نافع'), QuranRawi.warsh);
      expect(QuranRawi.parse('عاصم'), QuranRawi.hafs);
    });

    test('Counting system resolution directly via enum', () {
      expect(QuranCountingSystem.fromRawi(QuranRawi.warsh), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawi(QuranRawi.susi), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawi(QuranRawi.hafs), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromQiraa(QuranQiraa.ibnKathir), QuranCountingSystem.makki);
    });

    test('Madani-Last (Nafi) loaded from JSON matches canonical Quranpedia data', () async {
      final file = File('assets/json/madani-last-to-kufi.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.madaniLast);

      expect(mapper.getSourceAyahCount(1), 7);
      expect(mapper.getHafsAyahCount(1), 7);
      expect(mapper.getHafsAyahs(1, 1), [1, 2]);
      expect(mapper.getPrimaryHafsAyah(1, 1), 1);
      expect(mapper.getMappingStatus(1, 1), 'covers_multiple');
    });

    test('Makki (Ibn Kathir) loaded from JSON', () async {
      final file = File('assets/json/makki-to-kufi.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.makki);

      expect(mapper.system, QuranCountingSystem.makki);
      expect(mapper.getSourceAyahCount(114), 7);
      expect(mapper.getHafsAyahCount(114), 6);
    });

    test('Basri (Abu Amr & Yaqub) loaded from JSON', () async {
      final file = File('assets/json/basri-to-kufi.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.basri);

      expect(mapper.system, QuranCountingSystem.basri);
      expect(mapper.getSourceAyahCount(114), 6);
      expect(mapper.getHafsAyahCount(114), 6);
    });

    test('Dimashqi (Ibn Amir) loaded from JSON', () async {
      final file = File('assets/json/dimashqi-to-kufi.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.dimashqi);

      expect(mapper.system, QuranCountingSystem.dimashqi);
      expect(mapper.getSourceAyahCount(114), 7);
      expect(mapper.getHafsAyahCount(114), 6);
    });
  });
}
