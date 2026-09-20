// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import '../utils/debug_logger.dart';

class TranscriptionResult {
  final String text;
  final bool isFinal;
  final int startTime;
  final List<String> tokens;
  final List<double> timestamps;
  final int streamEpoch;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.streamEpoch = 0,
  });
}

@JS('isWasmModuleLoaded')
external JSBoolean _isWasmModuleLoaded();

@JS('writeSherpaAssetToVFS')
external JSBoolean _writeSherpaAssetToVFS(
  JSString filename,
  JSUint8Array bytes,
);

@JS('initSherpaRecognizer')
external JSBoolean _initSherpaRecognizer();

@JS('fetchSherpaModel')
external JSPromise _fetchSherpaModel(JSString url);

@JS('isSherpaModelCached')
external JSPromise _isSherpaModelCached();

@JS('resetOfficialSherpaBuffer')
external void _resetOfficialSherpaBuffer();

@JS('feedSherpaAudioChunk')
external void _feedSherpaAudioChunk(JSFloat32Array chunk, JSBoolean isFinal);

/// Web-specific implementation of SherpaEngine using Official Sherpa WebAssembly JS.
class SherpaEngine {
  /// Where the caller keeps a downloaded model, honoured by the IO engine.
  ///
  /// The web engine loads its model from the bundle and ignores this, but the
  /// parameter has to exist: sherpa_engine.dart exports one of the two by
  /// conditional import, so their constructors have to match or any app that
  /// passes it fails to compile for the web.
  final String? assetOverrideDir;

  SherpaEngine({this.assetOverrideDir});

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  Future<void>? _initFuture;
  int _currentStreamEpoch = 0;

  bool get isInitialized => _isInitialized;
  int get currentStreamEpoch => _currentStreamEpoch;

  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<bool> isModelCached() async {
    try {
      final res = await _isSherpaModelCached().toDart;
      if (res != null && res is JSBoolean) {
        return res.toDart;
      }
    } catch (_) {}
    return false;
  }

  Future<void> preExtractAssets() async {
    // Handled in initialize for Web
  }

  Future<void> initialize() {
    if (_isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {

    final JSFunction jsOnResult = (JSString jsonStr, JSBoolean isFinal) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr.toDart);
        final tokensList = List<String>.from(data['tokens'] ?? []);
        final text = data['text'] ?? '';
        final isFinalDart = isFinal.toDart;

        DebugLogger.logSimple(
          'SherpaWeb',
          '📥 ASR Event: text="$text", tokens=${tokensList.length}, isFinal=$isFinalDart, epoch=$_currentStreamEpoch',
        );

        _outputController.add(
          TranscriptionResult(
            text: text,
            isFinal: isFinalDart,
            startTime: DateTime.now().millisecondsSinceEpoch,
            tokens: tokensList,
            timestamps: List<double>.from(
              (data['timestamps'] ?? []).map((e) => (e as num).toDouble()),
            ),
            streamEpoch: _currentStreamEpoch,
          ),
        );
      } catch (e) {
        DebugLogger.logSimple('SherpaDart', 'Error parsing JSON result: $e');
      }
    }.toJS;

    globalContext.setProperty('dartSherpaOnResult'.toJS, jsOnResult);

    try {
      const String modelFileName = 'zipformer_p_arabic_v3.int8.onnx';
      // Downloaded on demand from a CORS-enabled host and cached by the browser;
      // it is not bundled with the web deploy. Override at build time with
      // --dart-define=RECITATION_MODEL_URL=... to point at a different mirror.
      //
      // GitHub release assets do not work here: github.com redirects to
      // release-assets.githubusercontent.com and neither hop sends an
      // Access-Control-Allow-Origin header, so the browser blocks the fetch.
      const String modelUrl = String.fromEnvironment(
        'RECITATION_MODEL_URL',
        defaultValue:
            'https://tathbeet.pythonanywhere.com/api/recitation/model/',
      );
      DebugLogger.logSimple(
        'SherpaDart',
        'Fetching ONNX model from $modelUrl (in parallel with WASM load)...',
      );

      // Start fetching the model in parallel with WASM memory compilation
      final modelFuture = _fetchSherpaModel(modelUrl.toJS).toDart;

      // Concurrently wait for the WASM engine to start (with a 120s timeout for mobile devices)
      int waitCount = 0;
      while (!_isWasmModuleLoaded().toDart) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
        if (waitCount > 1200) {
          DebugLogger.logSimple('SherpaDart', 'TIMEOUT waiting for WASM module!');
          return;
        }
      }

