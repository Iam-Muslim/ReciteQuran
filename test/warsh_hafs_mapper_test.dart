import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/alignment/warsh_hafs_mapper.dart';

void main() {
  group('WarshHafsMapper Tests', () {
    late WarshHafsMapper mapper;

    setUpAll(() async {
      final file = File('assets/json/warsh-to-hafs.json');
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      mapper = WarshHafsMapper.fromJson(json);
    });

    test('Surah 1 (Al-Fatiha) mapping', () {
      expect(mapper.getWarshAyahCount(1), 7);
      expect(mapper.getHafsAyahCount(1), 7);

      // In Warsh Madani-last: Ayah 1 covers Hafs Ayah 1 & 2
      expect(mapper.getHafsAyahs(1, 1), [1, 2]);
      expect(mapper.getPrimaryHafsAyah(1, 1), 1);
      expect(mapper.getMappingStatus(1, 1), 'covers_multiple');

      // Warsh Ayah 2 maps to Hafs 3
      expect(mapper.getHafsAyahs(1, 2), [3]);
      expect(mapper.getMappingStatus(1, 2), 'mapped');

      // Reverse lookup: Hafs Ayah 1 maps to Warsh 1
      expect(mapper.getWarshAyahs(1, 1), [1]);
      expect(mapper.getWarshAyahs(1, 2), [1]);
      expect(mapper.getWarshAyahs(1, 3), [2]);
    });

    test('Surah 2 (Al-Baqarah) mapping counts and multi-ayah spans', () {
      expect(mapper.getWarshAyahCount(2), 285);
      expect(mapper.getHafsAyahCount(2), 286);

      // Warsh Ayah 1 covers Hafs 1 & 2 (Alif-Lam-Meem ... )
      expect(mapper.getHafsAyahs(2, 1), [1, 2]);
      expect(mapper.getMappingStatus(2, 1), 'covers_multiple');
    });

    test('Surah 114 (An-Nas) standard mapped fallback', () {
      expect(mapper.getWarshAyahCount(114), 6);
      expect(mapper.getHafsAyahCount(114), 6);
      expect(mapper.getHafsAyahs(114, 1), [1]);
      expect(mapper.getWarshAyahs(114, 1), [1]);
    });
  });
}
