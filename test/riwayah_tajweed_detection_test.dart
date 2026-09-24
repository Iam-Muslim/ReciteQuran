import "package:flutter_test/flutter_test.dart";
import "package:recite_quran/recite_quran.dart";
import "package:recite_quran/tracking/tajweed/error_explainer.dart";
import "package:recite_quran/tracking/tajweed/tajweed_rules.dart";
import "package:recite_quran/tracking/word/dictation_matcher.dart";
import "package:recite_quran/tracking/word/dictation_sequencer.dart";

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
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 2: MATHEMATICAL MODELS FOR ALL TAJWEED RULES
  // ═══════════════════════════════════════════════════════════════════════════

  group("Tajweed Rules Mathematical Duration & Tolerance Tests", () {
    const hBase = 0.20; // Standard Harakah Base = 200ms

    test("Rule 1: Normal Madd (المد الطبيعي) — 1.2 Harakat", () {
      const rule = NormalMaddRule();
      expect(rule.name.ar, "المد الطبيعي");
      expect(rule.name.en, "Normal Madd");
      expect(rule.goldenLen, 1.2);

      // Lower bound: min required duration is 0.70 * hBase = 140ms
      expect(rule.checkDurationStatus(0.00, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.10, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.05, hBase), TajweedDurationStatus.defect);

      // Valid range: passes natural human recitation (140ms - 600ms)
      expect(rule.checkDurationStatus(0.15, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.24, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.40, hBase), TajweedDurationStatus.valid);

      // Surplus: excessive elongation beyond +2.5 Harakat headroom
      expect(rule.checkDurationStatus(0.90, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 2: Monfasel Madd (المد المنفصل) — 4 Harakat", () {
      const rule = MonfaselMaddRule();
      expect(rule.name.ar, "المد المنفصل");
      expect(rule.goldenLen, 4);
      expect(rule.getRequiredDuration(hBase), closeTo(0.80, 0.001));

      // 20% margin: req threshold = 0.80 * 0.80 = 0.64s
      expect(rule.checkDurationStatus(0.40, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.60, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.65, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.80, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.20, hBase), TajweedDurationStatus.valid);

      // Upper bound: req (0.64) + 4.0 * 0.20 (0.80) = 1.44s
      expect(rule.checkDurationStatus(1.50, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 3: Mottasel Madd (المد المتصل) — 4 Harakat", () {
      const rule = MottaselMaddRule();
      expect(rule.name.ar, "المد المتصل");
      expect(rule.goldenLen, 4);

      expect(rule.checkDurationStatus(0.50, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.70, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.00, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.60, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 4: Mottasel Madd at Pause (المد المتصل وقفا) — 4 Harakat", () {
      const rule = MottaselMaddPauseRule();
      expect(rule.name.ar, "المد المتصل وقفا");
      expect(rule.goldenLen, 4);

      expect(rule.checkDurationStatus(0.50, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.80, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.10, hBase), TajweedDurationStatus.valid);
    });

    test("Rule 5: Aared Madd (المد العارض للسكون) — Qasr (2), Tawassut (4), Tool (6)", () {
      const rule = AaredMaddRule();
      expect(rule.name.ar, "المد العارض للسكون");
      expect(rule.goldenLen, 4);

      // Defect: shorter than allowed Qasr (0.70 * hBase = 140ms)
      expect(rule.checkDurationStatus(0.00, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.10, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.13, hBase), TajweedDurationStatus.defect);

      // 1. Qasr Face (2 Harakat ~ 0.40s, accepts >= 0.14s)
      expect(rule.checkDurationStatus(0.20, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.35, hBase), TajweedDurationStatus.valid);

      // 2. Tawassut Face (4 Harakat ~ 0.80s)
      expect(rule.checkDurationStatus(0.80, hBase), TajweedDurationStatus.valid);

      // 3. Tool Face (6 Harakat ~ 1.20s - 1.80s)
      expect(rule.checkDurationStatus(1.20, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.60, hBase), TajweedDurationStatus.valid);

      // Surplus: exceeds Tool (6 * 0.20 = 1.2s) + 4 Harakat headroom (0.8s) = 2.0s
      expect(rule.checkDurationStatus(2.10, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 6: Lazem Madd (المد اللازم) — 6 Harakat", () {
      const rule = LazemMaddRule();
      expect(rule.name.ar, "المد اللازم");
      expect(rule.goldenLen, 6);
      expect(rule.getRequiredDuration(hBase), closeTo(1.20, 0.001));

      // 20% margin: req threshold = 1.20 * 0.80 = 0.96s
      expect(rule.checkDurationStatus(0.80, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.95, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(1.00, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.20, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.60, hBase), TajweedDurationStatus.valid);

      // Upper bound: req (0.96) + 4.0 * 0.20 (0.80) = 1.76s
      expect(rule.checkDurationStatus(2.10, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 7: Leen Madd (مد اللين) — 4 Harakat", () {
      const rule = LeenMaddRule();
      expect(rule.name.ar, "مد اللين");
      expect(rule.goldenLen, 4);

      expect(rule.checkDurationStatus(0.50, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.70, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(1.00, hBase), TajweedDurationStatus.valid);
    });

    test("Rule 10: Mushaddad Ghunnah (النون والميم المشددة) — 2 Harakat", () {
      const ruleNoon = MushaddadGhunnahRule(
        name: LangName(ar: "النون المشددة", en: "Mushaddad Noon"),
      );
      const ruleMeem = MushaddadGhunnahRule(
        name: LangName(ar: "الميم المشددة", en: "Mushaddad Meem"),
      );

      expect(ruleNoon.name.ar, "النون المشددة");
      expect(ruleMeem.name.ar, "الميم المشددة");
      expect(ruleNoon.goldenLen, 2);
      expect(ruleNoon.getRequiredDuration(hBase), closeTo(0.40, 0.001));

      // 20% margin: req = 0.40 * 0.80 = 0.32s
      expect(ruleNoon.checkDurationStatus(0.20, hBase), TajweedDurationStatus.defect);
      expect(ruleNoon.checkDurationStatus(0.30, hBase), TajweedDurationStatus.defect);
      expect(ruleNoon.checkDurationStatus(0.35, hBase), TajweedDurationStatus.valid);
      expect(ruleNoon.checkDurationStatus(0.50, hBase), TajweedDurationStatus.valid);

      // Surplus: 0.32 + 2.5 * 0.20 (0.50) = 0.82s
      expect(ruleNoon.checkDurationStatus(0.95, hBase), TajweedDurationStatus.surplus);
    });

    test("Rule 9: Shaddah (الشدة) — Consonant closure holding", () {
      const rule = ShaddahRule();
      expect(rule.name.ar, "الشدة");
      expect(rule.goldenLen, 1);
      expect(rule.getRequiredDuration(hBase), closeTo(0.13, 0.001));

      // 20% margin: req = 0.13 * 0.80 = 0.104s
      expect(rule.checkDurationStatus(0.08, hBase), TajweedDurationStatus.defect);
      expect(rule.checkDurationStatus(0.12, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.25, hBase), TajweedDurationStatus.valid);
      expect(rule.checkDurationStatus(0.45, hBase), TajweedDurationStatus.valid);
    });

    test("Adaptive tempo scaling (Fast Hadr vs Slow Tahqiq)", () {
      const aared = AaredMaddRule();

      // Fast recitation (Hadr): hBase = 150ms
      expect(aared.checkDurationStatus(0.11, 0.15), TajweedDurationStatus.valid);
      expect(aared.checkDurationStatus(0.08, 0.15), TajweedDurationStatus.defect);

      // Slow recitation (Tahqiq): hBase = 250ms
      expect(aared.checkDurationStatus(0.20, 0.25), TajweedDurationStatus.valid);
      expect(aared.checkDurationStatus(0.12, 0.25), TajweedDurationStatus.defect);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 3: ERROR EXPLAINER INTEGRATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group("ErrorExplainer Span Evaluation Unit Tests", () {
    test("Zero or missing duration does NOT produce false defects", () {
      final deenRule = const WordTajweedRule(
        ruleId: 5,
        nameAr: "المد العارض للسكون",
        nameEn: "Aared Madd",
        goldenLen: 4,
      );

      // Aligned ASR with 0.0 duration (e.g. streaming timestamp lag)
      final trace = [
        PhonemeGroupAlignment(opType: 'match', refIdx: 0, predIdx: 0), // د
        PhonemeGroupAlignment(opType: 'delete', refIdx: 1, predIdx: -1), // د
        PhonemeGroupAlignment(opType: 'match', refIdx: 2, predIdx: 1), // ِ
        PhonemeGroupAlignment(opType: 'match', refIdx: 3, predIdx: 2), // ۦ
        PhonemeGroupAlignment(opType: 'delete', refIdx: 4, predIdx: -1), // ۦ
        PhonemeGroupAlignment(opType: 'delete', refIdx: 5, predIdx: -1), // ۦ
        PhonemeGroupAlignment(opType: 'delete', refIdx: 6, predIdx: -1), // ۦ
        PhonemeGroupAlignment(opType: 'match', refIdx: 7, predIdx: 3), // ن
      ];

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: trace,
        fullPhonemes: "ددِۦۦۦۦن",
        wordBoundaries: [0, 8],
        currentAsrText: "دِۦن",
        trackingTimestamps: [0.0, 0.0, 0.0, 0.0], // All zeros!
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
        expectedWordRules: [deenRule],
      );

      // Must be empty: never falsely claim a 0.00s defect!
      expect(errors, isEmpty);
    });

    test("Quranic glyph equivalence (Small Yaa ۦ vs Regular Yaa ي) avoids false substitution", () {
      final aaredRule = const WordTajweedRule(
        ruleId: 5,
        nameAr: "المد العارض للسكون",
        nameEn: "Aared Madd",
        goldenLen: 4,
      );

      // ASR predicted regular 'ي', reference has 'ۦ'
      final trace = [
        PhonemeGroupAlignment(opType: 'match', refIdx: 0, predIdx: 0), // د
        PhonemeGroupAlignment(opType: 'match', refIdx: 1, predIdx: 1), // د
        PhonemeGroupAlignment(opType: 'match', refIdx: 2, predIdx: 2), // ِ
        PhonemeGroupAlignment(opType: 'match', refIdx: 3, predIdx: 3), // ۦ matched to ي!
        PhonemeGroupAlignment(opType: 'delete', refIdx: 4, predIdx: -1),
        PhonemeGroupAlignment(opType: 'delete', refIdx: 5, predIdx: -1),
        PhonemeGroupAlignment(opType: 'delete', refIdx: 6, predIdx: -1),
        PhonemeGroupAlignment(opType: 'match', refIdx: 7, predIdx: 4), // ن
      ];

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: trace,
        fullPhonemes: "ددِۦۦۦۦن",
        wordBoundaries: [0, 8],
        currentAsrText: "ددِين",
        trackingTimestamps: [0.15, 0.15, 0.15, 0.85, 0.15], // 850ms on 'ي'
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
        expectedWordRules: [aaredRule],
      );

      // Must be completely free of errors (both Tajweed and substitution)
      expect(errors, isEmpty);
    });

    test("Quranic glyph equivalence (Small Waw ۥ vs Regular Waw و)", () {
      expect(PhoneticCostEngine.isEquivalentGlyph('و'.codeUnitAt(0), 'ۥ'.codeUnitAt(0)), isTrue);
      expect(PhoneticCostEngine.isEquivalentGlyph('ي'.codeUnitAt(0), 'ۦ'.codeUnitAt(0)), isTrue);
      expect(PhoneticCostEngine.isEquivalentGlyph('ن'.codeUnitAt(0), 'ں'.codeUnitAt(0)), isTrue);
      expect(PhoneticCostEngine.isEquivalentGlyph('م'.codeUnitAt(0), '۾'.codeUnitAt(0)), isTrue);
    });

    test("Shaddah consonant doubling bypasses acoustic duration deficiency", () {
      final shaddahRule = const WordTajweedRule(
        ruleId: 9,
        nameAr: "الشدة",
        nameEn: "Shaddah",
        goldenLen: 1,
      );

      // Reciter clearly doubled the letter in ASR (رَببِ -> رَببِ)
      final trace = [
        PhonemeGroupAlignment(opType: 'match', refIdx: 0, predIdx: 0), // ر
        PhonemeGroupAlignment(opType: 'match', refIdx: 1, predIdx: 1), // َ
        PhonemeGroupAlignment(opType: 'match', refIdx: 2, predIdx: 2), // ب
        PhonemeGroupAlignment(opType: 'match', refIdx: 3, predIdx: 3), // ب
        PhonemeGroupAlignment(opType: 'match', refIdx: 4, predIdx: 4), // ِ
      ];

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: trace,
        fullPhonemes: "رَببِ",
        wordBoundaries: [0, 5],
        currentAsrText: "رَببِ",
        trackingTimestamps: [0.05, 0.05, 0.05, 0.05, 0.05], // Even if each frame is brief
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
        expectedWordRules: [shaddahRule],
      );

      expect(errors, isEmpty, reason: "Doubled consonant satisfies Shaddah requirement");
    });

    test("Valid Waqf sukoon at word boundary does not trigger Tashkeel error", () {
      final trace = [
        PhonemeGroupAlignment(opType: 'match', refIdx: 0, predIdx: 0), // د
        PhonemeGroupAlignment(opType: 'match', refIdx: 1, predIdx: 1), // ِ
        PhonemeGroupAlignment(opType: 'match', refIdx: 2, predIdx: 2), // ي
        PhonemeGroupAlignment(opType: 'match', refIdx: 3, predIdx: 3), // ن
        PhonemeGroupAlignment(opType: 'delete', refIdx: 4, predIdx: -1), // ِ omitted due to Waqf!
      ];

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: trace,
        fullPhonemes: "دِينِ",
        wordBoundaries: [0, 5],
        currentAsrText: "دِين",
        trackingTimestamps: [0.15, 0.15, 0.80, 0.15],
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
      );

      expect(errors, isEmpty, reason: "Terminal Waqf without Kasra is standard Arabic pause");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 4: STREAMING CHARACTER DURATION SYNCHRONIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  group("Streaming Character Duration Pro-Rating Tests", () {
    test("Compound tokens expand correctly so character indices stay 100% in sync", () {
      // Simulate Sherpa tokens including compound glyphs: ['بَ', 'ل', 'كِ']
      final tokens = ['بَ', 'ل', 'كِ'];
      final tokenDurations = [0.30, 0.15, 0.40];

      final String asrString = tokens.join('');
      expect(asrString, 'بَلكِ');
      expect(asrString.length, 5); // 5 characters, but 3 tokens!

      // Expand duration across characters
      final List<double> charDurations = [];
      for (int i = 0; i < tokens.length; i++) {
        final tok = tokens[i];
        final dur = tokenDurations[i] / (tok.isEmpty ? 1 : tok.length);
        for (int c = 0; c < tok.length; c++) {
          charDurations.add(dur);
        }
      }

      // Verification: charDurations length matches asrString length exactly!
      expect(charDurations.length, asrString.length);
      expect(charDurations[0], closeTo(0.15, 0.001)); // 'ب'
      expect(charDurations[1], closeTo(0.15, 0.001)); // 'َ'
      expect(charDurations[2], closeTo(0.15, 0.001)); // 'ل'
      expect(charDurations[3], closeTo(0.20, 0.001)); // 'ك'
      expect(charDurations[4], closeTo(0.20, 0.001)); // 'ِ'

      // Sum of character durations matches sum of token durations exactly
      final double totalTokenDur = tokenDurations.reduce((a, b) => a + b);
      final double totalCharDur = charDurations.reduce((a, b) => a + b);
      expect(totalCharDur, closeTo(totalTokenDur, 0.001));
    });
  });
}
