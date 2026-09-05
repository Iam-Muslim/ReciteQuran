import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/qiraat_ayah_mapper.dart';
import 'package:recite_quran/data/quran_data.dart';

void main() {
  group('QuranRepository Dynamic Multi-Riwaya Tests', () {
    late QuranMetadataService metadataService;
    late QuranRepository repository;

    setUpAll(() async {
      final phonemesFile = File('assets/model/ordered_quran_phonemes.json');
      metadataService = QuranMetadataService(phonemeFilePath: phonemesFile.path);
      await metadataService.loadData();
    });

    test('Hafs (Kufi default): Surah 1 has 7 ayahs starting with Basmalah', () {
      repository = QuranRepository(metadataService);
      final verses = repository.getSurah(1);
      expect(verses.length, 7);

      // In Hafs, verse 1 is Basmalah (4 words: Bismillah)
      expect(verses[0].ayah, 1);
      expect(verses[0].uthmaniWords.length, 4);

      // Verse 2 is Al-Hamd (4 words: Alhamdu lillahi rabbil alamin)
      expect(verses[1].ayah, 2);
      expect(verses[1].uthmaniWords.length, 4);

      // Check words
      final words = repository.getSurahWords(1);
      expect(words.length, 29);
      expect(repository.getAyahStartGlobalIndex(1, 1), 0);
      expect(repository.getAyahStartGlobalIndex(1, 2), 4);
    });

    test('Warsh (Madani Last): Surah 1 has 7 ayahs starting with Al-Hamd', () async {
      final mapperFile = File('test/fixtures/warsh-to-hafs.json');
      final json = jsonDecode(await mapperFile.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.madaniLast);

      repository = QuranRepository(metadataService, ayahMapper: mapper);
      final verses = repository.getSurah(1);
      expect(verses.length, 7);

      // In Warsh, verse 1 is "Al-Hamd" (corresponds to Hafs 1:2)
      expect(verses[0].ayah, 1);
      expect(verses[0].uthmaniWords.length, 4);

      // Verse 6 is "Sirata allatheena anamta alayhim" (first 4 words of Hafs 1:7)
      expect(verses[5].ayah, 6);
      expect(verses[5].uthmaniWords.length, 4);

      // Verse 7 is "Ghayril maghdubi alayhim walad-dalleen" (last 5 words of Hafs 1:7)
      expect(verses[6].ayah, 7);
      expect(verses[6].uthmaniWords.length, 5);

      // ContinuousQuranWord mapping
      final words = repository.getSurahWords(1);
      expect(words.first.ayah, 1);

      // Start global index for verse 1 should be 0
      expect(repository.getAyahStartGlobalIndex(1, 1), 0);
      // Start global index for verse 6
      final v6Start = repository.getAyahStartGlobalIndex(1, 6);
      expect(v6Start, greaterThan(0));
      expect(words[v6Start].ayah, 6);
    });

    test('Al-Baqarah ayah count reflects counting tradition', () async {
      final mapperFile = File('test/fixtures/warsh-to-hafs.json');
      final json = jsonDecode(await mapperFile.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(json, system: QuranCountingSystem.madaniLast);

      repository = QuranRepository(metadataService, ayahMapper: mapper);
      expect(mapper.getSourceAyahCount(2), 285);
      expect(mapper.getHafsAyahCount(2), 286);
    });
  });
}
