import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'qiraat_ayah_mapper.dart';

/// Status of on-demand ayah mapping JSON assets.
enum AyahMappingDownloadStatus {
  notDownloaded,
  downloading,
  ready,
  error,
}

/// Utility for checking, downloading, and caching Riwayah ayah mapping JSON files
/// on-demand from the official verified repository releases.
///
/// Avoids bloating package and application binary size with multi-megabyte JSON mapping tables.
class AyahMappingDownloader {
  static const String defaultBaseUrl =
      'https://github.com/M97Chahboun/quran-database-verifier/releases/download/riwayat-v1.0';

  final String baseUrl;
  final String? customStoragePath;

  AyahMappingDownloader({
    this.baseUrl = defaultBaseUrl,
    this.customStoragePath,
  });

  /// Resolves the local storage directory for on-demand mapping files.
  Future<Directory> getStorageDirectory() async {
    if (customStoragePath != null) {
      final dir = Directory(customStoragePath!);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'recite_quran_assets', 'mappings'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the expected local file for a Riwayah mapping.
  Future<File> getMappingFile(QuranRiwayah riwayah) async {
    final dir = await getStorageDirectory();
    return File(p.join(dir.path, '${riwayah.id}-to-hafs.json'));
  }

  /// Checks if mapping is available on disk or if it is Kufi (which needs no file).
  Future<bool> isMappingReady(QuranRiwayah riwayah) async {
    if (riwayah.countingSystem == QuranCountingSystem.kufi) return true;
    try {
      final file = await getMappingFile(riwayah);
      if (await file.exists() && (await file.length()) > 50) return true;
      // Also check app-level documents/mappings folder if exists
      final appDir = await getApplicationDocumentsDirectory();
      final altFile = File(p.join(appDir.path, 'mappings', '${riwayah.id}-to-hafs.json'));
      return await altFile.exists() && (await altFile.length()) > 50;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the mapping JSON file for a given Riwayah from the remote release URL.
  Future<File?> downloadMapping(
    QuranRiwayah riwayah, {
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    if (riwayah.countingSystem == QuranCountingSystem.kufi) {
      onProgress?.call(1.0, 'Kufi requires no external mapping');
      return null;
    }

    final targetFile = await getMappingFile(riwayah);
    final fileName = '${riwayah.id}-to-hafs.json';
    final downloadUrl = '$baseUrl/$fileName';

    final httpClient = client ?? http.Client();
    try {
      onProgress?.call(0.0, 'Downloading ayah mapping for ${riwayah.nameEn}...');
      final request = http.Request('GET', Uri.parse(downloadUrl))..followRedirects = true;
      final response = await httpClient.send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw HttpException('Failed to download $downloadUrl (HTTP ${response.statusCode})');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final tempFile = File('${targetFile.path}.tmp');
      if (await tempFile.exists()) await tempFile.delete();

      final sink = tempFile.openWrite();
      await response.stream.listen((chunk) {
        if (isCancelled?.call() == true) {
          throw HttpException('Download cancelled by user.');
        }
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(
            receivedBytes / totalBytes,
            'Downloading mapping (${((receivedBytes / totalBytes) * 100).toInt()}%)...',
          );
        }
      }).asFuture().timeout(const Duration(minutes: 2));

      await sink.flush();
      await sink.close();

      if (await targetFile.exists()) await targetFile.delete();
      await tempFile.rename(targetFile.path);

      onProgress?.call(1.0, 'Mapping ready');
      return targetFile;
    } catch (e) {
      onProgress?.call(0.0, 'Download failed: $e');
      rethrow;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Deletes a cached mapping file from disk.
  Future<void> deleteMapping(QuranRiwayah riwayah) async {
    final file = await getMappingFile(riwayah);
    if (await file.exists()) await file.delete();
  }
}
