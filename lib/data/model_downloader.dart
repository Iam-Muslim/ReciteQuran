import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Status of on-demand neural model assets.
enum ModelDownloadStatus {
  notDownloaded,
  downloading,
  ready,
  error,
}

/// Utility for downloading, managing, and verifying the neural ASR model asset
/// on demand, avoiding the need to bundle ~69MB into the initial app binary.
/// Tokens and phonemes remain bundled inside the app assets for offline stability.
class ModelDownloader {
  static const String defaultModelFileName = 'zipformer_p_arabic_v3.int8.onnx';

  static const String defaultModelUrl =
      'https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/zipformer_p_arabic_v3.int8.onnx';

  final String modelUrl;
  final String? customStoragePath;

  ModelDownloader({
    this.modelUrl = defaultModelUrl,
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

  /// Verifies whether the neural model file exists on disk and meets the size threshold.
  Future<bool> isModelReady() async {
    if (kIsWeb) return true;
    try {
      final dir = await getStorageDirectory();
      final modelFile = File(p.join(dir.path, defaultModelFileName));
      return await modelFile.exists() && (await modelFile.length()) > 10 * 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  /// Returns the absolute path to the directory containing model assets.
  Future<String> getModelDirectoryPath() async {
    final dir = await getStorageDirectory();
    return dir.path;
  }

  /// Returns the absolute path to the downloaded model file.
  Future<String> getModelFilePath() async {
    final dir = await getStorageDirectory();
    return p.join(dir.path, defaultModelFileName);
  }

  /// Downloads the neural model asset with streaming progress reporting.
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

      onProgress?.call(0.0, 'Downloading neural acoustic model...');
      await _downloadFile(
        httpClient,
        modelUrl,
        p.join(dir.path, defaultModelFileName),
        onProgress: (ratio) {
          onProgress?.call(ratio, 'Downloading neural acoustic model (${(ratio * 100).toInt()}%)...');
        },
      );

      onProgress?.call(1.0, 'Model ready');
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
