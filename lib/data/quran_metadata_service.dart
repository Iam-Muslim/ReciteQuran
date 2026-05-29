// Quran metadata loader.
//
// Reads [assets/model/quran.json] from the app bundle and
// deserialises it into [QuranVerse] objects using Flutter's [compute]
// so the JSON parsing does not block the UI thread.


import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/quran_data.dart';

// Top-level function required by [compute].
List<QuranVerse> _parseDatabaseInBackground(String jsonString) {
  final List<dynamic> jsonList = jsonDecode(jsonString);

  return jsonList.map((json) {
    // Map hafs_smart_v8.json keys to the expected structure
    final mappedJson = {
      'surah': json['sura_no'],
      'ayah': json['aya_no'],
      'surah_name': json['sura_name_ar'],
      'surah_name_en': json['sura_name_en'],
      // We use aya_text_emlaey for clean word matching (without diacritics)
      'text_clean': json['aya_text_emlaey'] as String? ?? '',
      // We use aya_text for Uthmani display
      'text_uthmani': _stripAyahNumber(json['aya_text'] as String? ?? ''),
    };

    return QuranVerse.fromJson(mappedJson);
  }).toList();
}

String _stripAyahNumber(String text) {
  final words = text.trim().split(' ');
  if (words.length > 1) {
    // The Hafs Smart font places the Ayah symbol+number as the final "word"
    return words.sublist(0, words.length - 1).join(' ');
  }
  return text;
}

class QuranMetadataService {
  List<QuranVerse>? _allVerses;

  Future<List<QuranVerse>> loadAll() async {
    if (_allVerses != null) return _allVerses!;
    final String quranData = await rootBundle.loadString(
      'assets/hafs_smart_v8.json',
    );
    _allVerses = await compute(_parseDatabaseInBackground, quranData);
    return _allVerses!;
  }
}
