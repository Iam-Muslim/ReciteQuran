import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/riwaya_descriptor.dart';
import 'package:recite_quran/data/riwaya_registry.dart';

void main() {
  group('RiwayaRegistry & Descriptor Tests', () {
    test('loads successfully from json string', () async {
      final file = File('assets/json/riwayat.json');
      final jsonStr = await file.readAsString();
      final registry = RiwayaRegistry.fromJsonString(jsonStr);

      expect(registry.all.length, greaterThanOrEqualTo(2));
      final hafs = registry.byId('hafs');
      expect(hafs.id, 'hafs');
      expect(hafs.nameAr, 'حفص عن عاصم');
      expect(hafs.tajweedVerified, isTrue);

      final warsh = registry.byId('warsh');
      expect(warsh.id, 'warsh');
      expect(warsh.nameAr, 'ورش عن نافع');
      expect(warsh.tajweedVerified, isFalse);
    });

    test('throws ArgumentError on unknown riwaya id', () {
      final registry = RiwayaRegistry.fromJsonString(jsonEncode({
        'riwayat': [
          {
            'id': 'hafs',
            'nameAr': 'حفص',
            'nameEn': 'Hafs',
            'sourceDatabase': 'hafs.sqlite',
            'profileId': 'hafs',
            'phonemeArtifact': 'hafs_phonemes.json',
            'dataVersion': 1,
            'tajweedVerified': true,
          }
        ]
      }));

      expect(() => registry.byId('non_existent'), throwsArgumentError);
      expect(registry.tryById('non_existent'), isNull);
    });
  });
}
