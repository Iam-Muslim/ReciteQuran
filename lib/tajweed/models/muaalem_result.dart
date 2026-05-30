// Heavily-typed Dart translation of Quran-Muaalem-Swift APIModels

import 'package:flutter/material.dart';
class MuaalemResponse {
  final String phonemesText;
  final String wav2vec2Text;
  final PhonemeUnit phonemes;
  final List<SifaItem> sifat;
  final Reference reference;
  final List<ExpectedSifaItem>? expectedSifat;
  final List<PhonemeDiffItem>? phonemeDiff;
  final List<SifatComparisonError>? sifatErrors;
  final List<WordPhoneme>? phonemesByWord;

  MuaalemResponse({
    required this.phonemesText,
    this.wav2vec2Text = '',
    required this.phonemes,
    required this.sifat,
    required this.reference,
    this.expectedSifat,
    this.phonemeDiff,
    this.sifatErrors,
    this.phonemesByWord,
  });

  factory MuaalemResponse.fromJson(Map<String, dynamic> json) {
    final phonemesUnit = PhonemeUnit.fromJson(
      json['phonemes'] as Map<String, dynamic>? ?? {},
    );

    List<SifaItem> parsedSifat =
        (json['sifat'] as List<dynamic>?)
            ?.map((e) => SifaItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    // If API response does not include 'sifat' but has phonemes, synthesize them
    // so that the UI can still map characters and probabilities to words.
    if (parsedSifat.isEmpty && phonemesUnit.probs.isNotEmpty) {
      final chars = phonemesUnit.text.characters.toList();
      for (int i = 0; i < chars.length; i++) {
        if (i < phonemesUnit.probs.length) {
          parsedSifat.add(
            SifaItem(
              phonemesGroup: chars[i],
              index: i,
              phonemeProb: phonemesUnit.probs[i],
            ),
          );
        }
      }
    }

    return MuaalemResponse(
      phonemesText: json['phonemes_text'] as String? ?? '',
      wav2vec2Text: json['wav2vec2_text'] as String? ?? '',
      phonemes: phonemesUnit,
      sifat: parsedSifat,
      reference: Reference.fromJson(
        json['reference'] as Map<String, dynamic>? ?? {},
      ),
      expectedSifat: (json['expected_sifat'] as List<dynamic>?)
          ?.map((e) => ExpectedSifaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      phonemeDiff: (json['phoneme_diff'] as List<dynamic>?)
          ?.map((e) => PhonemeDiffItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      sifatErrors: (json['sifat_errors'] as List<dynamic>?)
          ?.map((e) => SifatComparisonError.fromJson(e as Map<String, dynamic>))
          .toList(),
      phonemesByWord: (json['phonemes_by_word'] as List<dynamic>?)
          ?.map((e) => WordPhoneme.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WordPhoneme {
  final int wordIndex;
  final String word;
  final String phonemes;
  final int sifatStart;
  final int sifatEnd;
  final int sifatCount;
  final double? startMs;
  final double? endMs;

  WordPhoneme({
    required this.wordIndex,
    required this.word,
    required this.phonemes,
    required this.sifatStart,
    required this.sifatEnd,
    required this.sifatCount,
    this.startMs,
    this.endMs,
  });

  factory WordPhoneme.fromJson(Map<String, dynamic> json) {
    return WordPhoneme(
      wordIndex: json['word_index'] as int? ?? 0,
      word: json['word'] as String? ?? '',
      phonemes: json['phonemes'] as String? ?? '',
      sifatStart: json['sifat_start'] as int? ?? 0,
      sifatEnd: json['sifat_end'] as int? ?? 0,
      sifatCount: json['sifat_count'] as int? ?? 0,
      startMs: (json['start_ms'] as num?)?.toDouble(),
      endMs: (json['end_ms'] as num?)?.toDouble(),
    );
  }

  bool containsIndex(int index) {
    return index >= sifatStart && index <= sifatEnd;
  }
}

class ExpectedSifaItem {
  final int index;
  final String phonemes;
  final String? hamsOrJahr;
  final String? shiddaOrRakhawa;
  final String? tafkheemOrTaqeeq;
  final String? itbaq;
  final String? safeer;
  final String? qalqla;
  final String? tikraar;
  final String? tafashie;
  final String? istitala;
  final String? ghonna;

  ExpectedSifaItem({
    required this.index,
    required this.phonemes,
    this.hamsOrJahr,
    this.shiddaOrRakhawa,
    this.tafkheemOrTaqeeq,
    this.itbaq,
    this.safeer,
    this.qalqla,
    this.tikraar,
    this.tafashie,
    this.istitala,
    this.ghonna,
  });

  factory ExpectedSifaItem.fromJson(Map<String, dynamic> json) {
    return ExpectedSifaItem(
      index: json['index'] as int? ?? 0,
      phonemes: json['phonemes'] as String? ?? '',
      hamsOrJahr: json['hams_or_jahr'] as String?,
      shiddaOrRakhawa: json['shidda_or_rakhawa'] as String?,
      tafkheemOrTaqeeq: json['tafkheem_or_taqeeq'] as String?,
      itbaq: json['itbaq'] as String?,
      safeer: json['safeer'] as String?,
      qalqla: json['qalqla'] as String?,
      tikraar: json['tikraar'] as String?,
      tafashie: json['tafashie'] as String?,
      istitala: json['istitala'] as String?,
      ghonna: json['ghonna'] as String?,
    );
  }
}

class PhonemeDiffItem {
  final String type;
  final String text;

  PhonemeDiffItem({required this.type, required this.text});

  factory PhonemeDiffItem.fromJson(Map<String, dynamic> json) {
    return PhonemeDiffItem(
      type: json['type'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

class SifatComparisonError {
  final int index;
  final String phoneme;
  final String expectedPhoneme;
  final List<SifaAttributeError> errors;

  SifatComparisonError({
    required this.index,
    required this.phoneme,
    required this.expectedPhoneme,
    required this.errors,
  });

  factory SifatComparisonError.fromJson(Map<String, dynamic> json) {
    return SifatComparisonError(
      index: json['index'] as int? ?? 0,
      phoneme: json['phoneme'] as String? ?? '',
      expectedPhoneme: json['expected_phoneme'] as String? ?? '',
      errors:
          (json['errors'] as List<dynamic>?)
              ?.map(
                (e) => SifaAttributeError.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

class SifaAttributeError {
  final String attribute;
  final String attributeAr;
  final String expected;
  final String actual;
  final double prob;

  SifaAttributeError({
    required this.attribute,
    required this.attributeAr,
    required this.expected,
    required this.actual,
    required this.prob,
  });

  factory SifaAttributeError.fromJson(Map<String, dynamic> json) {
    return SifaAttributeError(
      attribute: json['attribute'] as String? ?? '',
      attributeAr: json['attribute_ar'] as String? ?? '',
      expected: json['expected'] as String? ?? '',
      actual: json['actual'] as String? ?? '',
      prob: (json['prob'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PhonemeUnit {
  final String text;
  final List<double> probs;
  final List<int> ids;

  PhonemeUnit({required this.text, required this.probs, required this.ids});

  factory PhonemeUnit.fromJson(Map<String, dynamic> json) {
    return PhonemeUnit(
      text: json['text'] as String? ?? '',
      probs:
          (json['probs'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      ids: (json['ids'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    );
  }
}

class SifaItem {
  final String phonemesGroup;
  final int index;
  final double? startMs;
  final double? endMs;
  double phonemeProb; // Added to store the probability from phonemes list
  int charIndex; // Added to store character index alignment within the word
  final SingleUnit? hamsOrJahr;
  final SingleUnit? shiddaOrRakhawa;
  final SingleUnit? tafkheemOrTaqeeq;
  final SingleUnit? itbaq;
  final SingleUnit? safeer;
  final SingleUnit? qalqla;
  final SingleUnit? tikraar;
  final SingleUnit? tafashie;
  final SingleUnit? istitala;
  final SingleUnit? ghonna;

  SifaItem({
    required this.phonemesGroup,
    required this.index,
    this.startMs,
    this.endMs,
    this.phonemeProb = 1.0,
    this.charIndex = 0,
    this.hamsOrJahr,
    this.shiddaOrRakhawa,
    this.tafkheemOrTaqeeq,
    this.itbaq,
    this.safeer,
    this.qalqla,
    this.tikraar,
    this.tafashie,
    this.istitala,
    this.ghonna,
  });

  factory SifaItem.fromJson(Map<String, dynamic> json) {
    return SifaItem(
      phonemesGroup: json['phonemes_group'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      startMs: (json['start_ms'] as num?)?.toDouble(),
      endMs: (json['end_ms'] as num?)?.toDouble(),
      phonemeProb: 1.0,
      hamsOrJahr: json['hams_or_jahr'] != null
          ? SingleUnit.fromJson(json['hams_or_jahr'])
          : null,
      shiddaOrRakhawa: json['shidda_or_rakhawa'] != null
          ? SingleUnit.fromJson(json['shidda_or_rakhawa'])
          : null,
      tafkheemOrTaqeeq: json['tafkheem_or_taqeeq'] != null
          ? SingleUnit.fromJson(json['tafkheem_or_taqeeq'])
          : null,
      itbaq: json['itbaq'] != null ? SingleUnit.fromJson(json['itbaq']) : null,
      safeer: json['safeer'] != null
          ? SingleUnit.fromJson(json['safeer'])
          : null,
      qalqla: json['qalqla'] != null
          ? SingleUnit.fromJson(json['qalqla'])
          : null,
      tikraar: json['tikraar'] != null
          ? SingleUnit.fromJson(json['tikraar'])
          : null,
      tafashie: json['tafashie'] != null
          ? SingleUnit.fromJson(json['tafashie'])
          : null,
      istitala: json['istitala'] != null
          ? SingleUnit.fromJson(json['istitala'])
          : null,
      ghonna: json['ghonna'] != null
          ? SingleUnit.fromJson(json['ghonna'])
          : null,
    );
  }
}

class SingleUnit {
  final String text;
  final double prob;
  final int idx;

  SingleUnit({required this.text, required this.prob, required this.idx});

  factory SingleUnit.fromJson(Map<String, dynamic> json) {
    return SingleUnit(
      text: json['text'] as String? ?? '',
      prob: (json['prob'] as num?)?.toDouble() ?? 0.0,
      idx: json['idx'] as int? ?? 0,
    );
  }
}

class Reference {
  final int? sura;
  final int? aya;
  final String uthmaniText;
  final Moshaf moshaf;
  final PhoneticScript phoneticScript;

  Reference({
    this.sura,
    this.aya,
    required this.uthmaniText,
    required this.moshaf,
    required this.phoneticScript,
  });

  factory Reference.fromJson(Map<String, dynamic> json) {
    return Reference(
      sura: json['sura'] as int?,
      aya: json['aya'] as int?,
      uthmaniText: json['uthmani_text'] as String? ?? '',
      moshaf: Moshaf.fromJson(json['moshaf'] as Map<String, dynamic>? ?? {}),
      phoneticScript: PhoneticScript.fromJson(
        json['phonetic_script'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class Moshaf {
  final String rewaya;
  final int maddMonfaselLen;
  final int maddMottaselLen;
  final int maddMottaselWaqf;
  final int maddAaredLen;

  Moshaf({
    required this.rewaya,
    required this.maddMonfaselLen,
    required this.maddMottaselLen,
    required this.maddMottaselWaqf,
    required this.maddAaredLen,
  });

  factory Moshaf.fromJson(Map<String, dynamic> json) {
    return Moshaf(
      rewaya: json['rewaya'] as String? ?? '',
      maddMonfaselLen: json['madd_monfasel_len'] as int? ?? 0,
      maddMottaselLen: json['madd_mottasel_len'] as int? ?? 0,
      maddMottaselWaqf: json['madd_mottasel_waqf'] as int? ?? 0,
      maddAaredLen: json['madd_aared_len'] as int? ?? 0,
    );
  }
}

class PhoneticScript {
  final String phonemesText;

  PhoneticScript({required this.phonemesText});

  factory PhoneticScript.fromJson(Map<String, dynamic> json) {
    return PhoneticScript(phonemesText: json['phonemes_text'] as String? ?? '');
  }
}

class APIError implements Exception {
  final String detail;

  APIError({required this.detail});

  factory APIError.fromJson(Map<String, dynamic> json) {
    return APIError(detail: json['detail'] as String? ?? 'Unknown error');
  }

  @override
  String toString() => 'APIError: $detail';
}
