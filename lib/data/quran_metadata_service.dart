/// Quran metadata loader.
///
/// Reads [assets/model/quran.json] from the app bundle and
/// deserialises it into [QuranVerse] objects using Flutter's [compute]
/// so the JSON parsing does not block the UI thread.
library data.quran_metadata_service;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/quran_data.dart';

// Top-level function required by [compute].
// Must NOT be a method or a closure — the Flutter isolate runner
// cannot serialise those across isolate boundaries.
List<QuranVerse> _parseDatabaseInBackground(String jsonString) {
  final List<dynamic> jsonList = jsonDecode(jsonString);

  return jsonList.map((json) {
    String uthmani = json['text_uthmani'] as String? ?? '';
    uthmani = uthmani.replaceAll(RegExp(r'[۩۞ۖۗۚۛۙۘۜ]'), '');
    json['text_uthmani'] = uthmani;
    return QuranVerse.fromJson(json);
  }).toList();
}

class QuranMetadataService {
  List<QuranVerse>? _allVerses;

  Future<List<QuranVerse>> loadAll() async {
    if (_allVerses != null) return _allVerses!;
    final String quranData = await rootBundle.loadString('assets/model/quran.json');
    _allVerses = await compute(_parseDatabaseInBackground, quranData);
    return _allVerses!;
  }
}
