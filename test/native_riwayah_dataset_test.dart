import "dart:convert";
import "dart:io";
import "package:flutter_test/flutter_test.dart";
import "package:recite_quran/data/qiraat_ayah_mapper.dart";
import "package:recite_quran/data/quran_data.dart";
import "package:recite_quran/recite_quran.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Native Riwayah Dataset & In-Memory Loading Tests", () {
    const warshSampleJson = "{\"moshaf\":{\"rewaya\":\"warsh\",\"madd_monfasel_len\":6,\"madd_mottasel_len\":6},\"rule_names\":{\"1\":{\"ar\":\"المد الطبيعي\",\"en\":\"Normal Madd\"}},\"verses\":{\"1:1\":{\"aya_text\":\"الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ\",\"aya_phoneme\":\"لحمدُلِللَاهِرَببِلعَالَمِين\",\"aya_phonemes_list\":[\"الْحَمْدُ\",\"لِلَّهِ\",\"رَبِّ\",\"الْعَالَمِينَ\"],\"rules\":[]},\"1:2\":{\"aya_text\":\"الرَّحْمَٰنِ الرَّحِيمِ\",\"aya_phoneme\":\"ررَحمَٰنِرَّحِيم\",\"aya_phonemes_list\":[\"الرَّحْمَٰنِ\",\"الرَّحِيمِ\"],\"rules\":[]}}}";

    test("QuranMetadataService loads data directly from phonemeJsonString", () async {
      final service = QuranMetadataService(phonemeJsonString: warshSampleJson);
      expect(service.rawJson, isNull);

      await service.loadData();

      expect(service.rawJson, isNotNull);
      expect(service.datasetRiwayah, "warsh");
      expect(service.rawJson!["verses"]["1:1"]["aya_text"], "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ");
    });

    test("QuranRepository recognises native Warsh dataset and loads 1:1 without mapper distortion", () async {
      final service = QuranMetadataService(phonemeJsonString: warshSampleJson);
      final repository = QuranRepository(
        service,
        riwayah: QuranRiwayah.warsh,
      );

      await repository.loadSurahAsync(1);

      expect(repository.isNativeDataset, isTrue);
      expect(repository.isTajweedSupported, isTrue);

      final verses = repository.getSurah(1);
      expect(verses.length, 2);
      expect(verses[0].ayah, 1);
      expect(verses[0].textUthmani, "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ");
      expect(verses[1].ayah, 2);
      expect(verses[1].textUthmani, "الرَّحْمَٰنِ الرَّحِيمِ");
    });

    test("QuranRepository with native dataset bypasses mapper even if mapper is supplied", () async {
      final service = QuranMetadataService(phonemeJsonString: warshSampleJson);
      final fixtureFile = File("test/fixtures/warsh-to-hafs.json");
      final mapperJson = jsonDecode(await fixtureFile.readAsString()) as Map<String, dynamic>;
      final mapper = QiraatAyahMapper.fromJson(mapperJson, riwayah: QuranRiwayah.warsh);

      final repository = QuranRepository(
        service,
        ayahMapper: mapper,
        riwayah: QuranRiwayah.warsh,
      );

      await repository.loadSurahAsync(1);

      expect(repository.isNativeDataset, isTrue);
      final verses = repository.getSurah(1);
      // Because dataset is native Warsh, it loads 1:1 instead of mapping through Hafs:
      expect(verses[0].ayah, 1);
      expect(verses[0].textUthmani, "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ");
    });

    test("Tajweed evaluation flag is enabled for Warsh when isTajweedSupported is true", () async {
      final service = QuranMetadataService(phonemeJsonString: warshSampleJson);
      final repository = QuranRepository(
        service,
        riwayah: QuranRiwayah.warsh,
      );
      await repository.loadSurahAsync(1);

      final tracker = ReciteQuran(
        repository: repository,
        isTajweed: true,
      );

      expect(repository.isTajweedSupported, isTrue);
      expect(tracker.isTajweed, isTrue);

      tracker.setTajweedMode(false);
      expect(tracker.isTajweed, isFalse);

      tracker.setTajweedMode(true);
      expect(tracker.isTajweed, isTrue);

      tracker.dispose();
    });
    test("Full generated Warsh dataset loads from disk file and parses Surah 1 & 114 properly", () async {
      final file = File("/Users/m97chahboun/Development/tathbeet/tathbeet_backend/riwayat_assets/warsh_phonemes.json");
      if (!await file.exists()) return;

      final service = QuranMetadataService(phonemeFilePath: file.path);
      final repository = QuranRepository(
        service,
        riwayah: QuranRiwayah.warsh,
      );

      await repository.loadSurahAsync(1);
      final surah1 = repository.getSurah(1);
      expect(surah1.length, 7);
      expect(surah1[0].ayah, 1);
      expect(surah1[0].textUthmani.contains("اِ۬لْحَمْدُ"), isTrue);
      expect(surah1[6].ayah, 7);
      expect(surah1[6].textUthmani.contains("غَيْرِ"), isTrue);

      final words1 = repository.getSurahWords(1);
      expect(words1.length, 25);
      expect(words1[0].uthmani, "اِ۬لْحَمْدُ");
      expect(words1[0].phoneme, "ءَلحَمدُ");
      expect(words1[1].uthmani, "لِلهِ");
      expect(words1[1].phoneme, "لِللَااهِ");
      expect(words1[2].uthmani, "رَبِّ");
      expect(words1[2].phoneme, "رَببِ");
      expect(words1[3].uthmani, "اِ۬لْعَٰلَمِينَ");
      expect(words1[3].phoneme, "لعَاالَمِۦۦۦۦن");

      await repository.loadSurahAsync(114);
      final surah114 = repository.getSurah(114);
      expect(surah114.length, 6);
      expect(surah114[0].textUthmani.contains("قُلَ اَعُوذُ"), isTrue);
    });
  });
}
