import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/riwaya_descriptor.dart';
import 'package:recite_quran/data/verse_alignment.dart';
import 'package:recite_quran/data/verse_key_map.dart';

void main() {
  group('VerseAlignment & Exceptions Tests', () {
    const hafs = RiwayaDescriptor(
      id: 'hafs',
      nameAr: 'حفص عن عاصم',
      nameEn: 'Hafs an Asim',
      sourceDatabase: 'hafs.sqlite',
      profileId: 'hafs',
      phonemeArtifact: 'hafs_phonemes.json',
      dataVersion: 1,
      tajweedVerified: true,
    );

    const warsh = RiwayaDescriptor(
      id: 'warsh',
      nameAr: 'ورش عن نافع',
      nameEn: 'Warsh an Nafi',
      sourceDatabase: 'warsh.sqlite',
      profileId: 'warsh',
      phonemeArtifact: 'warsh_phonemes.json',
      dataVersion: 1,
      tajweedVerified: false,
    );

    final hafsAlignment = VerseAlignment(hafs);
    final warshAlignment = VerseAlignment(warsh);

    test('Regular verse has 1:1 index alignment', () {
      expect(hafsAlignment.artifactWordIndex(1, 1, 0), 0);
      expect(hafsAlignment.artifactWordIndex(1, 1, 3), 3);
      expect(hafsAlignment.expectedArtifactWordCount(1, 1, 4), 4);
    });

    test('Surah At-Tawbah 9:1 drops 2 leading database header words in Hafs', () {
      expect(hafsAlignment.artifactWordIndex(9, 1, 0), 0);
      expect(hafsAlignment.artifactWordIndex(9, 1, 1), 0);
      expect(hafsAlignment.artifactWordIndex(9, 1, 2), 0); // 2 - 2 = 0
      expect(hafsAlignment.artifactWordIndex(9, 1, 3), 1); // 3 - 2 = 1
      expect(hafsAlignment.expectedArtifactWordCount(9, 1, 11), 9);
    });

    test('Warsh alignment has no exceptions by default', () {
      expect(warshAlignment.artifactWordIndex(9, 1, 2), 2);
      expect(warshAlignment.expectedArtifactWordCount(9, 1, 11), 11);
    });
  });
}
