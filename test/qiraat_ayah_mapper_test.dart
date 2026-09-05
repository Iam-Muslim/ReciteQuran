import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/qiraat_ayah_mapper.dart';

void main() {
  group('QiraatAyahMapper Tests (All 6 Counting Madhhabs & 20 Rawis)', () {
    test('Kufi identity mapping requires no JSON load and is 1:1', () {
      final kufi = QiraatAyahMapper.kufiIdentity();
      expect(kufi.system, QuranCountingSystem.kufi);
      expect(kufi.getHafsAyahs(1, 7), [7]);
      expect(kufi.getSourceAyahs(1, 7), [7]);
      expect(kufi.getPrimaryHafsAyah(1, 7), 7);
    });

    test('Counting system resolution for all 20 rawis in English', () {
      // Nafi'
      expect(QuranCountingSystem.fromRawiOrQiraa('warsh'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('qalun'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('qaloon'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('qaloon-an-nafi'), QuranCountingSystem.madaniLast);

      // Abu Ja'far
      expect(QuranCountingSystem.fromRawiOrQiraa('ibn_wardan'), QuranCountingSystem.madaniFirst);
      expect(QuranCountingSystem.fromRawiOrQiraa('ibn_jammaz'), QuranCountingSystem.madaniFirst);

      // Ibn Kathir
      expect(QuranCountingSystem.fromRawiOrQiraa('bazzi'), QuranCountingSystem.makki);
      expect(QuranCountingSystem.fromRawiOrQiraa('qunbul'), QuranCountingSystem.makki);

      // Abu 'Amr & Ya'qub
      expect(QuranCountingSystem.fromRawiOrQiraa('duri'), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawiOrQiraa('susi'), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawiOrQiraa('ruways'), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawiOrQiraa('rawh'), QuranCountingSystem.basri);

      // Ibn 'Amir
      expect(QuranCountingSystem.fromRawiOrQiraa('hisham'), QuranCountingSystem.dimashqi);
      expect(QuranCountingSystem.fromRawiOrQiraa('ibn_dhakwan'), QuranCountingSystem.dimashqi);

      // Asim, Hamza, Kisai, Khalaf
      expect(QuranCountingSystem.fromRawiOrQiraa('hafs'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('shuba'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('khalaf'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('khallad'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('abu_al_harith'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('duri_kisai'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('ishaq'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('idris'), QuranCountingSystem.kufi);
    });

    test('Counting system resolution for Arabic Rawi & Qiraa names', () {
      expect(QuranCountingSystem.fromRawiOrQiraa('ورش'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('قالون'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('قَالُون عَنْ نَافِع'), QuranCountingSystem.madaniLast);
      expect(QuranCountingSystem.fromRawiOrQiraa('حفص'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('حَفْص عَنْ عَاصِم'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('شعبة'), QuranCountingSystem.kufi);
      expect(QuranCountingSystem.fromRawiOrQiraa('ابن كثير'), QuranCountingSystem.makki);
      expect(QuranCountingSystem.fromRawiOrQiraa('البزي'), QuranCountingSystem.makki);
      expect(QuranCountingSystem.fromRawiOrQiraa('الدوري عن أبي عمرو'), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawiOrQiraa('السوسي'), QuranCountingSystem.basri);
      expect(QuranCountingSystem.fromRawiOrQiraa('ابن عامر'), QuranCountingSystem.dimashqi);
      expect(QuranCountingSystem.fromRawiOrQiraa('أبو جعفر'), QuranCountingSystem.madaniFirst);
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
