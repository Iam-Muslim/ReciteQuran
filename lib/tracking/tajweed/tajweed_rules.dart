// lib/tracking/matchers/tajweed_rules.dart

class PhoneticConstants {
  static const String qlqla = '\u0687'; // جيم صغيرة
  static const String alif = '\u0627';
  static const String wawMadd = '\u06e5'; // small waw
  static const String yaaMadd = '\u06e6'; // small yaa sila
  static const String noon = '\u0646';
  static const String yaa = '\u064a';
  static const String waw = '\u0648';
  static const String meem = '\u0645';
  static const String noonMokhfah = '\u06ba'; // urdu ghonna
  static const String meemMokhfah = '\u06fe';
  static const String tafkheemChars = 'خصضغطقظ';
  static const String hamsChars = 'فحثهشخصسكت';
  static const String qalqalahChars = 'قطبجد';
}

class LangName {
  final String ar;
  final String en;
  const LangName({required this.ar, required this.en});
}

enum CorrectnessType { match, count }

abstract class TajweedRule {
  final LangName name;
  final int goldenLen;
  final CorrectnessType correctnessType;
  final String? tag;
  final Set<String>? availableTags;

  TajweedRule({
    required this.name,
    required this.goldenLen,
    required this.correctnessType,
    this.tag,
    this.availableTags,
  }) {
    if (tag != null && availableTags != null) {
      if (!availableTags!.contains(tag)) {
        throw ArgumentError('Invalid tag value: $tag. Available ones are: $availableTags');
      }
    }
  }

  int count(String refText, String predText) => 0;

  bool match(String refText, String predText) => true;

  bool checkDuration(double durationSeconds) {
    if (goldenLen <= 0) return true;
    double requiredDuration = goldenLen * 0.20; // 0.20s per harakah roughly
    return durationSeconds >= requiredDuration;
  }

  /// Whether the phonetic script is associated with this Tajweed rule or not
  bool isPhStrIn(String phStr) => true;

  /// Returns a Tajweed rule that is associated with the input phStr
  TajweedRule? getRelevantRule(String phStr) => this;

  TajweedRule copyWith({String? tag, LangName? name, int? offset});
}

class Qalqalah extends TajweedRule {
  Qalqalah()
      : super(
          name: const LangName(ar: "قلقة", en: "Qalqalah"),
          goldenLen: 0,
          correctnessType: CorrectnessType.match,
        );

  @override
  bool match(String refText, String predText) => refText == predText;

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isEmpty) return false;
    // Base consonant is the first character
    return PhoneticConstants.qalqalahChars.contains(phStr[0]);
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (isPhStrIn(phStr)) return this;
    // Also support the explicit qalqalah small jeem sign at the end
    if (phStr.isNotEmpty && phStr[phStr.length - 1] == PhoneticConstants.qlqla) return this;
    return null;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) => this;
}

class MaddRule extends TajweedRule {
  static const Map<String, String> _maddToTag = {
    PhoneticConstants.alif: "alif",
    PhoneticConstants.wawMadd: "waw",
    PhoneticConstants.yaaMadd: "yaa",
  };

  MaddRule({
    required super.name,
    required super.goldenLen,
    super.correctnessType = CorrectnessType.count,
    super.tag,
  }) : super(availableTags: {"alif", "waw", "yaa"});

  @override
  int count(String refText, String predText) {
    if (predText.isEmpty || refText.isEmpty) return 0;
    // The case where we have Tashkeel after madd (Error from the model)
    if (predText[predText.length - 1] != predText[0]) {
      return predText.substring(0, predText.length - 1).split(refText[0]).length - 1;
    } else {
      return predText.split(refText[0]).length - 1;
    }
  }

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isNotEmpty) {
      return _maddToTag.containsKey(phStr[0]);
    }
    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (phStr.isEmpty) return null;
    if (!_maddToTag.containsKey(phStr[0])) return null;
    return copyWith(tag: _maddToTag[phStr[0]]);
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return MaddRule(
      name: name ?? this.name,
      goldenLen: goldenLen,
      correctnessType: correctnessType,
      tag: tag ?? this.tag,
    );
  }
}

class NormalMaddRule extends MaddRule {
  NormalMaddRule({super.tag})
      : super(
          name: const LangName(ar: "المد الطبيعي", en: "Normal Madd"),
          goldenLen: 2,
        );
}

class MonfaselMaddRule extends MaddRule {
  MonfaselMaddRule({super.tag})
      : super(
          name: const LangName(ar: "المد المنفصل", en: "Monfasel Madd"),
          goldenLen: 4,
        );
}

class MottaselMaddPauseRule extends MaddRule {
  MottaselMaddPauseRule({super.tag})
      : super(
          name: const LangName(ar: "المد المتصل وقفا", en: "Mottasel Madd at Pause"),
          goldenLen: 4,
        );
}

class MottaselMaddRule extends MaddRule {
  MottaselMaddRule({super.tag})
      : super(
          name: const LangName(ar: "المد المتصل", en: "Mottasel Madd"),
          goldenLen: 4,
        );
}

class LazemMaddRule extends MaddRule {
  LazemMaddRule({super.tag})
      : super(
          name: const LangName(ar: "المد اللازم", en: "Lazem Madd"),
          goldenLen: 6,
        );
}

class AaredMaddRule extends MaddRule {
  AaredMaddRule({super.tag})
      : super(
          name: const LangName(ar: "المد العارض للسكون", en: "Aared Madd"),
          goldenLen: 2,
        );
}

