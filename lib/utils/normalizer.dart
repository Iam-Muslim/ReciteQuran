class Normalizer {
  static final RegExp _diacritics = RegExp(
    '[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC'
    '\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\u0640]',
  );

  static final Map<String, String> _normMap = {
    '\u0623': '\u0627', // أ -> ا
    '\u0625': '\u0627', // إ -> ا
    '\u0622': '\u0627', // آ -> ا
    '\u0671': '\u0627', // ٱ -> ا
    '\u0629': '\u0647', // ة -> ه
    '\u0649': '\u064A', // ى -> ي
  };

  // NEW: Pre-compiled regex for Huroof Muqatta'ah
  static final RegExp _muqattaatRegex = RegExp(
    r'(?<=^|\s)(صاد|قاف|نون)(?=\s|$)',
  );
  // NEW: Method to process Huroof Muqatta'ah efficiently
  static String processMuqattaat(String text) {
    if (text.isEmpty) return text;
    return text;
    // .replaceAll("الف لام ميم صاد", "المص")
    // .replaceAll("الف لام ميم را", "المر")
    // .replaceAll("الف لام ميم", "الم")
    // .replaceAll("الف لام را", "الر")
    // .replaceAll("الف م", "الم")
    // .replaceAll("كاف ها يا عين صاد", "كهيعص")
    // .replaceAll("طا سين ميم", "طسم")
    // .replaceAll("طا سين", "طس")
    // .replaceAll("طا ها", "طه")
    // .replaceAll("يا سين", "يس")
    // .replaceAll("حا ميم عين سين قاف", "حم عسق")
    // .replaceAll("حا ميم", "حم")
    // .replaceAllMapped(
    //   // <--- CHANGED TO replaceAllMapped
    //   _muqattaatRegex,
    //   (Match match) {
    //     if (match.group(0) == "صاد") return "ص";
    //     if (match.group(0) == "قاف") return "ق";
    //     if (match.group(0) == "نون") return "ن";
    //     return match.group(0)!;
    //   }, // <--- REMOVED "as String"
    // );
  }

  static String normalizeArabic(String text) {
    if (text.isEmpty) return text;

    // Strip BOM
    if (text.startsWith('\ufeff')) {
      text = text.substring(1);
    }

    // Remove diacritics
    text = text.replaceAll(_diacritics, '');

    // Apply character normalization map
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(_normMap[char] ?? char);
    }
    text = buffer.toString();

    // Replace SentencePiece lower-one-eighth block with standard space
    text = text.replaceAll('\u2581', ' ');

    // Replace multiple spaces with a single space and trim
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }
}
