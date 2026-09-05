import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/qiraat_ayah_mapper.dart';

void main() {
  group('QiraatAyahMapper & QuranRiwayah Tests', () {
    test('Kufi identity mapping requires no JSON load and is 1:1', () {
      final kufi = QiraatAyahMapper.kufiIdentity();
      expect(kufi.system, QuranCountingSystem.kufi);
      expect(kufi.getHafsAyahs(1, 7), [7]);
      expect(kufi.getSourceAyahs(1, 7), [7]);
      expect(kufi.getPrimaryHafsAyah(1, 7), 7);
    });

    test('QuranRiwayah enum inherits countingSystem directly from QuranQiraa', () {
      // Nafi' -> Madani Last
      expect(QuranRiwayah.warsh.qiraa, QuranQiraa.nafi);
      expect(QuranRiwayah.warsh.countingSystem, QuranCountingSystem.madaniLast);
      expect(QuranRiwayah.qaloon.qiraa, QuranQiraa.nafi);
      expect(QuranRiwayah.qaloon.countingSystem, QuranCountingSystem.madaniLast);

      // Ibn Kathir -> Makki
      expect(QuranRiwayah.bazzi.qiraa, QuranQiraa.ibnKathir);
      expect(QuranRiwayah.bazzi.countingSystem, QuranCountingSystem.makki);
      expect(QuranRiwayah.qunbul.qiraa, QuranQiraa.ibnKathir);
      expect(QuranRiwayah.qunbul.countingSystem, QuranCountingSystem.makki);

      // Abu 'Amr -> Basri
      expect(QuranRiwayah.duri.qiraa, QuranQiraa.abuAmr);
      expect(QuranRiwayah.duri.countingSystem, QuranCountingSystem.basri);
      expect(QuranRiwayah.susi.qiraa, QuranQiraa.abuAmr);
      expect(QuranRiwayah.susi.countingSystem, QuranCountingSystem.basri);

      // 'Asim -> Kufi
      expect(QuranRiwayah.hafs.qiraa, QuranQiraa.asim);
      expect(QuranRiwayah.hafs.countingSystem, QuranCountingSystem.kufi);
      expect(QuranRiwayah.shubah.qiraa, QuranQiraa.asim);
      expect(QuranRiwayah.shubah.countingSystem, QuranCountingSystem.kufi);
    });

    test('QuranRiwayah fromId and tryFromId work with aliases', () {
      expect(QuranRiwayah.tryFromId('hafs'), QuranRiwayah.hafs);
      expect(QuranRiwayah.tryFromId('warsh'), QuranRiwayah.warsh);
      expect(QuranRiwayah.tryFromId('qalun'), QuranRiwayah.qaloon);
      expect(QuranRiwayah.tryFromId('qaloon'), QuranRiwayah.qaloon);
      expect(QuranRiwayah.tryFromId('unknown_id'), isNull);
    });

    test('QuranRiwayah.parse handles Arabic and English strings seamlessly', () {
      expect(QuranRiwayah.parse('warsh'), QuranRiwayah.warsh);
      expect(QuranRiwayah.parse('qalun'), QuranRiwayah.qaloon);
      expect(QuranRiwayah.parse('al-susi'), QuranRiwayah.susi);
      expect(QuranRiwayah.parse('susi'), QuranRiwayah.susi);
      expect(QuranRiwayah.parse('السوسي'), QuranRiwayah.susi);
      expect(QuranRiwayah.parse('حفص عن عاصم'), QuranRiwayah.hafs);
      expect(QuranRiwayah.parse('ورش عن نافع'), QuranRiwayah.warsh);
      expect(QuranRiwayah.parse('نافع'), QuranRiwayah.warsh);
      expect(QuranRiwayah.parse('عاصم'), QuranRiwayah.hafs);
    });

    test('Counting system resolution directly via enum', () {
      expect(QuranCountingSystem.fromRiwayah(QuranRiwayah.warsh), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRiwayah(QuranRiwayah.susi), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRiwayah(QuranRiwayah.hafs), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromQiraa(QuranQiraa.ibnKathir), QuranCountingSystem.makki);
    });

    test('Warsh loaded from official warsh-to-hafs.json', () async {
      final file = File('test/fixtures/warsh-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.warsh);

      expect(mapper.getSourceAyahCount(1), 7);
      expect(mapper.getHafsAyahCount(1), 7);
      expect(mapper.getHafsAyahs(1, 1), [1, 2]);
      expect(mapper.getPrimaryHafsAyah(1, 1), 1);
      expect(mapper.getMappingStatus(1, 1), 'covers_multiple');
    });

    test('Qaloon loaded from official qaloon-to-hafs.json', () async {
      final file = File('test/fixtures/qaloon-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.qaloon);

      expect(mapper.riwayah, QuranRiwayah.qaloon);
      expect(mapper.system, QuranCountingSystem.madaniLast);
      expect(mapper.getHafsAyahs(1, 1), [1, 2]);
    });

    test('Al-Bazzi loaded from official bazzi-to-hafs.json', () async {
      final file = File('test/fixtures/bazzi-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.bazzi);

      expect(mapper.riwayah, QuranRiwayah.bazzi);
      expect(mapper.system, QuranCountingSystem.makki);
      expect(mapper.getSourceAyahCount(114), 7);
      expect(mapper.getHafsAyahCount(114), 6);
    });

    test('Al-Susi loaded from official susi-to-hafs.json', () async {
      final file = File('test/fixtures/susi-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.susi);

      expect(mapper.riwayah, QuranRiwayah.susi);
      expect(mapper.system, QuranCountingSystem.basri);
      expect(mapper.getSourceAyahCount(114), 6);
      expect(mapper.getHafsAyahCount(114), 6);
    });

    test('Al-Duri loaded from official duri-to-hafs.json', () async {
      final file = File('test/fixtures/duri-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.duri);

      expect(mapper.riwayah, QuranRiwayah.duri);
      expect(mapper.system, QuranCountingSystem.basri);
      expect(mapper.getSourceAyahCount(114), 6);
      expect(mapper.getHafsAyahCount(114), 6);
    });

    test('Qunbul loaded from official qunbul-to-hafs.json', () async {
      final file = File('test/fixtures/qunbul-to-hafs.json');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, riwayah: QuranRiwayah.qunbul);

      expect(mapper.riwayah, QuranRiwayah.qunbul);
      expect(mapper.system, QuranCountingSystem.makki);
      expect(mapper.getSourceAyahCount(114), 7);
      expect(mapper.getHafsAyahCount(114), 6);
    });
  });
}
