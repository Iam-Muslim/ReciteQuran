import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  group('LcsOmissionDetector Tests (tasmee3-muaalem-findings benchmark)', () {
    test('LCS length calculates correctly', () {
      expect(LcsOmissionDetector.lcsLength('abcde', 'ace'), equals(3));
      expect(LcsOmissionDetector.lcsLength('ءِننننَشَاانِءَكَ', 'ءِننننَ'), equals(7));
      expect(LcsOmissionDetector.lcsLength('', 'abc'), equals(0));
    });

    test('108:3 Complete Recitation (KTR3_KAMIL) -> matches with 0 shortfall', () {
      final phonemesPerWord = [
        'ءِننننَ',
        'شَاانِءَكَ',
        'هُوَ',
        'لءَبڇتَر',
      ];
      final emittedPhonemes = 'ءِننننَشَاانِءَكَهُوَلءَبڇتَر';

      final result = LcsOmissionDetector.detectOmission(
        phonemesPerWord: phonemesPerWord,
        emittedPhonemes: emittedPhonemes,
      );

      expect(result.isOmissionDetected, isFalse);
      expect(result.shortfall, equals(0));
    });

    test('108:3 Omitted word "هُوَ" (KTR3_HADHF) -> correctly nominates index 2 ("هُوَ")', () {
      final phonemesPerWord = [
        'ءِننننَ',     // [0]
        'شَاانِءَكَ', // [1]
        'هُوَ',       // [2] -> omitted
        'لءَبڇتَر',   // [3]
      ];
      // Emitted without "هُوَ" (26 chars vs 29 chars reference)
      final emittedPhonemes = 'ءِننننَشَاانِءَكَلءَبڇتَر';

      final result = LcsOmissionDetector.detectOmission(
        phonemesPerWord: phonemesPerWord,
        emittedPhonemes: emittedPhonemes,
      );

      expect(result.isOmissionDetected, isTrue);
      expect(result.omittedWordIndex, equals(2)); // "هُوَ" is at index 2
      expect(result.shortfall, greaterThan(0));
      expect(result.confidenceGap, greaterThanOrEqualTo(3));
    });

    test('103:2 Omitted word "ٱلْإِنسَـٰنَ" (ASR2_HADHF) -> correctly nominates index 1', () {
      final phonemesPerWord = [
        'ءِننننَ',       // [0]
        'لءِںںںسَاانَ', // [1] -> omitted
        'لَفِۦۦ',        // [2]
        'خُسر',         // [3]
      ];
      // Emitted without "الإنسان" (17 chars vs 29 chars reference)
      final emittedPhonemes = 'ءِننننَلَفِۦۦخُسر';

      final result = LcsOmissionDetector.detectOmission(
        phonemesPerWord: phonemesPerWord,
        emittedPhonemes: emittedPhonemes,
      );

      expect(result.isOmissionDetected, isTrue);
      expect(result.omittedWordIndex, equals(1)); // "الإنسان" is at index 1
      expect(result.shortfall, equals(12));
    });

    test('103:2 Omitted last word "خُسْرٍ" (KATHRA_ISQAT2) -> correctly nominates index 3', () {
      final phonemesPerWord = [
        'ءِننننَ',       // [0]
        'لءِںںںسَاانَ', // [1]
        'لَفِۦۦ',        // [2]
        'خُسر',         // [3] -> omitted
      ];
      final emittedPhonemes = 'ءِننننَلءِںںںسَاانَلَفِۦۦ';

      final result = LcsOmissionDetector.detectOmission(
        phonemesPerWord: phonemesPerWord,
        emittedPhonemes: emittedPhonemes,
      );

      expect(result.isOmissionDetected, isTrue);
      expect(result.omittedWordIndex, equals(3)); // "خسر" is at index 3
    });
  });
}