      DebugLogger.logSimple(
        'SherpaDart',
        'WASM Memory loaded. Awaiting model bytes...',
      );

      final modelRaw = await modelFuture;
      if (modelRaw == null) {
        DebugLogger.logSimple('SherpaDart', 'Model bytes returned null! Cannot initialize.');
        return;
      }
      final JSUint8Array modelBytes = modelRaw as JSUint8Array;

      _writeSherpaAssetToVFS(modelFileName.toJS, modelBytes);
      DebugLogger.logSimple('SherpaDart', 'Model written to VFS.');

      Uint8List tokensBytes;
      try {
        ByteData rawData;
        try {
          rawData = await rootBundle.load(
            'packages/recite_quran/assets/model/tokens.txt',
          );
        } catch (_) {
          rawData = await rootBundle.load('assets/model/tokens.txt');
        }
        final rawBytes = rawData.buffer.asUint8List();
        final text = utf8.decode(rawBytes, allowMalformed: true);
        if (text.startsWith('<!DOCTYPE') || text.length > 50000) {
          throw Exception('Loaded HTML instead of tokens');
        }
        tokensBytes = rawBytes;
      } catch (e) {
        DebugLogger.logSimple(
          'SherpaDart',
          'Failed loading tokens bundle ($e), using embedded fallback.',
        );
        tokensBytes = Uint8List.fromList(utf8.encode(_fallbackTokensText));
      }

      _writeSherpaAssetToVFS(
        'quran_tokens.txt'.toJS,
        tokensBytes.toJS,
      );
      DebugLogger.logSimple(
        'SherpaDart',
        'Tokens (${tokensBytes.length} bytes) written to VFS.',
      );

      DebugLogger.logSimple('SherpaDart', 'Initializing Sherpa Recognizer...');
      bool success = _initSherpaRecognizer().toDart;

      if (success) {
        DebugLogger.logSimple(
          'SherpaDart',
          'Sherpa WebAssembly initialized successfully!',
        );
        _isInitialized = true;
      } else {
        DebugLogger.logSimple(
          'SherpaDart',
          'FATAL JS ERROR: Failed to create recognizer engine!',
        );
        _initFuture = null;
      }
    } catch (e) {
      DebugLogger.logSimple('SherpaDart', 'FATAL ERROR loading models: $e');
      _initFuture = null;
    }
  }

  bool transcribe(Float32List audioChunk, {bool isFinal = false}) {
    if (!_isInitialized) return false;
    try {
      _feedSherpaAudioChunk(audioChunk.toJS, isFinal.toJS);
      return true;
    } catch (e) {
      DebugLogger.logSimple('SherpaWeb', 'transcribe error: $e');
      return false;
    }
  }

  void resetBuffer() {
    _currentStreamEpoch++;
    try {
      _resetOfficialSherpaBuffer();
    } catch (_) {}
    DebugLogger.logSimple(
      'SherpaWeb',
      '🔄 resetBuffer() executed (epoch: $_currentStreamEpoch)',
    );
  }

  void flushThenReset() {
    _currentStreamEpoch++;
    try {
      _resetOfficialSherpaBuffer();
    } catch (_) {}
    DebugLogger.logSimple(
      'SherpaWeb',
      '🔄 flushThenReset() executed (epoch: $_currentStreamEpoch)',
    );
  }

  void destroy() {
    globalContext.setProperty('dartSherpaOnResult'.toJS, null);
  }
}

