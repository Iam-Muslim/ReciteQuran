import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/quran_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QuranMetadataService loads data from phonemeFilePath on disk', () async {
    final tempDir = await Directory.systemTemp.createTemp('quran_test_');
    final tempPhoneme = File('${tempDir.path}/test_phonemes.json');
    await tempPhoneme.writeAsString('''{
      "ayahs": {
        "1:1": {
          "uthmani": "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
          "phoneme": "بِسمِ لللَّهِ ررَحمَٰنِ ررَحِيمِ",
          "phoneme_words": ["بِسمِ", "لللَّهِ", "ررَحمَٰنِ", "ررَحِيمِ"]
        }
      }
    }''');

    final service = QuranMetadataService(phonemeFilePath: tempPhoneme.path);
    await service.loadData();

    expect(service.rawJson, isNotNull);
    final ayahs = service.rawJson!['ayahs'] as Map<String, dynamic>;
    expect(ayahs.containsKey('1:1'), isTrue);

    await tempDir.delete(recursive: true);
  });
}
