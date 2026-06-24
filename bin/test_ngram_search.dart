import 'dart:convert';
import 'dart:io';

import '../lib/tracking/matchers/anchor.dart';
import '../lib/tracking/matchers/phoneme_chunker.dart';

void main() async {
  print('Loading NgramIndex from JSON...');
  final File file = File('assets/model/ngram_index.json');
  final String jsonStr = await file.readAsString();
  final Map<String, dynamic> data = jsonDecode(jsonStr);
  final NgramIndex index = NgramIndex.fromJson(data);
  print('Index loaded successfully!');

  final String fakePhoneme = "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِممممِنَلمُشرِكِۦۦنَقَتلَءَولَاادِهِمشُرَكَااااءُهُملِيُردُۥۥهُموَلِيَلبِسُۥۥعَلَيهِمدِۦۦنَهُموَلَوشَااااءَللَااهُمَاافَعَلُۥۥهُفَذَرهُموَمَاايَفتَرُۥۥۥۥن";

  print('Chunking input phoneme string...');
  final chunks = PhonemeChunker.chunkPhonemes(fakePhoneme);
  
  print('Running Anchor.findAnchorByVoting...');
  final result = Anchor.findAnchorByVoting(
    phonemeTexts: [chunks],
    ngramIndex: index,
  );

  print('\n=== SEARCH RESULT ===');
  print('Surah: ${result.surah}');
  print('Ayah:  ${result.ayah}');
  
  if (result.surah == 6 && result.ayah == 137) {
    print('SUCCESS: The index correctly identified Al-An\'am (6), Ayah 137!');
  } else {
    print('FAILED: Expected 6:137, but got ${result.surah}:${result.ayah}');
  }
}