class LeenMaddRule extends MaddRule {
  static const Map<String, String> _leenMaddToTag = {
    PhoneticConstants.waw: "waw",
    PhoneticConstants.yaa: "yaa",
  };

  LeenMaddRule({super.tag})
      : super(
          name: const LangName(ar: "مد اللين", en: "Leen Madd"),
          goldenLen: 2,
        );

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isNotEmpty) {
      return _leenMaddToTag.containsKey(phStr[0]);
    }
    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (phStr.isEmpty) return null;
    if (!_leenMaddToTag.containsKey(phStr[0])) return null;
    return copyWith(tag: _leenMaddToTag[phStr[0]]);
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return LeenMaddRule(tag: tag ?? this.tag);
  }

  @override
  int count(String refText, String predText) {
    if (predText.isEmpty || refText.isEmpty) return 0;
    if (predText[predText.length - 1] != predText[0]) {
      return (predText.substring(0, predText.length - 1).split(refText[0]).length - 1) + 1;
    } else {
      return (predText.split(refText[0]).length - 1) + 1;
    }
  }
}

class IdghamKamel extends TajweedRule {
  IdghamKamel()
      : super(
          name: const LangName(ar: "إدغام كامل", en: "Full Merging"),
          goldenLen: 0,
          correctnessType: CorrectnessType.match,
        );

  @override
  bool match(String refText, String predText) => refText == predText;

  @override
  bool isPhStrIn(String phStr) => true;

  @override
  TajweedRule? getRelevantRule(String phStr) => null;

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) => this;
}

class GhonnahMetadata {
  final LangName name;
  final String tag;
  final int offset;

  const GhonnahMetadata({required this.name, required this.tag, this.offset = 0});
}

class Ghonnah extends TajweedRule {
  final int offset;

  static const Map<String, GhonnahMetadata> _phToMetadata = {
    PhoneticConstants.noon: GhonnahMetadata(
      name: LangName(ar: "النون المشددة أو المدغمة", en: "Moshadad or Modgham Noon"),
      tag: "noon",
      offset: 0,
    ),
    PhoneticConstants.yaa: GhonnahMetadata(
      name: LangName(ar: "", en: ""),
      tag: "noon_yaa",
      offset: 1,
    ),
    PhoneticConstants.waw: GhonnahMetadata(
      name: LangName(ar: "", en: ""),
      tag: "noon_waw",
      offset: 1,
    ),
    PhoneticConstants.noonMokhfah: GhonnahMetadata(
      name: LangName(ar: "", en: ""),
      tag: "noon_mokhfah",
      offset: 1,
    ),
    PhoneticConstants.meem: GhonnahMetadata(
      name: LangName(ar: "", en: ""),
      tag: "meem",
      offset: 0,
    ),
    PhoneticConstants.meemMokhfah: GhonnahMetadata(
      name: LangName(ar: "", en: ""),
      tag: "meem_mokhfah",
      offset: 0,
    ),
  };

  Ghonnah({
    required super.name,
    super.goldenLen = 4,
    super.correctnessType = CorrectnessType.count,
    super.tag,
    this.offset = 0,
  }) : super(availableTags: {
          "noon",
          "noon_yaa",
          "noon_waw",
          "noon_mokhfah",
          "meem",
          "meem_mokhfah",
        });

  @override
  int count(String refText, String predText) {
    if (refText.isEmpty) return 0;
    return (predText.split(refText[0]).length - 1) + offset;
  }

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isNotEmpty) {
      return _phToMetadata.containsKey(phStr[0]);
    }
    return false;
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (phStr.isEmpty || !_phToMetadata.containsKey(phStr[0])) return null;
    final meta = _phToMetadata[phStr[0]]!;
    return copyWith(name: meta.name, offset: meta.offset, tag: meta.tag);
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) {
    return Ghonnah(
      name: name ?? this.name,
      goldenLen: goldenLen,
      correctnessType: correctnessType,
      tag: tag ?? this.tag,
      offset: offset ?? this.offset,
    );
  }
}

class MoshaddadOrModghamNoonRule extends MaddRule {
  MoshaddadOrModghamNoonRule({super.tag})
      : super(
          name: const LangName(ar: "النون المشددة أو المدغمة", en: "Moshaddad or ModghamNoon"),
          goldenLen: 4,
        );
}

class TafkheemRule extends TajweedRule {
  TafkheemRule()
      : super(
          name: const LangName(ar: "تفخيم", en: "Tafkheem"),
          goldenLen: 0,
          correctnessType: CorrectnessType.match,
        );

  @override
  bool match(String refText, String predText) => refText == predText;

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isEmpty) return false;
    return PhoneticConstants.tafkheemChars.contains(phStr[0]);
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (isPhStrIn(phStr)) return this;
    return null;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) => this;
}

class HamsRule extends TajweedRule {
  HamsRule()
      : super(
          name: const LangName(ar: "همس", en: "Hams"),
          goldenLen: 0,
          correctnessType: CorrectnessType.match,
        );

  @override
  bool match(String refText, String predText) => refText == predText;

  @override
  bool isPhStrIn(String phStr) {
    if (phStr.isEmpty) return false;
    return PhoneticConstants.hamsChars.contains(phStr[0]);
  }

  @override
  TajweedRule? getRelevantRule(String phStr) {
    if (isPhStrIn(phStr)) return this;
    return null;
  }

  @override
  TajweedRule copyWith({String? tag, LangName? name, int? offset}) => this;
}
