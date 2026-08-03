# Android to Web Synchronization Guide for ReciteQuran

This document is a technical blueprint for synchronizing the **ReciteQuran** Web application (`ReciteQuran-web`) whenever the main Android repository (`ReciteQuran`) is updated.

---

## 1. Architectural Differences: Android vs Web

| Component | Android (`ReciteQuran`) | Web (`ReciteQuran-web`) |
| :--- | :--- | :--- |
| **ASR Engine** | Native C++ `.so` via `package:sherpa_onnx` (FFI) | WebAssembly (`sherpa-onnx-wasm-main-asr.wasm`) via `dart:js_interop` |
| **Audio Capture** | `package:record` + `package:audio_session` | Web Audio API (`navigator.mediaDevices.getUserMedia` + ScriptProcessor/Worklet) |
| **Background Threading** | `dart:isolate` (`Isolate.spawn`, `ReceivePort`, `SendPort`) | Reactive `StreamController` command queue on the browser event loop |
| **Model Storage** | Embedded in APK assets / internal storage | IndexedDB (`SherpaModelDB`) + Local Asset / `/download-model` HTTP proxy |
| **Native-only Plugins** | `permission_handler`, `flutter_displaymode`, `in_app_update`, `wakelock_plus` | Omitted or replaced with standard web APIs |

---

## 2. File Categories & Synchronization Rules

### Category A: 100% Direct Copy (Pure Dart / Algorithm Files)
These files can be copied directly from Android to Web with zero modifications:
- `lib/tracking/word/dictation_matcher.dart` (Forward DP engine, Case 2 Acoustic Shield)
- `lib/tracking/word/phoneme_matrix.dart` (Flattened Float64List alignment matrix)
- `lib/tracking/word/quran_normalizer.dart` (Phoneme tokenization and normalization)
- `lib/tracking/tajweed/tajweed_rules.dart` (Timing and strictness thresholds)
- `lib/tracking/tajweed/error_explainer.dart` (Tajweed error classifier)
- `lib/tracking/ayah_search/fuzzy_search.dart` (Levenshtein search)
- `lib/tracking/ayah_search/voice_search_controller.dart` (Phonetic Ayah navigation)
- `lib/utils/debug_logger.dart` (Structured logging utility)
- `lib/data/quran_data.dart` (Quran metadata, database loader)

---

### Category B: Copy with Minor Platform Strip
- **`lib/tracking/ayah_search/phonetic_search.dart`**:
  - Remove any `import 'dart:io';`.
  - Ensure all file loading uses `rootBundle.load` and `rootBundle.loadString`.
  - Remove any standalone test methods using `dart:io` `File`.

---

### Category C: Web-Specialized Files (DO NOT Overwrite Directly)
Do not overwrite these files with the Android versions directly; maintain their Web adapters:

1. **`lib/engine/sherpa_engine.dart`**:
   - Must use `dart:js_interop` bindings (`startOfficialSherpa`, `stopOfficialSherpa`, `resetOfficialSherpaBuffer`, `_writeSherpaAssetToVFS`, `_initSherpaRecognizer`, `_fetchSherpaModel`).
   - Must load the ONNX model dynamically from `Uri.base.resolve(...)` (local) or `/download-model` (production).

2. **`lib/tracking/word/phoneme_alignment.dart`**:
   - Uses `StreamController<PhonemeAlignmentCommand>` and `Stream<PhonemeAlignmentResult>` instead of `Isolate.spawn`.

3. **`lib/tracking/word/highlighting_controller.dart`**:
   - Listens to `PhonemeAlignmentWorker.results` stream rather than `ReceivePort`.

4. **`lib/main.dart` & `lib/ui/tracking_screen.dart`**:
   - Native-only services (`FlutterDisplayMode`, `AudioSession`, `InAppUpdate`) are excluded.
   - Microphone activation triggers `SherpaEngine.instance.start()` which hooks the browser's `getUserMedia`.

---

## 3. Updating the AI Model File

When the ONNX model changes (e.g. from version `X` to `Y`):
1. **Copy Model Asset:**
   Place the new `.onnx` file into `assets/model/` (e.g., `assets/model/zipformer_p_arabic_v2.int8.onnx`).
2. **Update `pubspec.yaml`:**
   Ensure the new filename is listed under `flutter.assets`.
3. **Update `lib/engine/sherpa_engine.dart`:**
   Update the filename passed to `_writeSherpaAssetToVFS` and the local asset URL.
4. **Update `web/sherpa-onnx-asr.js`:**
   Update `onlineZipformer2CtcModelConfig.model = './<new_model_name>.onnx';`.
5. **Update `functions/download-model.js`:**
   Update the GitHub release URL pointing to the new model release.
6. **Update `build.sh`:**
   Update the `rm -f build/web/assets/assets/model/<new_model_name>.onnx` stripping line.

---

## 4. Verification Checklist

After every sync:
```powershell
# 1. Run static analysis (must report 0 issues)
flutter analyze

# 2. Test local compilation
flutter build web --release --base-href "/"
```
