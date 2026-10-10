import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/tracking/ayah_search/voice_search_controller.dart';
import 'package:recite_quran/tracking/ayah_search/phonetic_search.dart';
import 'package:recite_quran/data/quran_data.dart';
import 'package:recite_quran/engine/sherpa_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PhoneticSearch phoneticSearch;
  late VoiceSearchController controller;
  late QuranRepository repo;

  setUpAll(() async {
    phoneticSearch = PhoneticSearch();
    final refStr = File('assets/model/ref_norm_ph.txt').readAsStringSync();
    final npyBytes = File('assets/model/ph_index.npy').readAsBytesSync();
    phoneticSearch.loadSync(refPhNorm: refStr, npyBytes: npyBytes);

    final service = QuranMetadataService(
      phonemeFilePath: 'assets/model/ordered_quran_phonemes.json',
    );
    await service.loadData();
    repo = QuranRepository(service);

    controller = VoiceSearchController(
      engine: SherpaEngine(),
      repository: repo,
    );
    controller.preloadIndex();
  });

  group('Deep Analysis & Edge Case Scenarios for Ayah Finder', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 1: Standard Arabic Text vs ASR Phoneme Gap (Current Failing Part)
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 1: Standard Arabic Text with Hamza (أ, إ) fails due to _coreChars dropping Hamza', () async {
      // Standard user typing or third-party STT: "قل هو الله أحد"
      const standardText = 'قل هو الله أحد';
      final norm = PhoneticSearch.normalizeQuery(standardText);
      // 'أ' in "أحد" is stripped, producing "قلهوالهحد" instead of "قلهولاهءحد"
      expect(norm, 'قلهوالهحد');
      expect(norm.contains('ء'), isFalse);

      final result = await controller.searchCandidates(standardText);
      // FAILING PART: Returns null because standard Arabic orthography diverges from phoneme index
      expect(result, isNull);
    });

    test('Scenario 2: Standard Arabic with Lam Shamsiyyah and Hamzat Wasl fails search', () async {
      // Standard text: "اهدنا الصراط المستقيم"
      const textFatihah = 'اهدنا الصراط المستقيم';
      final norm = PhoneticSearch.normalizeQuery(textFatihah);
      // Normalizer retains unpronounced silent letters from standard text: "اهدنالصراطالمستقيم"
      expect(norm, 'اهدنالصراطالمستقيم');

      final result = await controller.searchCandidates(textFatihah);
      // FAILING PART: Reference has 'ءهدنصراطلمستقۦم', so edit distance exceeds tolerance
      expect(result, isNull);
    });

    test('Scenario 3: Phonetic ASR representation of the same verses matches with 100% precision', () async {
      // When fed the acoustic phonemes emitted by the custom Zipformer model:
      // 1. Al-Ikhlas: 'قلهولاهءحد'
      final rIkhlas = await controller.searchCandidates('قلهولاهءحد');
      expect(rIkhlas, isNotNull);
      expect(rIkhlas!.topMatch!.surah, 112);
      expect(rIkhlas.topMatch!.ayah, 1);
      expect(rIkhlas.isUnique, isTrue);

      // 2. Al-Fatihah: 'ءهدنصراطلمستقۦم'
      final rFatihah = await controller.searchCandidates('ءهدنصراطلمستقۦم');
      expect(rFatihah, isNotNull);
      expect(rFatihah!.topMatch!.surah, 1);
      expect(rFatihah.topMatch!.ayah, 6);
      expect(rFatihah.isUnique, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 2: Cross-Ayah Boundary Recitation (Wasl Across Verses)
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 4: Reciting across Ayah boundary (112:1 into 112:2 with wasl)', () async {
      // "قُلْ هُوَ اللَّهُ أَحَدٌ اللَّهُ الصَّمَدُ" -> 'قلهولاهءحدنلاهصمد'
      final result = await controller.searchCandidates('قلهولاهءحدنلاهصمد');
      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 112);
      expect(result.topMatch!.startWordIdx, 0); // From Ayah 1
      expect(result.topMatch!.endWordIdx, 1);   // From Ayah 2!
      // Verified: Multi-Ayah span ported from detector.py
      expect(result.topMatch!.startAyah, 1);
      expect(result.topMatch!.endAyah, 2);
      expect(result.topMatch!.isMultiAyah, isTrue);
    });

    test('Scenario 5: Reciting across Ayah boundary (1:6 into 1:7)', () async {
      // "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ"
      final result = await controller.searchCandidates('ءهدنصراطلمستقۦمصراطلذۦنءنعمتعليهم');
      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 1);
      expect(result.topMatch!.ayah, 7);
      // Verified: Multi-Ayah span ported from detector.py
      expect(result.topMatch!.startAyah, 6);
      expect(result.topMatch!.endAyah, 7);
      expect(result.topMatch!.isMultiAyah, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 3: Long Recitations (> 64 characters triggering DP Fallback)
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 6: Query exceeding 64 chars uses _dpSearch and maintains high accuracy', () async {
      // Ayat Al-Kursi complete first clause
      final rawKursi = repo.getVerse(2, 255)!.textPhoneme;
      final longQuery = rawKursi.substring(0, 75);

      final stopwatch = Stopwatch()..start();
      final result = await controller.searchCandidates(longQuery);
      stopwatch.stop();

      // Myers DP fallback completes within ~20ms
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 255);
      expect(result.isUnique, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 4: Massive Repetition & Mutashabihat
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 7: "يا أيها الذين آمنوا" returns multiple candidates without false uniqueness', () async {
      // Appears 89 times in Quran
      final result = await controller.searchCandidates('ياءيهلذۦنءامنۥ');
      expect(result, isNotNull);
      expect(result!.candidates.length, greaterThanOrEqualTo(2));
      expect(result.isUnique, isFalse);
    });

    test('Scenario 8: "ويل يومئذ للمكذبين" preserves ambiguity across Surah 52 and Surah 77', () async {
      // Appears in At-Tur 52:11 and 10 times in Al-Mursalat 77
      final result = await controller.searchCandidates('ويلنيومءذنلمكذبۦن');
      expect(result, isNotNull);
      expect(result!.candidates.length, greaterThanOrEqualTo(2));
      // Ambiguity must be strictly preserved
      expect(result.isUnique, isFalse);
      expect(result.candidates.any((c) => c.surah == 77), isTrue);
      expect(result.candidates.any((c) => c.surah == 52), isTrue);
    });

    test('Scenario 9: Short generic phrase "قال رب" preserves ambiguity', () async {
      final result = await controller.searchCandidates('قالرب');
      if (result != null) {
        expect(result.isUnique, isFalse);
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 5: Controller State & Stream Lifecycle
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 10: processRealtime updates currentResult, clear() resets it', () async {
      // Realtime search updates currentResult
      await controller.processRealtime('قلهولاهءحد');
      expect(controller.currentResult.value, isNotNull);
      expect(controller.currentResult.value!.topMatch!.surah, 112);

      // Clear properly resets
      controller.clear();
      expect(controller.currentResult.value, isNull);
    });

    test('Scenario 11: Realtime streaming progression through partial speech chunks', () async {
      // Chunk 1: Short prefix
      final r1 = await controller.processRealtime('قلهو');
      expect(r1, isNull);

      // Chunk 2: Ambiguous middle
      await controller.processRealtime('قلهولاه');
      expect(controller.currentResult.value, isNotNull);
      expect(controller.currentResult.value!.isUnique, isFalse);

      // Chunk 3: Completed unique phrase
      final r3 = await controller.processRealtime('قلهولاهءحد');
      expect(r3, isNotNull);
      expect(r3!.surah, 112);
      expect(r3.ayah, 1);
      expect(r3.isUnique, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Scenario Group 6: Special Preamble Case - Mid-Verse Basmalah (Surah 27:30)
    // ─────────────────────────────────────────────────────────────────────────
    test('Scenario 12: Surah 27:30 containing Basmalah inside the verse text matches 27:30', () async {
      // "إِنَّهُ مِن سُلَيْمَانَ وَإِنَّهُ بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"
      final raw27_30 = repo.getVerse(27, 30)!.textPhoneme;
      final result = await controller.searchCandidates(raw27_30);
      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 27);
      expect(result.topMatch!.ayah, 30);
    });

    test('Scenario 13: Session epoch guard prevents stale async search from overwriting clear()', () async {
      // Trigger processRealtime without awaiting immediately
      final future = controller.processRealtime('قلهولاهءحد');
      // Immediately clear the session before or during the search execution
      controller.clear();
      expect(controller.currentResult.value, isNull);

      // Await the previous future: must return null because epoch changed
      final result = await future;
      expect(result, isNull);
      expect(controller.currentResult.value, isNull);
    });
  });
}
