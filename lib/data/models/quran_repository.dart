// In-memory Quran repository.
//
// Wraps the full flat verse list loaded from [assets/model/quran.json]
// and exposes fast, cached per-surah access.


import '../quran_metadata_service.dart';
import 'quran_data.dart';

class QuranRepository {
  final QuranMetadataService _service;

  List<QuranVerse> _allVerses = [];
  bool _isLoaded = false;

  QuranRepository(this._service);

  List<QuranVerse> get verses => _allVerses;

  Future<void> loadSurahAsync(int surah) async {
    if (_isLoaded) return;
    _allVerses = await _service.loadAll();
    _isLoaded = true;
  }

  final Map<int, List<QuranVerse>> _surahCache = {};

  List<QuranVerse> getSurah(int surah) {
    if (!_isLoaded) return [];

    // Return the cached list instantly, or build it if it doesn't exist yet
    return _surahCache.putIfAbsent(
      surah,
      () => _allVerses.where((v) => v.surah == surah).toList(),
    );
  }

  QuranVerse? getVerse(int surah, int ayah) {
    if (!_isLoaded) return null;
    try {
      return _allVerses.firstWhere((v) => v.surah == surah && v.ayah == ayah);
    } catch (_) {
      return null;
    }
  }
}
