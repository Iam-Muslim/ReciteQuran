## 1.0.4

* **FEAT (Dictation & Loss-of-Tracking Recovery)**: Added `enableAutoReanchor` and `enableEarlyMatching` to `TrackerConfig` with Multi-Stage Window Probing and the Anti-Ambiguity Guard ($\Delta\text{dist} < 3$) preventing false jumps across repeated refrains (Surah Ar-Rahman).
* **FEAT (Tajweed Engine)**: Complete overhaul of the acoustic verification engine with a strict compile-time `AcousticThreshold` matrix across all recitation speeds (`Tahqiq`/`Tartil`, `Tadweer`, `Hadr`).
* **FEAT (Tajweed)**: Multi-Madd span matching support (e.g. Lazem + Aared in "الضَّآلِّينَ") and legitimate Aared Madd Qasr/Tawassut/Tool allowance.
* **FEAT (Tajweed)**: Pro-rated character duration distribution for multi-phoneme ASR CTC spikes, zero-duration safety shields, and glyph equivalence matching in `PhoneticCostEngine`.
* **FEAT (UI & DX)**: Enhanced `ReciterError` with localized message & advice helpers (`messageAr`, `messageEn`, `adviceAr`, `adviceEn`), clean JSON serialization (`toMap`/`fromMap`), while preserving full raw telemetry for custom UIs.
* **FEAT (UI)**: Added built-in `showTajweedErrorSheet` and `TajweedErrorSheet` widget for 1-line drop-in Islamic modal bottom sheets with automatic dark/light theme adaptation.
* **FEAT (Multi-Riwayah & Qira'at)**: Comprehensive cross-Riwayah and cross-madhhab ayah mapping via `QiraatAyahMapper`, `RiwayaRegistry`, `RiwayaDescriptor`, and `AyahMappingDownloader`, supporting all 6 canonical counting madhhabs (6,236 down to 6,204 ayahs) and 20 mutawatir rawis sourced from Quranpedia.
* **FEAT (Omission Detection)**: Added `LcsOmissionDetector` and `OmissionResult` using the 2-row dynamic-programming Best-Drop LCS algorithm (derived from `tasmee3-muaalem-findings` benchmark research) for precise word omission localization.
* **FEAT (Assets & Networking)**: Built-in `ModelDownloader` for streaming on-demand neural model download (~72 MB), keeping initial app download size under 25 MB.
* **FEAT (Voice Navigation)**: Overhauled `VoiceSearchController` with real-time candidate Ayah streaming (`onSearchResult`, `currentResult`), progressive narrowing auto-jump, Mutashabihat (متشابهات) disambiguation, and `AyahSearchMatch` metadata enrichment.
* **DOC**: Added 12 comprehensive modular engineering guides in `doc/` covering Dictation, Tajweed, Voice Search, Tarteel-style Memorization Mode, Production Audio Pipeline, Mus'haf UI & Typography, Multi-Riwayah, Neural Model Deployment, API Reference Cheat Sheet, and Troubleshooting FAQ.
* **TEST**: Added regression test suite `test/auto_reanchor_test.dart` covering 5 critical scenarios.
## 1.0.3

* **FEAT**: Enabled official platform classification for Windows and Linux on pub.dev.
* **REFACTOR**: Streamlined `AudioProcessor` by removing redundant mobile-only `audio_session` dependency in favor of direct cross-platform recording via `record`.

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
