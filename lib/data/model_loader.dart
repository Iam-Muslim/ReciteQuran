// lib/data/model_loader.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL ASSET & ON-DEMAND DOWNLOAD MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages loading, caching, and on-demand downloading of the 72MB ONNX model.
class ModelLoader {
  static const String defaultModelFileName = 'zipformer_p_arabic_v3.int8.onnx';

  /// Default GitHub release URL for the acoustic model.
  static const String defaultRemoteModelUrl =
      'https://github.com/Iam-Muslim/ReciteQuran/releases/download/v1.0.0/zipformer_p_arabic_v3.int8.onnx';

  /// Returns the local destination file for the cached ONNX model.
  static Future<File> getCachedModelFile([String fileName = defaultModelFileName]) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory modelDir = Directory('${appDir.path}/quran_voice_models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return File('${modelDir.path}/$fileName');
  }

  /// Checks whether the ONNX model is already present on local storage.
  static Future<bool> isModelCached([String fileName = defaultModelFileName]) async {
    final File file = await getCachedModelFile(fileName);
    return file.existsSync() && (await file.length()) > 1024 * 1024 * 10; // At least 10MB
  }

  /// Downloads the ONNX model from [url] with progress reporting (0.0 to 1.0).
  ///
  /// Returns the absolute path of the downloaded file.
  static Future<String> downloadModel({
    String url = defaultRemoteModelUrl,
    String fileName = defaultModelFileName,
    void Function(double progress)? onProgress,
  }) async {
    final File targetFile = await getCachedModelFile(fileName);
    final File tempFile = File('${targetFile.path}.tmp');

    if (tempFile.existsSync()) {
      await tempFile.delete();
    }

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url));
      final HttpClientResponse response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('Failed to download model (HTTP ${response.statusCode})', uri: Uri.parse(url));
      }

      final int totalBytes = response.contentLength;
      int receivedBytes = 0;

      final IOSink sink = tempFile.openWrite();

      await response.listen((List<int> chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      // Rename temp file to target file on complete download
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      return targetFile.path;
    } catch (e) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Extracts an asset bundled inside the app's `assets/` to writable local storage.
  static Future<String> loadFromAssetBundle({
    required String assetPath,
    String? outputFileName,
  }) async {
    final String fName = outputFileName ?? assetPath.split('/').last;
    final File targetFile = await getCachedModelFile(fName);

    if (!targetFile.existsSync() || await targetFile.length() == 0) {
      final byteData = await rootBundle.load(assetPath);
      await targetFile.writeAsBytes(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
    }

    return targetFile.path;
  }

  /// Automatically resolves or downloads the ONNX model path.
  ///
  /// 1. If [customFilePath] exists, returns it.
  /// 2. If already cached in documents directory, returns cached path.
  /// 3. If [bundledAssetPath] is given, extracts it from assets.
  /// 4. Otherwise, downloads on-demand from [downloadUrl].
  static Future<String> prepareModelPath({
    String? customFilePath,
    String? bundledAssetPath,
    String downloadUrl = defaultRemoteModelUrl,
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (customFilePath != null && File(customFilePath).existsSync()) {
      return customFilePath;
    }

    if (await isModelCached()) {
      final File cached = await getCachedModelFile();
      return cached.path;
    }

    if (bundledAssetPath != null) {
      try {
        return await loadFromAssetBundle(assetPath: bundledAssetPath);
      } catch (_) {
        // Fallback to download if asset is not bundled
      }
    }

    return await downloadModel(
      url: downloadUrl,
      onProgress: onDownloadProgress,
    );
  }
}
