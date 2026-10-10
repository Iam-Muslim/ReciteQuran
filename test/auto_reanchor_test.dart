import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  group('Auto-Reanchor (Loss-of-Tracking Recovery) Tests', () {
    final List<String> fatihaPhonemes = [
      // Ayah 1 (Words 0..3)
      'بِسمِ', // 0
      'للَااهِ', // 1
      'ررَحمَاانِ', // 2
      'ررَحِيمِ', // 3
      // Ayah 2 (Words 4..7)
      'ءَلحَمدُ', // 4
      'لِلَّاهِ', // 5
      'رَبِّ', // 6
      'لعَالَمِين', // 7
      // Ayah 3 (Words 8..9)
      'ءَلرَّحمَاانِ', // 8
      'ررَحِيمِ', // 9
      // Ayah 4 (Words 10..12)
      'مَاالِكِ', // 10
      'يَومِ', // 11
      'ددِين', // 12
      // Ayah 5 (Words 13..16)
      'ءِيَّاكَ', // 13
      'نَعبُدُ', // 14
      'وَءِيَّاكَ', // 15
      'نَستَعِين', // 16
      // Ayah 6 (Words 17..19)
      'ءِهدِنَا', // 17
      'صِّرَااطَ', // 18
      'لمُستَقِيم', // 19
      // Ayah 7 (Words 20..28)
      'صِرَااطَ', // 20
      'لَّذِينَ', // 21
      'ءَنعَمتَ', // 22
      'عَلَيهِم', // 23
      'غَيرِ', // 24
      'لمَغضُوبِ', // 25
      'عَلَيهِم', // 26
      'وَلَا', // 27
      'ضضَاالِّين', // 28
    ];

    List<int> calculateBoundaries(List<String> words) {
      final List<int> bounds = [];
      int cursor = 0;
      for (final w in words) {
        bounds.add(cursor);
        cursor += w.length;
      }
      bounds.add(cursor);
      return bounds;
    }

    final boundaries = calculateBoundaries(fatihaPhonemes);
    final fullPhonemes = fatihaPhonemes.join('');

    test('Scenario 1: Dictation Mode - user skips from Ayah 1 to Ayah 6, auto-reanchors when enabled', () {
      final List<Map<String, dynamic>> events = [];
      final sequencer = DictationSequencer((e) => events.add(e));
      sequencer.updateConfig(const TrackerConfig(
        enableAutoReanchor: true,
      ));

      sequencer.setSurahReference(SetSurahReferenceCommand(
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        surahNumber: 1,
        isTajweed: false, // Dictation Mode
        forceClear: true,
      ));

      expect(sequencer.targetWordCursor, 0);

      // Reciter recites Ayah 1: 'بِسمِللَااهِررَحمَاانِررَحِيمِ'
      const ayah1 = 'بِسمِللَااهِررَحمَاانِررَحِيمِ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: ayah1,
        timestamps: List.filled(ayah1.length, 0.1),
      ));

      // Ayah 1 words (0, 1, 2, 3) are green
      expect(sequencer.committedGreenWords.contains(0), isTrue);
      expect(sequencer.committedGreenWords.contains(3), isTrue);
      expect(sequencer.targetWordCursor, 4); // Cursor is now at Ayah 2

      // Reciter skips Ayahs 2, 3, 4, 5 (13 words!) and recites Ayah 6 + 7:
      // 'ءِهدِنَاصِّرَااطَلمُستَقِيمصِرَااطَلَّذِينَءَنعَمتَ' (41 chars)
      const ayah6and7 = 'ءِهدِنَاصِّرَااطَلمُستَقِيمصِرَااطَلَّذِينَءَنعَمتَ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: '$ayah1$ayah6and7',
        timestamps: List.filled('$ayah1$ayah6and7'.length, 0.5),
      ));

      expect(sequencer.committedGreenWords.contains(17), isTrue);
      expect(sequencer.committedGreenWords.contains(18), isTrue);
      expect(sequencer.targetWordCursor, greaterThanOrEqualTo(19));
    });

    test('Scenario 2: Tajweed Mode - skips are strictly NOT re-anchored even if enableAutoReanchor is true', () {
      final List<Map<String, dynamic>> events = [];
      final sequencer = DictationSequencer((e) => events.add(e));
      sequencer.updateConfig(const TrackerConfig(
        enableAutoReanchor: true,
      ));

      sequencer.setSurahReference(SetSurahReferenceCommand(
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        surahNumber: 1,
        isTajweed: true, // Tajweed Mode
        forceClear: true,
      ));

      // Reciter recites Ayah 1
      const ayah1 = 'بِسمِللَااهِررَحمَاانِررَحِيمِ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: ayah1,
        timestamps: List.filled(ayah1.length, 0.1),
      ));
      expect(sequencer.committedGreenWords.contains(0), isTrue);
      expect(sequencer.targetWordCursor, 4);

      // Reciter skips to Ayah 6:
      const ayah6and7 = 'ءِهدِنَاصِّرَااطَلمُستَقِيمصِرَااطَلَّذِينَءَنعَمتَ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: '$ayah1$ayah6and7',
        timestamps: List.filled('$ayah1$ayah6and7'.length, 0.5),
      ));

      // In Tajweed mode, re-anchor is strictly disabled:
      // Words 17, 18 must NEVER be reached or auto-jumped!
      expect(sequencer.committedGreenWords.contains(17), isFalse);
      expect(sequencer.committedGreenWords.contains(18), isFalse);
      expect(sequencer.targetWordCursor, lessThan(7));
    });

    test('Scenario 3: Config defaults - autoReanchor defaults to false, earlyMatching defaults to true', () {
      const defaultConfig = TrackerConfig();
      expect(defaultConfig.enableAutoReanchor, isFalse);
      expect(defaultConfig.enableEarlyMatching, isTrue);
      expect(defaultConfig.reanchorStallThreshold, 24);

      final List<Map<String, dynamic>> events = [];
      final sequencer = DictationSequencer((e) => events.add(e));
      // Uses default config (enableAutoReanchor: false)

      sequencer.setSurahReference(SetSurahReferenceCommand(
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        surahNumber: 1,
        isTajweed: false, // Dictation Mode, but re-anchor is disabled by default
        forceClear: true,
      ));

      const ayah1 = 'بِسمِللَااهِررَحمَاانِررَحِيمِ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: ayah1,
        timestamps: List.filled(ayah1.length, 0.1),
      ));
      expect(sequencer.targetWordCursor, 4);

      const ayah6and7 = 'ءِهدِنَاصِّرَااطَلمُستَقِيمصِرَااطَلَّذِينَءَنعَمتَ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: '$ayah1$ayah6and7',
        timestamps: List.filled('$ayah1$ayah6and7'.length, 0.5),
      ));

      // Because enableAutoReanchor is false by default, re-anchor does not jump
      expect(sequencer.committedGreenWords.contains(17), isFalse);
      expect(sequencer.targetWordCursor, lessThan(7));
    });

    test('Scenario 4: Anti-ambiguity guard suppresses jump on ambiguous candidates', () {
      // Create a test sequence with an ambiguous refrain: "ءَلحَمدُلِلَّاهِرَبِّلعَالَمِين" repeated at two different places
      final List<String> repetitiveWords = [
        'ءَلحَمدُ', // 0
        'لِلَّاهِ',  // 1
        'رَبِّ',   // 2
        'لعَالَمِين', // 3
        'غَيرِ',   // 4
        'ءَلحَمدُ', // 5 - duplicate
        'لِلَّاهِ',  // 6 - duplicate
        'رَبِّ',   // 7 - duplicate
        'لعَالَمِين', // 8 - duplicate
      ];
      final repBounds = calculateBoundaries(repetitiveWords);
      final repFull = repetitiveWords.join('');

      final List<Map<String, dynamic>> events = [];
      final sequencer = DictationSequencer((e) => events.add(e));
      sequencer.updateConfig(const TrackerConfig(
        enableAutoReanchor: true,
      ));

      sequencer.setSurahReference(SetSurahReferenceCommand(
        fullPhonemes: repFull,
        boundaries: repBounds,
        surahNumber: 1,
        isTajweed: false,
        forceClear: true,
      ));

      // Cursor at 0. Unconsumed ambiguous speech that matches BOTH word 0 and word 5 equally:
      const ambiguousQuery = 'ءَلحَمدُلِلَّاهِرَبِّلعَالَمِين';
      sequencer.syncStream(const SyncStreamCommand(
        asrText: 'غَرِيب$ambiguousQuery',
        timestamps: [0.1],
      ));

      // The ambiguity guard must prevent jumping to word 5 because dist(word 0) == dist(word 5)
      expect(sequencer.committedGreenWords.contains(5), isFalse);
    });

    test('Scenario 5: Ambiguous refrain (Surah 55:25) suppresses jump, then re-anchors when following verse 55:26 arrives', () async {
      final service = QuranMetadataService(
        phonemeFilePath: 'assets/model/ordered_quran_phonemes.json',
      );
      await service.loadData();
      final repo = QuranRepository(service);

      final words = repo.getSurahWords(55);
      final boundaries = <int>[];
      int cursor = 0;
      for (final w in words) {
        boundaries.add(cursor);
        cursor += w.phoneme.replaceAll(' ', '').length;
      }
      boundaries.add(cursor);
      final fullPhonemes = words.map((w) => w.phoneme.replaceAll(' ', '')).join('');

      final List<Map<String, dynamic>> events = [];
      final sequencer = DictationSequencer((e) => events.add(e));
      sequencer.updateConfig(const TrackerConfig(
        enableAutoReanchor: true,
      ));

      sequencer.setSurahReference(SetSurahReferenceCommand(
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        surahNumber: 55,
        isTajweed: false,
        forceClear: true,
      ));

      expect(sequencer.targetWordCursor, 0);

      // 1. Reciter says ONLY the refrain (Ayah 25):
      const refrainAsr = 'فَبِ ءَييِءَاالَااااءِرَببِكُمَاتُكَذِّبَانِ';
      sequencer.syncStream(SyncStreamCommand(
        asrText: refrainAsr,
        timestamps: List.filled(refrainAsr.length, 0.1),
      ));

      // Refrain alone is ambiguous across 31 refrains -> jump suppressed, cursor stays at 0
      expect(sequencer.targetWordCursor, 0);

      // 2. Reciter continues with next Ayah 26 ("كل من عليها فان"):
      const ayah26Asr = 'للُمَنعَلَيهَاافَاان';
      sequencer.syncStream(SyncStreamCommand(
        asrText: '$refrainAsr$ayah26Asr',
        timestamps: List.filled('$refrainAsr$ayah26Asr'.length, 0.2),
      ));

      // Re-anchored to word 91 (Ayah 25) and advanced through Ayah 26
      expect(sequencer.targetWordCursor, greaterThanOrEqualTo(91));
      expect(sequencer.committedGreenWords.contains(91), isTrue);
      expect(sequencer.committedGreenWords.contains(92), isTrue);
      expect(sequencer.committedGreenWords.contains(98), isTrue);
    });
  });
}