const String _fallbackTokensText = '''<blank> 250
ؙ 0
ء 1
ا 2
ب 3
ت 4
ث 5
ج 6
ح 7
خ 8
د 9
ذ 10
ر 11
ز 12
س 13
ش 14
ص 15
ض 16
ط 17
ظ 18
ع 19
غ 20
ـ 21
ف 22
ق 23
ك 24
ل 25
م 26
ن 27
ه 28
و 29
ي 30
َ 31
ُ 32
ِ 33
ٲ 34
ڇ 35
ں 36
ۜ 37
ۥ 38
ۦ 39
۪ 40
۾ 41
ءَ 42
ءُ 43
ءِ 44
اا 45
بَ 46
بُ 47
بِ 48
بڇ 49
تت 50
تَ 51
تُ 52
تِ 53
ثَ 54
ثُ 55
ثِ 56
جَ 57
جُ 58
جِ 59
جڇ 60
حح 61
حَ 62
حُ 63
حِ 64
خَ 65
خُ 66
خِ 67
دَ 68
دُ 69
دِ 70
دڇ 71
ذَ 72
ذُ 73
ذِ 74
رر 75
رَ 76
رُ 77
رِ 78
ر۪ 79
زَ 80
زُ 81
زِ 82
سس 83
سَ 84
سُ 85
سِ 86
شَ 87
شُ 88
شِ 89
صَ 90
صُ 91
صِ 92
ضَ 93
ضُ 94
ضِ 95
طَ 96
طُ 97
طِ 98
طڇ 99
ظَ 100
ظُ 101
ظِ 102
عَ 103
عُ 104
عِ 105
غَ 106
غُ 107
غِ 108
ــ 109
فف 110
فَ 111
فُ 112
فِ 113
قَ 114
قُ 115
قِ 116
قڇ 117
كك 118
كَ 119
كُ 120
كِ 121
لل 122
لَ 123
لُ 124
لِ 125
لۜ 126
مَ 127
مُ 128
مِ 129
نؙ 130
نَ 131
نُ 132
نِ 133
نۜ 134
هَ 135
ه 136
هِ 137
وو 138
وَ 139
وُ 140
وِ 141
يي 142
يَ 143
يُ 144
يِ 145
ۥۥ 146
ۦۦ 147
ااۜ 148
ببَ 149
ببُ 150
ببِ 151
ببڇ 152
تتَ 153
تتُ 154
تتِ 155
ثثَ 156
ثثُ 157
ثثِ 158
ججَ 159
ججُ 160
ججِ 161
ججڇ 162
ححَ 163
ححِ 164
خخَ 165
خخِ 166
ددَ 167
ددُ 168
ددِ 169
ددڇ 170
ذذَ 171
ذذُ 172
ذذِ 173
ررَ 174
ررُ 175
ررِ 176
ززَ 177
ززُ 178
ززِ 179
سسَ 180
سسُ 181
سسِ 182
ششَ 183
ششُ 184
ششِ 185
صصَ 186
صصُ 187
صصِ 188
ضضَ 189
ضضُ 190
ضضِ 191
ططَ 192
ططُ 193
ططِ 194
ظظَ 195
ظظُ 196
ظظِ 197
ععَ 198
ععُ 199
ععِ 200
ففَ 201
ففُ 202
ففِ 203
ققَ 204
ققُ 205
ققِ 206
ققڇ 207
ككَ 208
ككُ 209
ككِ 210
للَ 211
للُ 212
للِ 213
ممم 214
ننن 215
ههَ 216
ههُ 217
ههِ 218
ووو 219
ووَ 220
ووُ 221
ووِ 222
ييي 223
ييَ 224
ييُ 225
ييِ 226
ںںں 227
۾۾۾ 228
اااا 229
وووَ 230
وووُ 231
وووِ 232
يييَ 233
يييُ 234
ۥۥۥۥ 235
ۦۦۦۦ 236
ااااا 237
ممممَ 238
ممممُ 239
ممممِ 240
ننننَ 241
ننننُ 242
ننننِ 243
ييييي 244
ۥۥۥۥۥ 245
ۦۦۦۦۦ 246
اااااا 247
ۥۥۥۥۥۥ 248
ۦۦۦۦۦۦ 249''';
