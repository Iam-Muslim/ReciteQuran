import 'package:flutter/material.dart';

bool isCharMatch(String pBase, String wBase) {
  final mappings = getCharMappings(pBase);
  if (pBase == wBase) return true;
  if (mappings.contains(wBase)) return true;
  return false;
}

Set<String> getCharMappings(String charStr) {
  final mappings = <String, List<String>>{
    "ء": ["أ", "إ", "آ", "ؤ", "ئ", "ٱ"],
    "أ": ["ء", "إ", "آ", "ٱ"],
    "إ": ["ء", "أ", "آ", "ٱ"],
    "ا": ["آ", "أ", "إ", "ٰ", "ى", "ٱ", "ـٰ"],
    "ٱ": ["ا", "آ", "أ", "إ"],
    "ٰ": ["ا"],
    "ـٰ": ["ا"],
    "ه": ["ة", "ھ", "ہ"],
    "ة": ["ه"],
    "ي": ["ى", "ۦ", "ئ", "ی", "يـ"],
    "ى": ["ي", "ۦ"],
    "ۦ": ["ي", "ى", "ئ"],
    "و": ["ۥ", "ؤ"],
    "ۥ": ["و", "ؤ"],
    "ن": ["ں"],
    "ر": ["ڔ", "ڑ"],
    "ل": ["ڵ"],
    "ك": ["ک"],
    "ت": ["ة"],
    "د": ["ڈ"],
  };

  var result = <String>{};
  if (mappings.containsKey(charStr)) {
    result.addAll(mappings[charStr]!);
  }
  for (int i = 0; i < charStr.length; i++) {
    if (mappings.containsKey(charStr[i])) {
      result.addAll(mappings[charStr[i]]!);
    }
  }
  return result;
}

String stripArabicDiacritics(String text) {
  return text.replaceAll(
    RegExp(
      r'[\u064b-\u065f\u0610-\u061a\u06d6-\u06e4\u06e7-\u06ed\u08d4-\u08e1\u08e3-\u08ff]',
    ),
    '',
  );
}

bool wordContainsPhoneme(String word, String expectedPhoneme) {
  final expectedBase = stripArabicDiacritics(expectedPhoneme);
  final uniqueChars = expectedBase.split('').toSet();
  final targetBase = (uniqueChars.length == 1 && expectedBase.isNotEmpty)
      ? uniqueChars.first
      : expectedBase;

  if (targetBase.isEmpty) return true;

  final mappings = getCharMappings(targetBase);
  for (int i = 0; i < word.length; i++) {
    final charBase = stripArabicDiacritics(word[i]);
    if (charBase.isNotEmpty &&
        (charBase == targetBase ||
            mappings.contains(charBase) ||
            (targetBase.contains(charBase) &&
                targetBase.length > charBase.length))) {
      return true;
    }
  }
  return false;
}

Color getConfidenceColor(double prob) {
  if (prob > 0.90) return Colors.green;
  if (prob >= 0.70) return Colors.orange;
  return Colors.red;
}

String translateSifa(String val) {
  if (val == '[PAD]' || val.isEmpty) return 'غير واضح';

  const Map<String, String> dict = {
    'hams': 'همس',
    'jahr': 'جهر',
    'shadeed': 'شديد',
    'between': 'بين بين',
    'rikhw': 'رخاوة',
    'mofakham': 'مفخم',
    'moraqaq': 'مرقق',
    'low_mofakham': 'تفخيم خفيف',
    'motbaq': 'مطبق',
    'monfateh': 'منفتح',
    'safeer': 'صفير',
    'no_safeer': 'بدون صفير',
    'moqalqal': 'مقلقل',
    'not_moqalqal': 'بدون قلقلة',
    'mokarar': 'مكرر',
    'not_mokarar': 'بدون تكرار',
    'motafashie': 'متفشي',
    'not_motafashie': 'بدون تفشي',
    'mostateel': 'مستطيل',
    'not_mostateel': 'بدون استطالة',
    'maghnoon': 'مغنون',
    'not_maghnoon': 'بدون غنة',
    'true': 'يوجد',
    'false': 'لا يوجد',
    'none': 'لا يوجد',
    'correct': 'صحيح',
    'incorrect': 'خاطئ',
  };

  return dict[val.toLowerCase()] ?? val;
}