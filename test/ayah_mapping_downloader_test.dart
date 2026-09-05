import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recite_quran/recite_quran.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapping_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AyahMappingDownloader Tests', () {
    test('Kufi riwayat are always ready without external files', () async {
      final downloader = AyahMappingDownloader(customStoragePath: tempDir.path);
      expect(await downloader.isMappingReady(QuranRiwayah.hafs), isTrue);
      expect(await downloader.isMappingReady(QuranRiwayah.shubah), isTrue);
    });

    test('Non-Kufi riwayah reports not ready before download', () async {
      final downloader = AyahMappingDownloader(customStoragePath: tempDir.path);
      expect(await downloader.isMappingReady(QuranRiwayah.susi), isFalse);
    });

    test('downloadMapping downloads and verifies JSON file accurately', () async {
      final fakeJson = jsonEncode({
        '_rawi': 'susi',
        '_source': 'basri',
        'surahs': {
          '1': {
            'source_ayah_count': 6,
            'hafs_ayah_count': 7,
            'ayahs': {
              '1': {'hafs_ayah': 1, 'status': 'mapped'},
            },
          },
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('susi-to-hafs.json')) {
          return http.Response(fakeJson, 200, headers: {
            'content-type': 'application/json',
          });
        }
        return http.Response('Not Found', 404);
      });

      final downloader = AyahMappingDownloader(
        customStoragePath: tempDir.path,
      );

      double reportedProgress = 0.0;
      final file = await downloader.downloadMapping(
        QuranRiwayah.susi,
        client: mockClient,
        onProgress: (p, s) {
          reportedProgress = p;
        },
      );

      expect(file, isNotNull);
      expect(await file!.exists(), isTrue);
      expect(reportedProgress, 1.0);
      expect(await downloader.isMappingReady(QuranRiwayah.susi), isTrue);

      // Verify QiraatAyahMapper.load uses this downloaded file seamlessly
      final mapper = await QiraatAyahMapper.load(
        QuranRiwayah.susi,
        customStoragePath: tempDir.path,
        downloadIfMissing: false,
      );

      expect(mapper.riwayah, QuranRiwayah.susi);
      expect(mapper.getSourceAyahCount(1), 6);
      expect(mapper.getHafsAyahs(1, 1), [1]);
    });
  });
}
