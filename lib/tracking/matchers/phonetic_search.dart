import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'fuzzy_search.dart';

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
  final int distance;

  PhonemesSearchResult({
    required this.start,
    required this.end,
    required this.distance,
  });

  @override
  String toString() {
    return 'PhonemesSearchResult(start: $start, end: $end)';
  }
}

class PhoneticSearch {
  late Uint16List _indexArray;
  late String _refPhNorm;
  bool _isLoaded = false;

  /// Loads the index and reference string from the assets.
  Future<void> load() async {
    if (_isLoaded) return;

    // Load reference phoneme string
    _refPhNorm = await rootBundle.loadString('assets/model/ref_norm_ph.txt');
    _refPhNorm = _refPhNorm.trim();

    // Load NPY index file
    ByteData npyData = await rootBundle.load('assets/model/ph_index.npy');

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
    int minorVer = npyData.getUint8(offset++);

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
    _indexArray = Uint16List.view(npyData.buffer, offset, numElements);

    // Check consistency
    int numRows = _indexArray.length ~/ 7;
    if (numRows != _refPhNorm.length) {
      throw Exception(
        "Reference length (${_refPhNorm.length}) does not match index length ($numRows)",
      );
    }

    _isLoaded = true;
  }

  /// For testing without Flutter bindings
  void forceLoadLocalForTest(String refPath, String npyPath) {
    _refPhNorm = File(refPath).readAsStringSync().trim();
    Uint8List bytes = File(npyPath).readAsBytesSync();
    ByteData npyData = ByteData.view(bytes.buffer);

    int offset = 0;
    final magic = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]; // "\x93NUMPY"
    for (int i = 0; i < 6; i++) {
      if (npyData.getUint8(offset++) != magic[i]) {
        throw Exception("Invalid NPY file: bad magic number");
      }
    }

    int majorVer = npyData.getUint8(offset++);
    int minorVer = npyData.getUint8(offset++);

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

    offset += headerLen;
    int remainingBytes = npyData.lengthInBytes - offset;
    int numElements = remainingBytes ~/ 2;
    _indexArray = Uint16List.view(npyData.buffer, offset, numElements);
    _isLoaded = true;
  }

  /// Normalizes the query by combining consecutive identical core characters
  /// into a single character and stripping residuals.
  String _normalizeQuery(String query) {
    const String coreChars = "ءبتثجحخدذرزسشصضطظعغفقكلمنهوياۥۦ۾ںـٲ";
    const String residualChars = "َُِڇؙ۪ۜ";

    String coreGroup = coreChars.split('').map((c) => '$c+').join('|');
    RegExp chunkRegex = RegExp('((?:$coreGroup)[$residualChars]?)');

    StringBuffer normQ = StringBuffer();
    for (var match in chunkRegex.allMatches(query)) {
      String group = match.group(1)!;
      if (group.isNotEmpty) {
        normQ.write(group[0]);
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
      uthmaniCharIdx: isEnd
          ? _indexArray[rowOffset + 4]
          : _indexArray[rowOffset + 3],
      phonemesIdx: isEnd
          ? _indexArray[rowOffset + 6]
          : _indexArray[rowOffset + 5],
    );
  }

  /// Searches for the query with a max allowed error ratio (e.g., 0.1 for 10% errors).
  List<PhonemesSearchResult> search(String query, {double errorRatio = 0.1}) {
    if (!_isLoaded) {
      throw Exception("PhoneticSearch must be loaded before searching");
    }

    String normQuery = _normalizeQuery(query);
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
          distance: out.dist,
        ),
      );
    }

    return results;
  }
}
