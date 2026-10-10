import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fuzzy_search.dart';

class _SearchArgs {
  final String normQuery;
  final String refPhNorm;
  final int maxEdits;
  _SearchArgs(this.normQuery, this.refPhNorm, this.maxEdits);
}

List<FuzzyMatch> _runSearchIsolated(_SearchArgs args) {
  return findNearMatches(args.normQuery, args.refPhNorm, args.maxEdits);
}

/// Long-lived background Isolate worker for zero-serialization fuzzy phonetic searches.
/// Holds the 623k reference string in isolate memory once at startup, eliminating
/// high GC and SendPort string copying on every real-time ASR chunk.
class _PhoneticIsolateWorker {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _responsePort;
  int _requestId = 0;
  final Map<int, Completer<List<FuzzyMatch>>> _pendingRequests = {};
  bool _isReady = false;

  bool get isReady => _isReady;

  Future<void> start(String refPhNorm) async {
    if (_isReady) return;
    if (kIsWeb) return;

    try {
      final initPort = ReceivePort();
      _responsePort = ReceivePort();

      _isolate = await Isolate.spawn(
        _phoneticWorkerEntrypoint,
        [initPort.sendPort, _responsePort!.sendPort, refPhNorm],
      );

      _sendPort = await initPort.first as SendPort;
      initPort.close();

      _responsePort!.listen((message) {
        if (message is List && message.length == 2) {
          final int reqId = message[0] as int;
          final List<FuzzyMatch> matches = message[1] as List<FuzzyMatch>;
          final completer = _pendingRequests.remove(reqId);
          completer?.complete(matches);
        }
      });

      _isReady = true;
    } catch (_) {
      _isReady = false;
    }
  }

  Future<List<FuzzyMatch>> search(String query, int maxEdits) {
    if (!_isReady || _sendPort == null) {
      return Future.value(const []);
    }
    final int reqId = ++_requestId;
    final completer = Completer<List<FuzzyMatch>>();
    _pendingRequests[reqId] = completer;
    _sendPort!.send([reqId, query, maxEdits]);
    return completer.future.timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () => const [],
    );
  }

  void dispose() {
    _isReady = false;
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) c.complete(const []);
    }
    _pendingRequests.clear();
    _responsePort?.close();
    _responsePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }
}

void _phoneticWorkerEntrypoint(List<dynamic> args) {
  final SendPort initSendPort = args[0] as SendPort;
  final SendPort responseSendPort = args[1] as SendPort;
  final String refPhNorm = args[2] as String;

  final commandPort = ReceivePort();
  initSendPort.send(commandPort.sendPort);

  commandPort.listen((message) {
    if (message is List && message.length == 3) {
      final int reqId = message[0] as int;
      final String normQuery = message[1] as String;
      final int maxEdits = message[2] as int;

      try {
        final List<FuzzyMatch> matches =
            findNearMatches(normQuery, refPhNorm, maxEdits);
        responseSendPort.send([reqId, matches]);
      } catch (_) {
        responseSendPort.send([reqId, <FuzzyMatch>[]]);
      }
    }
  });
}

class PhonemesSearchSpan {
  final int surahIdx;
  final int ayahIdx;
  final int uthmaniWordIdx;
  final int uthmaniCharIdx;
  final int phonemesIdx;

  PhonemesSearchSpan({
    required this.surahIdx,
    required this.ayahIdx,
    required this.uthmaniWordIdx,
    required this.uthmaniCharIdx,
    required this.phonemesIdx,
  });

  @override
  String toString() {
    return 'PhonemesSearchSpan(surah: $surahIdx, ayah: $ayahIdx, word: $uthmaniWordIdx, char: $uthmaniCharIdx, ph: $phonemesIdx)';
  }
}

class PhonemesSearchResult {
  final PhonemesSearchSpan start;
  final PhonemesSearchSpan end;
  final PhonemesSearchSpan mid;
  final int distance;

  PhonemesSearchResult({
    required this.start,
    required this.end,
    required this.mid,
    required this.distance,
  });

  @override
  String toString() {
    return 'PhonemesSearchResult(start: $start, mid: $mid, end: $end)';
  }
}

