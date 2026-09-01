import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Status of on-demand neural model and phoneme assets.
enum ModelDownloadStatus {
  notDownloaded,
  downloading,
  ready,
  error,
}

/// Utility for downloading, managing, and verifying neural ASR model and phoneme
/// assets on demand, avoiding the need to bundle ~85MB into the initial app binary.
class ModelDownloader {
  static const String defaultModelFileName = 'zipformer_p_arabic_v3.int8.onnx';
  static const String defaultTokensFileName = 'tokens.txt';
  static const String defaultPhonemesFileName = 'ordered_quran_phonemes.json';

  static const String defaultModelUrl =
      'https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/zipformer_p_arabic_v3.int8.onnx';
  static const String defaultTokensUrl =
      'https://raw.githubusercontent.com/Iam-Muslim/ReciteQuran/ReciteQuran-%D8%A7%D9%84%D8%AD%D9%85%D8%AF%D9%84%D9%84%D9%87/assets/model/tokens.txt';
  static const String defaultPhonemesUrl =
      'https://raw.githubusercontent.com/Iam-Muslim/ReciteQuran/ReciteQuran-%D8%A7%D9%84%D8%AD%D9%85%D8%AF%D9%84%D9%84%D9%87/assets/model/ordered_quran_phonemes.json';

  final String modelUrl;
  final String tokensUrl;
  final String phonemesUrl;
  final String? customStoragePath;

  ModelDownloader({
    this.modelUrl = defaultModelUrl,
    this.tokensUrl = defaultTokensUrl,
    this.phonemesUrl = defaultPhonemesUrl,
    this.customStoragePath,
  });

  /// Resolves the destination directory for on-demand recitation assets.
  Future<Directory> getStorageDirectory() async {
    if (customStoragePath != null) {
      final dir = Directory(customStoragePath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'recite_quran_assets'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Verifies whether all required neural model and phoneme files exist on disk.
  Future<bool> isModelReady() async {
    if (kIsWeb) return true;
    try {
      final dir = await getStorageDirectory();
      final modelFile = File(p.join(dir.path, defaultModelFileName));
      final tokensFile = File(p.join(dir.path, defaultTokensFileName));
      final phonemesFile = File(p.join(dir.path, defaultPhonemesFileName));

      final bool modelExists =
          await modelFile.exists() && (await modelFile.length()) > 10 * 1024 * 1024;
      final bool tokensExist =
          await tokensFile.exists() && (await tokensFile.length()) > 500;
      final bool phonemesExist =
          await phonemesFile.exists() && (await phonemesFile.length()) > 1024 * 1024;

      return modelExists && tokensExist && phonemesExist;
    } catch (_) {
      return false;
    }
  }

  /// Returns the absolute file path to the downloaded phoneme JSON.
  Future<String> getPhonemeFilePath() async {
    final dir = await getStorageDirectory();
    return p.join(dir.path, defaultPhonemesFileName);
  }

  /// Returns the absolute path to the directory containing model assets.
  Future<String> getModelDirectoryPath() async {
    final dir = await getStorageDirectory();
    return dir.path;
  }

  /// Downloads all required neural model and phoneme assets with streaming progress reporting.
  ///
  /// [onProgress] delivers `(progress: 0.0 -> 1.0, message: 'Downloading...')`.
  Future<bool> downloadAssets({
    void Function(double progress, String status)? onProgress,
    http.Client? client,
  }) async {
    if (kIsWeb) {
      onProgress?.call(1.0, 'Ready');
      return true;
    }

    final httpClient = client ?? http.Client();
    try {
      final dir = await getStorageDirectory();

      // 1. Download Tokens (~5 KB)
      onProgress?.call(0.02, 'Downloading tokens...');
      await _downloadFile(
        httpClient,
        tokensUrl,
        p.join(dir.path, defaultTokensFileName),
      );

      // 2. Download Phonemes JSON (~15 MB)
      onProgress?.call(0.05, 'Downloading phonemes metadata...');
      await _downloadFile(
        httpClient,
        phonemesUrl,
        p.join(dir.path, defaultPhonemesFileName),
      );

      // 3. Download ONNX Neural Model (~68 MB)
      onProgress?.call(0.20, 'Downloading neural acoustic model...');
      await _downloadFile(
        httpClient,
        modelUrl,
        p.join(dir.path, defaultModelFileName),
        onProgress: (ratio) {
          final mapped = 0.20 + (ratio * 0.80);
          onProgress?.call(mapped, 'Downloading neural acoustic model (${(ratio * 100).toInt()}%)...');
        },
      );

      onProgress?.call(1.0, 'Assets ready');
      return true;
    } catch (e) {
      onProgress?.call(0.0, 'Download failed: $e');
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Deletes downloaded model files from disk to free storage.
  Future<void> deleteAssets() async {
    final dir = await getStorageDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _downloadFile(
    http.Client client,
    String url,
    String targetPath, {
    void Function(double ratio)? onProgress,
  }) async {
    final tempPath = '$targetPath.tmp';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw HttpException('Failed to download $url (Status: ${response.statusCode})');
    }

    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;
    final sink = tempFile.openWrite();

    try {
      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }).asFuture();
      await sink.flush();
    } finally {
      await sink.close();
    }

    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetPath);
  }
}
