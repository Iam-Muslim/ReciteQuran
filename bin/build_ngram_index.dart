import 'dart:convert';
import 'dart:io';

import '../lib/tracking/matchers/phoneme_chunker.dart';
import '../lib/tracking/matchers/anchor.dart';

void main() async {
  print('Building N-gram index offline...');

  final File quranFile = File('assets/model/ordered_quran_phonemes.json');
  final String quranJson = await quranFile.readAsString();
  final Map<String, dynamic> quranData = jsonDecode(quranJson);

  final int ngramSize = 4;
  final Map<String, List<Map<String, int>>> ngramPositions = {};
  final Map<String, int> ngramCounts = {};

  quranData.forEach((key, value) {
    // key is "1:1"
    final parts = key.split(':');
    final surah = int.parse(parts[0]);
    final ayah = int.parse(parts[1]);

    final String ayaPhoneme = value['aya_phoneme'];
    // Strip spaces if any
    final String cleanAya = ayaPhoneme.replaceAll(' ', '');

    final chunks = PhonemeChunker.chunkPhonemes(cleanAya);
    if (chunks.length < ngramSize) return;

    for (int i = 0; i <= chunks.length - ngramSize; i++) {
      final ngram = chunks.sublist(i, i + ngramSize).join('|');
      
      // Update counts
      ngramCounts[ngram] = (ngramCounts[ngram] ?? 0) + 1;
      
      // Update positions
      ngramPositions.putIfAbsent(ngram, () => []);
      
      // Prevent duplicate ayah entries for the same ngram in the same ayah
      bool alreadyInAyah = false;
      for (var loc in ngramPositions[ngram]!) {
        if (loc['s'] == surah && loc['a'] == ayah) {
          alreadyInAyah = true;
          break;
        }
      }
      
      if (!alreadyInAyah) {
        ngramPositions[ngram]!.add({'s': surah, 'a': ayah});
      }
    }
  });

  final Map<String, dynamic> output = {
    'ngramSize': ngramSize,
    'ngramCounts': ngramCounts,
    'ngramPositions': ngramPositions,
  };

  final File outFile = File('assets/model/ngram_index.json');
  await outFile.writeAsString(jsonEncode(output));
  print('Saved N-gram index to ${outFile.path} (Size: ${outFile.lengthSync() / 1024 / 1024} MB)');
}