class PhoneticSearch {
  late Uint16List _indexArray;
  late String _refPhNorm;
  bool _isLoaded = false;
  final _PhoneticIsolateWorker _worker = _PhoneticIsolateWorker();

  /// Loads the index and reference string from the assets.
  Future<void> load() async {
    if (_isLoaded) return;

    // Load reference phoneme string
    String refPhNorm;
    try {
      refPhNorm = await rootBundle.loadString(
        'packages/recite_quran/assets/model/ref_norm_ph.txt',
      );
    } catch (_) {
      refPhNorm = await rootBundle.loadString('assets/model/ref_norm_ph.txt');
    }

    // Load NPY index file
    ByteData npyData;
    try {
      npyData = await rootBundle.load(
        'packages/recite_quran/assets/model/ph_index.npy',
      );
    } catch (_) {
      npyData = await rootBundle.load('assets/model/ph_index.npy');
    }

    loadFromData(refPhNorm, npyData);
    await _worker.start(_refPhNorm);
  }

  /// Synchronously loads from in-memory string and binary bytes (useful for unit tests and offline workers).
  void loadSync({required String refPhNorm, required Uint8List npyBytes}) {
    if (_isLoaded) return;
    loadFromData(refPhNorm, ByteData.sublistView(npyBytes));
    _worker.start(_refPhNorm);
  }

  /// Parses and initializes the internal index array from decoded reference and NPY binary buffer.
  void loadFromData(String refPhNorm, ByteData npyData) {
    _refPhNorm = refPhNorm.trim();

    // An NPY file starts with a Magic string "\x93NUMPY"
    // Then 1 byte major version, 1 byte minor version.
    // Then 2 bytes HEADER_LEN (little endian).
    // The header is a python dictionary string ending with newline.
    // Let's parse it dynamically to find the start of the data.
    int offset = 0;

    // Check magic
    final magic = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]; // "\x93NUMPY"
    for (int i = 0; i < 6; i++) {
      if (npyData.getUint8(offset++) != magic[i]) {
        throw Exception("Invalid NPY file: bad magic number");
      }
    }

    int majorVer = npyData.getUint8(offset++);
    offset++; // minorVer

    int headerLen;
    if (majorVer == 1) {
      headerLen = npyData.getUint16(offset, Endian.little);
      offset += 2;
    } else if (majorVer == 2 || majorVer == 3) {
      headerLen = npyData.getUint32(offset, Endian.little);
      offset += 4;
    } else {
      throw Exception("Unsupported NPY version: $majorVer");
    }

    // Skip header string
    offset += headerLen;

    // The rest is the binary data. It's a (N, 7) array of uint16.
    // In Dart, we can just create a Uint16List view over the remaining buffer.
    int remainingBytes = npyData.lengthInBytes - offset;
    int numElements = remainingBytes ~/ 2;

    int byteOffset = npyData.offsetInBytes + offset;
    if (byteOffset % 2 != 0) {
      Uint8List unaligned =
          npyData.buffer.asUint8List(byteOffset, remainingBytes);
      Uint8List aligned = Uint8List.fromList(unaligned);
      _indexArray = aligned.buffer.asUint16List();
    } else {
      _indexArray = npyData.buffer.asUint16List(byteOffset, numElements);
    }

    // Check consistency
    int numRows = _indexArray.length ~/ 7;
    if (numRows != _refPhNorm.length) {
      throw Exception(
        "Reference length (${_refPhNorm.length}) does not match index length ($numRows)",
      );
    }

