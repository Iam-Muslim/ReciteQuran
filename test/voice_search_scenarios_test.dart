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
    // Inject the synchronously loaded search index into controller
    // so tests run instantly without background isolate asset bundle mocking
    controller.preloadIndex();
  });

  group('Voice Search Real-World Scenarios', () {
    test('Scenario 1: User live trace - Basmalah + partial "قُلْ هُوَ اللَّهُ" matches Al-Ikhlas (NOT 59:22)', () async {
      // User's exact live ASR engine trace:
      // ASR: بِسمِللَااهِررَحمَاانِررَحِۦۦمقُل         لهُوَللَااهُ
      final result = await controller.searchCandidates(
        'بِسمِللَااهِررَحمَاانِررَحِۦۦمقُل         لهُوَللَااهُ',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 112);
      expect(result.topMatch!.ayah, 1);
      // Ensure Surah 59:22 is NOT the top match or falsely matched
      expect(result.topMatch!.surah, isNot(59));
    });

    test('Scenario 1b: processRealtime with user live trace returns AnchorResult for 112:1', () async {
      // Live realtime stream call as called in main.dart:
      await controller.processRealtime(
        'بِسمِللَااهِررَحمَاانِررَحِۦۦمقُل         لهُوَللَااهُ',
      );
      print('CurrentResult: ${controller.currentResult.value?.topMatch?.surah}:${controller.currentResult.value?.topMatch?.ayah} isUnique: ${controller.currentResult.value?.isUnique}');
      for (final c in controller.currentResult.value?.candidates ?? []) {
        print('  candidate: ${c.surah}:${c.ayah} dist: ${c.distance}');
      }
      expect(controller.currentResult.value, isNotNull);
      expect(controller.currentResult.value!.topMatch!.surah, 112);
    });

    test('Scenario 1c: Complete recitation with "أَحَدٌ" resolves uniquely in processRealtime', () async {
      // Completed phrase with "أحد" as emitted by ASR:
      final anchor = await controller.processRealtime(
        'بِسمِللَااهِررَحمَاانِررَحِۦۦمقُل         لهُوَللَااهُءَحَد',
      );

      expect(anchor, isNotNull);
      expect(anchor!.surah, 112);
      expect(anchor.ayah, 1);
    });

    test('Scenario 2: Basmalah + Surah 113:1 correctly matches Al-Falaq', () async {
      // Spoken: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ"
      final result = await controller.searchCandidates(
        'بسملاهرحمانرحۦمقلءعۥذبربلفلق',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 113);
      expect(result.topMatch!.ayah, 1);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 3: Basmalah only correctly matches Surah 1:1', () async {
      // Spoken: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ"
      final result = await controller.searchCandidates(
        'بسملاهرحمانرحۦم',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 1);
      expect(result.topMatch!.ayah, 1);
    });

    test('Scenario 4: Istiadha + Surah 112:1 correctly matches Al-Ikhlas', () async {
      // Spoken: "أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ قُلْ هُوَ اللَّهُ أَحَدٌ"
      final result = await controller.searchCandidates(
        'ءعۥذبلاهمنشيطانرجۦمقلهولاهءحد',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 112);
      expect(result.topMatch!.ayah, 1);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 5: User live trace for 2:183 - Ayyouha allatheena aamanoo kutiba alaykum as-siyaam', () async {
      // User's exact live ASR engine trace:
      // ASR: ءَييُهَااللَذِۦۦنَ     ءَاامَنُۥۥكُتِبَعَلَيكُمصصِيَاامَ
      const asrInput = 'ءَييُهَااللَذِۦۦنَ     ءَاامَنُۥۥكُتِبَعَلَيكُمصصِيَاامَ';
      print('Normalized query: "${PhoneticSearch.normalizeQuery(asrInput)}" (len=${PhoneticSearch.normalizeQuery(asrInput).length})');

      final result = await controller.searchCandidates(asrInput);

      print('Result: surah=${result?.topMatch?.surah}, ayah=${result?.topMatch?.ayah}, isUnique=${result?.isUnique}, candidates=${result?.candidates.length}');
      for (final c in result?.candidates ?? []) {
        print('  candidate: ${c.surah}:${c.ayah} dist: ${c.distance} score: ${c.score}');
      }

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 183);
      expect(result.isUnique, isTrue);

      // Verify stopSearch returns anchor for 2:183 without being blocked
      final anchor = await controller.stopSearch(asrInput, requireUnique: true);
      expect(anchor, isNotNull);
      expect(anchor!.surah, 2);
      expect(anchor.ayah, 183);
    });

    test('Scenario 6: "كتب عليكم القصاص" resolves uniquely to 2:178', () async {
      // Spoken: "يَا أَيُّهَا الَّذِينَ آمَنُوا كُتِبَ عَلَيْكُمُ الْقِصَاصُ"
      final result = await controller.searchCandidates(
        'ياءيهلذۦنءامنۥكتبعليكملقصاص',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 178);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 7: Leading noise/hesitation prefix recovery', () async {
      // Spoken with noise/cough prefix: "قلهذوه قُلْ أَعُوذُ بِرَبِّ النَّاسِ"
      final result = await controller.searchCandidates(
        'قلهذوهقلءعۥذبربلناس',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 114);
      expect(result.topMatch!.ayah, 1);
    });

    test('Scenario 8: Mutashabihat "الم" preserves ambiguity (isUnique == false)', () async {
      final result = await controller.searchCandidates('ءلفلامۦم');

      expect(result, isNotNull);
      expect(result!.candidates.length, greaterThanOrEqualTo(2));
      expect(result.isUnique, isFalse);
      expect(result.isAmbiguous, isTrue);
    });

    test('Scenario 9: Mid-verse substring alignment (Ayat Al-Kursi)', () async {
      // Spoken: "لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ"
      final result = await controller.searchCandidates(
        'لاتءخذهۥسنتولانوم',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 255);
      expect(result.topMatch!.startWordIdx, greaterThan(0));
    });

    test('Scenario 10: Non-Quranic conversational phrases rejected', () async {
      final result = await controller.searchCandidates(
        'شكرنجزۦلن',
      );

      expect(result, isNull);
    });

    test('Scenario 11: Surah Al-Mulk opening with Basmalah matches 67:1', () async {
      // Spoken: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ تَبَارَكَ الَّذِي بِيَدِهِ الْمُلْكُ"
      final result = await controller.searchCandidates(
        'بسملاهرحمانرحۦمتباركلذۦبيدهلملك',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 67);
      expect(result.topMatch!.ayah, 1);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 12: Surah An-Naba opening matches 78:1', () async {
      // Spoken: "عَمَّ يَتَسَاءَلُونَ عَنِ النَّبَإِ الْعَظِيمِ"
      final result = await controller.searchCandidates(
        'عميتساءلۥنعننبءلعظۦم',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 78);
      expect(result.topMatch!.ayah, 1);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 13: Repetitive Ayah "فبأي آلاء ربكما تكذبان" preserves ambiguity across Surah 55', () async {
      // Spoken: "فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ"
      final result = await controller.searchCandidates(
        'فبءياءالاءربكماتكذبان',
      );

      expect(result, isNotNull);
      expect(result!.candidates.length, greaterThanOrEqualTo(2));
      expect(result.topMatch!.surah, 55);
      expect(result.isUnique, isFalse);
      expect(result.isAmbiguous, isTrue);
    });

    test('Scenario 14: Mid-verse recitation "آمن الرسول بما أنزل إليه" matches 2:285', () async {
      // Spoken: "آمَنَ الرَّسُولُ بِمَا أُنزِلَ إِلَيْهِ مِن رَّبِّهِ"
      final result = await controller.searchCandidates(
        'ءامنرسۥلبماءںزلءليهمربهۦ',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 285);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 15: Throat clear + Basmalah + Ayah matches Al-Mulk 67:1', () async {
      // Spoken: Cough/throat-clearing "هممم" + Basmalah + "تبارك الذي بيده الملك"
      final result = await controller.searchCandidates(
        'همممبسملاهرحمانرحۦمتباركلذۦبيدهلملك',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 67);
      expect(result.topMatch!.ayah, 1);
    });

    test('Scenario 16: Single-word verse "الرحمن" matches 55:1 from dataset phonemes', () async {
      // Using ideal dataset phoneme output: "ءَررَحمَاااان"
      final rawPh = repo.getVerse(55, 1)!.textPhoneme;
      final result = await controller.searchCandidates(rawPh);

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.candidates.any((c) => c.surah == 55 && c.ayah == 1), isTrue);
    });

    test('Scenario 17: Istiadha + Basmalah + Ayah matches An-Nas 114:1', () async {
      // Reciting both opening preambles:
      // "أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم قل أعوذ برب الناس"
      final result = await controller.searchCandidates(
        'ءعۥذبلاهمنشيطانرجۦمبسملاهرحمانرحۦمقلءعۥذبربناس',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 114);
      expect(result.topMatch!.ayah, 1);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 18: Istiadha alone preserves non-unique ambiguity (no premature auto-jump to 16:98)', () async {
      // Reciting only "أعوذ بالله من الشيطان الرجيم"
      final result = await controller.searchCandidates(
        'ءعۥذبلاهمنشيطانرجۦم',
      );

      expect(result, isNotNull);
      // Safeguard: must not be considered unique to prevent jumping to An-Nahl 16:98
      expect(result!.isUnique, isFalse);

      // In stopSearch with requireUnique, returns null so app does not auto-jump
      final anchor = await controller.stopSearch('ءعۥذبلاهمنشيطانرجۦم', requireUnique: true);
      expect(anchor, isNull);
    });

    test('Scenario 19: Mutashabihat progressive narrowing from "الم" to 2:1-2 vs 3:1-2', () async {
      // 1. Ambiguous opening "الم"
      final resAmbiguous = await controller.searchCandidates('ءلفلامۦم');
      expect(resAmbiguous!.isUnique, isFalse);

      // 2. Narrowed with Baqarah continuation: "الم ذلك الكتاب لا ريب فيه"
      final resBaqarah = await controller.searchCandidates('ءلفلامۦمذالكلكتابلاريبفۦه');
      expect(resBaqarah, isNotNull);
      expect(resBaqarah!.topMatch!.surah, 2);
      expect(resBaqarah.isUnique, isTrue);

      // 3. Narrowed with Aal-Imran continuation: "الم الله لا إله إلا هو الحي القيوم"
      final resImran = await controller.searchCandidates('ءلفلامۦملاهلاءلاهءلاهولحيلقيۥم');
      expect(resImran, isNotNull);
      expect(resImran!.topMatch!.surah, 3);
      expect(resImran.isUnique, isTrue);
    });

    test('Scenario 20: Disjointed letters: كهيعص (19:1) unique, حم ambiguous across 40-46', () async {
      // "كهيعص" uniquely identifies Maryam 19:1
      final rawMaryam = repo.getVerse(19, 1)!.textPhoneme;
      final resMaryam = await controller.searchCandidates(rawMaryam);
      expect(resMaryam, isNotNull);
      expect(resMaryam!.topMatch!.surah, 19);
      expect(resMaryam.topMatch!.ayah, 1);
      expect(resMaryam.isUnique, isTrue);

      // "حم" is ambiguous across Ha-Meem surahs (40, 41, 42, 43, 44, 45, 46)
      final resHaMeem = await controller.searchCandidates('حامۦم');
      expect(resHaMeem, isNotNull);
      expect(resHaMeem!.candidates.length, greaterThanOrEqualTo(2));
      expect(resHaMeem.isUnique, isFalse);
    });

    test('Scenario 21: Ayat Al-Kursi tail substring matches 2:255', () async {
      // Spoken: "وَلَا يَئُودُهُ حِفْظُهُمَا وَهُوَ الْعَلِيُّ الْعَظِيمُ"
      final result = await controller.searchCandidates(
        'ولايءۥدهۥحفظهماوهولعليلعظۦم',
      );

      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 255);
      expect(result.isUnique, isTrue);
    });

    test('Scenario 22: Ayat Ad-Dayn (2:282, longest verse in Quran) opening matches 2:282', () async {
      // Spoken: "يَا أَيُّهَا الَّذِينَ آمَنُوا إِذَا تَدَايَنتُم بِدَيْنٍ إِلَىٰ أَجَلٍ مُّسَمًّى فَاكْتُبُوهُ"
      final rawDayn = repo.getVerse(2, 282)!.textPhoneme;
      final result = await controller.searchCandidates(rawDayn.substring(0, 50));

      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 2);
      expect(result.topMatch!.ayah, 282);
    });

    test('Scenario 23: Ayat An-Nur (24:35) opening matches 24:35', () async {
      // Spoken: "اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ مَثَلُ نُورِهِ كَمِشْكَاةٍ"
      final rawNur = repo.getVerse(24, 35)!.textPhoneme;
      final result = await controller.searchCandidates(rawNur.substring(0, 45));

      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 24);
      expect(result.topMatch!.ayah, 35);
    });

    test('Scenario 24: Khawateem Al-Hashr (59:22) opening matches 59:22', () async {
      // Spoken: "هُوَ اللَّهُ الَّذِي لَا إِلَٰهَ إِلَّا هُوَ عَالِمُ الْغَيْبِ وَالشَّهَادَةِ"
      final rawHashr = repo.getVerse(59, 22)!.textPhoneme;
      final result = await controller.searchCandidates(rawHashr.substring(0, 45));

      expect(result, isNotNull);
      expect(result!.topMatch!.surah, 59);
      expect(result.topMatch!.ayah, 22);
    });

    test('Scenario 25: Juz Amma short surahs match accurately', () async {
      // Al-Kawthar 108:1: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ"
      final rKawthar = await controller.searchCandidates('ءناءعطيناكلكوثر');
      expect(rKawthar!.topMatch!.surah, 108);

      // Al-Asr 103:1-2: "وَالْعَصْرِ إِنَّ الْإِنسَانَ لَفِي خُسْرٍ"
      final rAsr = await controller.searchCandidates('ولعصرءنلءنساللفۦخسر');
      expect(rAsr!.topMatch!.surah, 103);

      // Al-Qadr 97:1: "إِنَّا أَنزَلْنَاهُ فِي لَيْلَةِ الْقَدْرِ"
      final rQadr = await controller.searchCandidates('ءناءںزلناهفۦليلتلقدر');
      expect(rQadr!.topMatch!.surah, 97);

      // Ash-Sharh 94:1: "أَلَمْ نَشْرَحْ لَكَ صَدْرَكَ"
      final rSharh = await controller.searchCandidates('ءلمنشرحلكصدرك');
      expect(rSharh!.topMatch!.surah, 94);

      // Al-Fatihah 1:2: "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ"
      final rFatihah = await controller.searchCandidates('ءلحمدللاهربلعالمۦن');
      expect(rFatihah!.topMatch!.surah, 1);
      expect(rFatihah.topMatch!.ayah, 2);
    });

    test('Scenario 26: Stuttering & word repetition recovers target Ayah', () async {
      // Reciter stutters: "قل هو ... قل هو الله أحد"
      final result = await controller.searchCandidates(
        'قلهوقلهولاهءحد',
      );

      expect(result, isNotNull);
      expect(result!.candidates, isNotEmpty);
      expect(result.topMatch!.surah, 112);
      expect(result.topMatch!.ayah, 1);
    });

    test('Scenario 27: Conversational non-Quranic Arabic and English completely rejected', () async {
      // Non-Quranic Arabic phrases that do not exist in Quran:
      expect(await controller.searchCandidates('كۦفحالكياءخۦليومءںشاءلاهتكۥنبخير'), isNull);
      expect(await controller.searchCandidates('صباحلخيروسرۥرعللجمۦع'), isNull);

      // English conversational phrase:
      expect(await controller.searchCandidates('hello testing voice recognition one two'), isNull);

      // Short input (< 4 chars):
      expect(await controller.searchCandidates('نعم'), isNull);
    });

    test('Scenario 28: stopSearch requireUnique safeguards against ambiguous auto-navigation', () async {
      // 1. Ambiguous query with requireUnique: true -> returns null (safe, no auto-jump)
      final anchorBlocked = await controller.stopSearch('ءلفلامۦم', requireUnique: true);
      expect(anchorBlocked, isNull);

      // 2. Ambiguous query with requireUnique: false -> returns anchor with candidates preserved
      final anchorAllowed = await controller.stopSearch('ءلفلامۦم', requireUnique: false);
      expect(anchorAllowed, isNotNull);
      expect(controller.currentResult.value!.candidates.length, greaterThanOrEqualTo(2));

      // 3. Unique query with requireUnique: true -> returns anchor directly
      final anchorUnique = await controller.stopSearch('قلهولاهءحد', requireUnique: true);
      expect(anchorUnique, isNotNull);
      expect(anchorUnique!.surah, 112);
      expect(anchorUnique.ayah, 1);
    });
  });
}
