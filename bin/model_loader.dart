// bin/model_loader.dart
import 'dart:async';
import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL ASSET MANUAL DOWNLOADER & PUBSPEC CONFIGURATOR (DEVELOPER CLI TOOL)
// ═══════════════════════════════════════════════════════════════════════════════

/// Manages manual downloading of the ONNX acoustic model into project assets
/// and automatic configuration of pubspec.yaml.
class ModelLoader {
  /// Default ONNX model filename.
  static const String defaultModelFileName = 'zipformer_p_arabic_v3.int8.onnx';

  /// GitHub release download URL for the acoustic model.
  static const String remoteModelUrl =
      'https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/zipformer_p_arabic_v3.int8.onnx';

  /// Downloads the ONNX model to `assets/model/` in [projectDirectory] and updates `pubspec.yaml`.
  static Future<void> downloadModelToAssets({
    Directory? projectDirectory,
  }) async {
    final Directory projectDir = projectDirectory ?? Directory.current;
    final File pubspecFile = File('${projectDir.path}/pubspec.yaml');

    if (!await pubspecFile.exists()) {
      stderr.writeln(' Error: pubspec.yaml not found in ${projectDir.path}');
      stderr.writeln(
        'Please run this command from the root of your Flutter project.',
      );
      exit(1);
    }

    final Directory modelDir = Directory('${projectDir.path}/assets/model');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
      stdout.writeln('📁 Created directory: assets/model/');
    }

    final File targetFile = File('${modelDir.path}/$defaultModelFileName');
    final File tempFile = File('${targetFile.path}.tmp');

    stdout.writeln('====================================================');
    stdout.writeln(' 📖 ReciteQuran Model Asset Downloader');
    stdout.writeln('====================================================');
    stdout.writeln('🌐 Downloading ONNX model...');
    stdout.writeln('   Source: $remoteModelUrl');
    stdout.writeln('   Target: assets/model/$defaultModelFileName');

    final HttpClient client = HttpClient();
    client.autoUncompress = true;

    try {
      Uri currentUri = Uri.parse(remoteModelUrl);
      HttpClientResponse? response;
      int redirectCount = 0;

      while (redirectCount < 5) {
        final HttpClientRequest request = await client.getUrl(currentUri);
        response = await request.close();

        if (response.isRedirect ||
            response.statusCode == HttpStatus.movedPermanently ||
            response.statusCode == HttpStatus.movedTemporarily ||
            response.statusCode == HttpStatus.seeOther ||
            response.statusCode == HttpStatus.temporaryRedirect ||
            response.statusCode == HttpStatus.permanentRedirect) {
          final String? location = response.headers.value(
            HttpHeaders.locationHeader,
          );
          if (location == null) break;
          currentUri = Uri.parse(location);
          redirectCount++;
          continue;
        }
        break;
      }

      if (response == null || response.statusCode != HttpStatus.ok) {
        stderr.writeln(
          ' Download failed: HTTP ${response?.statusCode ?? 'No response'}',
        );
        exit(1);
      }

      final int totalBytes = response.contentLength;
      int receivedBytes = 0;
      final IOSink sink = tempFile.openWrite();

      await response.listen((List<int> chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final double progress = receivedBytes / totalBytes;
          final int barWidth = 30;
          final int filledWidth = (progress * barWidth).clamp(0, barWidth).toInt();
          final String bar = '█' * filledWidth + '░' * (barWidth - filledWidth);
          final String percent = (progress * 100).toStringAsFixed(1).padLeft(5);
          final String mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final String mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

          stdout.write('\r   [$bar] $percent% ($mbReceived MB / $mbTotal MB)');
        }
      }).asFuture();

      await sink.flush();
      await sink.close();
      stdout.writeln();

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      final String finalMb = ((await targetFile.length()) / (1024 * 1024)).toStringAsFixed(1);
      stdout.writeln(' Model saved ($finalMb MB) -> assets/model/$defaultModelFileName');
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      stderr.writeln(' Error during model download: $e');
      exit(1);
    } finally {
      client.close();
    }

    // Update pubspec.yaml
    stdout.writeln(' Configuring pubspec.yaml assets...');
    try {
      final String content = await pubspecFile.readAsString();
      final String updatedContent = _injectAssetEntry(
        content,
        'assets/model/$defaultModelFileName',
      );

      if (content != updatedContent) {
        await pubspecFile.writeAsString(updatedContent);
        stdout.writeln(
          ' Added "assets/model/$defaultModelFileName" under flutter: assets: in pubspec.yaml',
        );
      } else {
        stdout.writeln(' assets/model/ is already declared in pubspec.yaml');
      }
    } catch (e) {
      stdout.writeln(' Could not auto-update pubspec.yaml: $e');
      stdout.writeln('Please manually add to pubspec.yaml:');
      stdout.writeln('flutter:');
      stdout.writeln('  assets:');
      stdout.writeln('    - assets/model/$defaultModelFileName');
    }

    stdout.writeln('====================================================');
    stdout.writeln('  Complete! The model is ready for 100% offline use.');
    stdout.writeln('====================================================');
  }

  static String _injectAssetEntry(String yamlContent, String assetEntry) {
    if (yamlContent.contains(assetEntry) ||
        yamlContent.contains('assets/model/')) {
      return yamlContent;
    }

    final lines = yamlContent.split('\n');
    int flutterIndex = -1;
    int assetsIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (RegExp(r'^flutter:\s*').hasMatch(line)) {
        flutterIndex = i;
      } else if (flutterIndex != -1 &&
          RegExp(r'^\s\sassets:\s*').hasMatch(line)) {
        assetsIndex = i;
      }
    }

    if (flutterIndex == -1) {
      return '$yamlContent\nflutter:\n  assets:\n    - $assetEntry\n';
    } else if (assetsIndex == -1) {
      lines.insert(flutterIndex + 1, '  assets:\n    - $assetEntry');
      return lines.join('\n');
    } else {
      lines.insert(assetsIndex + 1, '    - $assetEntry');
      return lines.join('\n');
    }
  }
}

/// CLI Entry point for: `dart run recite_quran:model_loader`
void main(List<String> args) async {
  await ModelLoader.downloadModelToAssets();
}
