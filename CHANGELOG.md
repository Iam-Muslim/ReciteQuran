## 1.1.0

* **FEAT**: Added `LcsOmissionDetector` and `OmissionResult` using the 2-row dynamic-programming Best-Drop LCS algorithm (derived from `tasmee3-muaalem-findings` benchmark research) for precise word omission localization.
* **FEAT**: Added `WarshHafsMapper` and bundled `assets/json/warsh-to-hafs.json` (sourced from Quranpedia) for O(1) bidirectional ayah numbering and boundary mapping between Warsh (Madani-last) and Hafs (Kufi).
* **FEAT**: Added built-in `ModelDownloader` for background streaming on-demand model asset downloading and verification, reducing initial app binary size by ~85 MB.
* **FEAT**: Added `phonemeFilePath` override in `QuranMetadataService` and `assetOverrideDir` in `SherpaEngine` for custom dynamic model and phoneme paths.
* **FEAT**: Added flexible JSON schema key fallbacks in `QuranVerse` (`uthmani`, `aya_text`, `phoneme_words`).
* **CHORE**: Added unit test suite in `test/` for omission detection, Warsh mapping, custom asset loading, and model downloading.
* **CHORE**: Broadened `record` dependency constraint to `>=6.0.0 <8.0.0` for wider Flutter & Dart SDK compatibility.

## 1.0.2

* **FIX**: Restored baseline DTW endpoint alignment in `QuranDictationMatcher` to ensure complete word phonetic consumption and eliminate trailing phoneme bleed.
* **FIX**: Removed experimental lookahead guard in `DictationSequencer`.
* **DOC**: Documented streaming alignment and fast-committing mechanisms in `QuranDictationMatcher`.

## 1.0.1

* **FIX**: Drastically improved DTW alignment stability on Waqf for short words containing Shaddah (e.g. `رَبِّ`) and Madd (e.g. `الرَّحِيمِ`).
* **FIX**: Improved `ErrorExplainer` to correctly honor Waqf (Sukoon), preventing false `NORMAL -> DELETE` and `TASHKEEL` errors when pausing at the end of a word.

## 1.0.0

* Initial open-source release of **`recite_quran`**.
* Real-time continuous recitation tracking with Semi-Global Dynamic Time Warping (DTW).
* Deterministic Tajweed rule verification engine:
  - Madd duration evaluation (2, 4, 6 Harakat).
  - Mushaddad Ghunnah verification (Noon & Meem).
  - Shaddah consonant closure & timing verification.
* Cross-platform support (Android, iOS, Windows, macOS, Linux, and Web).
* Automated on-demand model downloader and caching via `ModelLoader`.
* Developer CLI tool for pre-bundling models: `dart run recite_quran:model_loader`.
* Configurable difficulty matrix (`TrackerConfig.normal()`, `.easy()`, `.strict()`).
