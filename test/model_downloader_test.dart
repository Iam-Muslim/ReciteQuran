import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recite_quran/data/model_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelDownloader Tests', () {
    late Directory tempDir;
    late ModelDownloader downloader;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('downloader_test_');
      downloader = ModelDownloader(customStoragePath: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('isModelReady returns false when assets are missing', () async {
      final isReady = await downloader.isModelReady();
      expect(isReady, isFalse);
    });

    test('isModelReady returns true when all 3 files are present with sufficient size', () async {
      final modelFile = File('${tempDir.path}/${ModelDownloader.defaultModelFileName}');
      final tokensFile = File('${tempDir.path}/${ModelDownloader.defaultTokensFileName}');
      final phonemesFile = File('${tempDir.path}/${ModelDownloader.defaultPhonemesFileName}');

      // Write mock files with required minimum sizes
      await modelFile.writeAsBytes(List.filled(11 * 1024 * 1024, 0));
      await tokensFile.writeAsBytes(List.filled(1000, 0));
      await phonemesFile.writeAsBytes(List.filled(2 * 1024 * 1024, 0));

      final isReady = await downloader.isModelReady();
      expect(isReady, isTrue);

      final modelDirPath = await downloader.getModelDirectoryPath();
      expect(modelDirPath, equals(tempDir.path));

      final phonemeFilePath = await downloader.getPhonemeFilePath();
      expect(phonemeFilePath, equals('${tempDir.path}/${ModelDownloader.defaultPhonemesFileName}'));
    });

    test('deleteAssets removes the storage directory', () async {
      final dummyFile = File('${tempDir.path}/test.txt');
      await dummyFile.writeAsString('hello');

      await downloader.deleteAssets();
      expect(await tempDir.exists(), isFalse);
    });
  });
}
