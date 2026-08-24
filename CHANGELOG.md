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
