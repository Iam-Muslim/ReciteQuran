import "package:flutter_test/flutter_test.dart";
import "package:recite_quran/recite_quran.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Hafs & Warsh Tajweed Detection Unit Tests", () {
    // ── Hafs Sample Dataset ──
    const hafsPhonemesJson = "{\"moshaf\":{\"rewaya\":\"hafs\"},\"rule_names\":{\"1\":{\"ar\":\"المد الطبيعي\",\"en\":\"Normal Madd\"},\"5\":{\"ar\":\"المد العارض للسكون\",\"en\":\"Aared Madd\"}},\"verses\":{\"1:1\":{\"aya_text\":\"بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ\",\"aya_phoneme\":\"بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم\",\"aya_phonemes_list\":[\"بِسمِ\",\"للَااهِ\",\"ررَحمَاانِ\",\"ررَحِۦۦۦۦم\"],\"rules\":[[11,1,2],[25,1,2],[36,5,4]]}}}";

    // ── Warsh Sample Dataset ──
    const warshPhonemesJson = "{\"moshaf\":{\"rewaya\":\"warsh\",\"madd_monfasel_len\":6,\"madd_mottasel_len\":6},\"rule_names\":{\"1\":{\"ar\":\"المد الطبيعي\",\"en\":\"Normal Madd\"},\"5\":{\"ar\":\"المد العارض للسكون\",\"en\":\"Aared Madd\"}},\"verses\":{\"1:1\":{\"aya_text\":\"الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ\",\"aya_phoneme\":\"لحمدُلِللَاهِرَببِلعَالَمِين\",\"aya_phonemes_list\":[\"الْحَمْدُ\",\"لِلَّهِ\",\"رَبِّ\",\"الْعَالَمِينَ\"],\"rules\":[[25,5,4]]},\"114:1\":{\"aya_text\":\"قُلْ أَعُوذُ بِرَبِّ النَّاسِ\",\"aya_phoneme\":\"قُلَاعُوذُبِرَببِننننَاس\",\"aya_phonemes_list\":[\"قُل\",\"ءَعُۥۥذُ\",\"بِرَببِ\",\"ننننَااااس\"],\"rules\":[]}}}";

    test("Hafs: Tajweed is supported, rules are parsed and attached to words", () async {
      final service = QuranMetadataService(phonemeJsonString: hafsPhonemesJson);
      final repository = QuranRepository(service, riwayah: QuranRiwayah.hafs);
      await repository.loadSurahAsync(1);

      // 1. Verify Tajweed capability
      expect(repository.isTajweedSupported, isTrue, reason: "Hafs must support Tajweed");
      expect(repository.isNativeDataset, isTrue);

      // 2. Verify word-level rules extraction
      final words = repository.getSurahWords(1);
      expect(words.length, 4);

      // Word 0: بِسْمِ (no rule)
      expect(words[0].rules.where((r) => r.ruleId == 1 || r.ruleId == 5), isEmpty);

      // Word 1: ٱللَّهِ (has Normal Madd rule 1)
      expect(words[1].rules.any((r) => r.ruleId == 1), isTrue);

      // Word 2: ٱلرَّحْمَـٰنِ (has Normal Madd rule 1)
      expect(words[2].rules.any((r) => r.ruleId == 1), isTrue);

      // Word 3: ٱلرَّحِيمِ (has Aared Madd rule 5)
      expect(words[3].rules.any((r) => r.ruleId == 5), isTrue);
      expect(words[3].rules.firstWhere((r) => r.ruleId == 5).goldenLen, 4);

      // 3. Verify ReciteQuran tracker activates Tajweed for Hafs
      final tracker = ReciteQuran(repository: repository, isTajweed: true);
      expect(tracker.isTajweed, isTrue, reason: "Tracker must enable Tajweed for Hafs");
      tracker.dispose();
    });

    test("Warsh: Tajweed is supported, rules and Ghunnah are parsed and attached to words", () async {
      final service = QuranMetadataService(phonemeJsonString: warshPhonemesJson);
      final repository = QuranRepository(service, riwayah: QuranRiwayah.warsh);
      await repository.loadSurahAsync(1);
      await repository.loadSurahAsync(114);

      // 1. Verify Tajweed capability
      expect(repository.isTajweedSupported, isTrue, reason: "Warsh must support Tajweed");
      expect(repository.isNativeDataset, isTrue);

      // 2. Verify word-level rules extraction for Surah 1
      final surah1Words = repository.getSurahWords(1);
      expect(surah1Words.length, 4);

      // Word 3: الْعَالَمِينَ (has Aared Madd rule 5)
      expect(surah1Words[3].rules.any((r) => r.ruleId == 5), isTrue);
      expect(surah1Words[3].rules.firstWhere((r) => r.ruleId == 5).nameAr, "المد العارض للسكون");

      // 3. Verify Mushaddad Ghunnah detection in Warsh (114:1 النَّاسِ has نننن)
      final surah114Words = repository.getSurahWords(114);
      final nasWord = surah114Words.last; // النَّاسِ
      expect(nasWord.rules.any((r) => r.ruleId == 10), isTrue,
          reason: "Mushaddad Noon Ghunnah must be detected from phonemes");

      // 4. Verify ReciteQuran tracker activates Tajweed for Warsh
      final tracker = ReciteQuran(repository: repository, isTajweed: true);
      expect(tracker.isTajweed, isTrue, reason: "Tracker must enable Tajweed for Warsh");

      // Can toggle off and on dynamically
      tracker.setTajweedMode(false);
      expect(tracker.isTajweed, isFalse);
      tracker.setTajweedMode(true);
      expect(tracker.isTajweed, isTrue);

      tracker.dispose();
    });

    test("Non-Hafs non-Warsh Riwayah without rules disables Tajweed", () async {
      // Qalun without rules in dataset
      const plainJson = "{\"moshaf\":{\"rewaya\":\"qaloon\"},\"verses\":{\"1:1\":{\"aya_text\":\"بِسْمِ اللَّهِ\",\"aya_phoneme\":\"بِسمِللَاه\",\"aya_phonemes_list\":[\"بِسمِ\",\"للَاه\"]}}}";
      final service = QuranMetadataService(phonemeJsonString: plainJson);
      final repository = QuranRepository(service, riwayah: QuranRiwayah.qaloon);
      await repository.loadSurahAsync(1);

      expect(repository.isTajweedSupported, isFalse, reason: "Qalun without rules must not enable Tajweed");

      final tracker = ReciteQuran(repository: repository, isTajweed: true);
      expect(tracker.isTajweed, isFalse, reason: "Tracker must keep Tajweed disabled for unsupported riwayah");
      tracker.dispose();
    });

    test("Tajweed acoustic duration verification logic (Madd and Ghunnah)", () {
      const normalMadd = NormalMaddRule();
      const aaredMadd = AaredMaddRule();
      const ghunnah = MushaddadGhunnahRule();

      // Normal Madd (~1.5 Harakat = 0.375s)
      expect(normalMadd.checkDurationStatus(0.10), TajweedDurationStatus.defect);
      expect(normalMadd.checkDurationStatus(0.40), TajweedDurationStatus.valid);
      expect(normalMadd.checkDurationStatus(1.50), TajweedDurationStatus.surplus);

      // Aared Madd (4 Harakat = 1.00s)
      expect(aaredMadd.checkDurationStatus(0.50), TajweedDurationStatus.defect);
      expect(aaredMadd.checkDurationStatus(1.20), TajweedDurationStatus.valid);

      // Ghunnah (2 Harakat = 0.50s)
      expect(ghunnah.checkDurationStatus(0.20), TajweedDurationStatus.defect);
      expect(ghunnah.checkDurationStatus(0.60), TajweedDurationStatus.valid);
    });
  });
}