    _isLoaded = true;
  }

  static const String _coreChars = "ءبتثجحخدذرزسشصضطظعغفقكلمنهوياۥۦ۾ںـٲ";

  static final Uint8List _isCoreCode = () {
    final arr = Uint8List(2048);
    for (int i = 0; i < _coreChars.length; i++) {
      final code = _coreChars.codeUnitAt(i);
      if (code < 2048) arr[code] = 1;
    }
    return arr;
  }();

  /// Normalizes an Arabic phoneme string by collapsing consecutive core consonants
  /// and stripping residuals/whitespace (identical to reference normalize_phoneme_query in phonetics.py).
  static String normalizeQuery(String query) {
    if (query.isEmpty) return '';
    final StringBuffer normQ = StringBuffer();
    int prevCode = -1;
    for (int i = 0; i < query.length; i++) {
      final int code = query.codeUnitAt(i);
      if (code < 2048 && _isCoreCode[code] == 1) {
        if (code != prevCode) {
          normQ.writeCharCode(code);
          prevCode = code;
        }
      }
    }
    return normQ.toString();
  }

  PhonemesSearchSpan _refIdxToSpan(int refIdx, {bool isEnd = false}) {
    if (refIdx < 0 || refIdx >= _refPhNorm.length) {
      throw RangeError("Reference index $refIdx out of range");
    }

    // Each row has 7 elements:
    // 0: sura_idx
    // 1: aya_idx
    // 2: uth_word_idx
    // 3: uth_char_start_idx
    // 4: uth_char_end_idx
    // 5: ph_start_idx
    // 6: ph_end_idx
    int rowOffset = refIdx * 7;

    return PhonemesSearchSpan(
      surahIdx: _indexArray[rowOffset + 0],
      ayahIdx: _indexArray[rowOffset + 1],
      uthmaniWordIdx: _indexArray[rowOffset + 2],
      uthmaniCharIdx:
          isEnd ? _indexArray[rowOffset + 4] : _indexArray[rowOffset + 3],
      phonemesIdx:
          isEnd ? _indexArray[rowOffset + 6] : _indexArray[rowOffset + 5],
    );
  }

  /// Searches for the query with a max allowed error ratio (e.g., 0.1 for 10% errors).
  List<PhonemesSearchResult> search(String query, {double errorRatio = 0.1}) {
    if (!_isLoaded) {
      throw Exception("PhoneticSearch must be loaded before searching");
    }

    String normQuery = normalizeQuery(query);
    if (normQuery.isEmpty) return [];

    int maxEdits = (normQuery.length * errorRatio).toInt();

    // Use our fuzzy_search algorithm
    List<FuzzyMatch> outs = findNearMatches(normQuery, _refPhNorm, maxEdits);

    if (outs.isEmpty) {
      return [];
    }

    List<PhonemesSearchResult> results = [];
    for (var out in outs) {
      results.add(
        PhonemesSearchResult(
          start: _refIdxToSpan(out.start, isEnd: false),
          end: _refIdxToSpan(out.end - 1, isEnd: true),
          mid: _refIdxToSpan((out.start + out.end - 1) ~/ 2, isEnd: false),
          distance: out.dist,
        ),
      );
    }

    // Sort by distance (best matches first) to align with python reference implementation
    results.sort((a, b) => a.distance.compareTo(b.distance));

    return results;
  }

  /// Searches for the query asynchronously on a background isolate to prevent UI freezes.
  Future<List<PhonemesSearchResult>> searchIsolated(String query,
      {double errorRatio = 0.1}) async {
    if (!_isLoaded) {
      throw Exception("PhoneticSearch must be loaded before searching");
    }

    String normQuery = normalizeQuery(query);
    if (normQuery.isEmpty) return [];

    int maxEdits = (normQuery.length * errorRatio).toInt();

    // Use persistent background isolate worker; fallback gracefully to compute if not yet ready
    List<FuzzyMatch> outs;
    if (_worker.isReady) {
      outs = await _worker.search(normQuery, maxEdits);
    } else {
      outs = await compute(
        _runSearchIsolated,
        _SearchArgs(normQuery, _refPhNorm, maxEdits),
      );
    }

    if (outs.isEmpty) {
      return [];
    }

    List<PhonemesSearchResult> results = [];
    for (var out in outs) {
      results.add(
        PhonemesSearchResult(
          start: _refIdxToSpan(out.start, isEnd: false),
          end: _refIdxToSpan(out.end - 1, isEnd: true),
          mid: _refIdxToSpan((out.start + out.end - 1) ~/ 2, isEnd: false),
          distance: out.dist,
        ),
      );
    }

    // Sort by distance (best matches first) to align with python reference implementation
    results.sort((a, b) => a.distance.compareTo(b.distance));

    return results;
  }

  /// Disposes background worker isolate resources.
  void dispose() {
    _worker.dispose();
  }
}
