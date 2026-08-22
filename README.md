<div align="center">

# وما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ

# ReciteQuran — اتلو القران
Flutter Package

A high-performance, real-time on-device **Quran recitation tracking** and **deterministic Tajweed verification engine** for Flutter applications.

---

## Key Features

* **Continuous Recitation Tracking**: Zero-lag real-time word tracking powered by semi-global Dynamic Time Warping (DTW) and custom causal Zipformer CTC acoustic models.
* **Deterministic Tajweed Evaluation**:
  * **Madd Rules (1–7)**: Validates elongation duration (2, 4, 6 Harakat) against acoustic timestamps.
  * **Mushaddad Ghunnah (10)**: Verifies 2-Harakah nasal holding on Mushaddad Noon & Meem.
  * **Shaddah (9)**: Inspects consonant closure duration (~1.5 Harakat) and doubling.
* **100% Offline**: Audio is processed entirely on the user's device.
* **Cross-Platform**: Seamless support for Android, iOS, Windows, macOS, Linux, and Web (WASM/WebAssembly).
* **Automated Asset Management**:
  * Built-in on-demand background model downloading (`ModelLoader`) to keep initial app install size under 15MB.
  * Works with pre-bundled assets, auto-download, or custom external downloaders.
* **Configurable Difficulty Matrix**: Tune thresholds dynamically using `TrackerConfig.normal()`, `.easy()`, or `.strict()`.

---

## How to Add to Your Project

### Option A: From pub.dev
```yaml
dependencies:
  recite_quran: ^1.0.0
```

### Option B: Directly from GitHub
```yaml
dependencies:
  recite_quran:
    git:
      url: https://github.com/Iam-Muslim/ReciteQuran.git
```

---

## 💻 Quick Usage & Integration Guide

```dart
import 'package:recite_quran/recite_quran.dart';

void main() async {
  // 1. Initialize Quran Metadata Repository
  final repository = QuranRepository(QuranMetadataService());
  await repository.loadSurahAsync(1); // Pre-load Surah Al-Fatihah

  // 2. Instantiate ReciteQuran Tracker
  final tracker = ReciteQuran(
    repository: repository,
    config: TrackerConfig.normal(), // or .easy() / .strict()
    isTajweed: true,
  );

  // 3. Initialize engine (automatically downloads model if missing!)
  await tracker.initialize(
    onDownloadProgress: (progress) {
      print('Model download: ${(progress * 100).toInt()}%');
    },
  );

  // 4. Set Surah Al-Fatihah
  tracker.setTargetSurah(1);

  // 5. Listen to recitation events
  tracker.onWordMatched.listen((event) {
    print('Matched Word #${event.wordId} in Surah ${event.surahNumber}');
    if (event.isRed) {
      print('Speech error detected on word!');
    }
  });

  // 6. Feed audio from microphone (16 kHz mono Float32 chunks)
  // tracker.feedAudioChunk(pcmAudioChunk);
}
```

---

## 📦 Model Asset Management (3 Flexible Ways)

### 1. Automatic On-Demand Download (Default & Recommended)
Keeps your app install size tiny (< 15MB) on the Play Store / App Store:
```dart
await tracker.initialize(
  onDownloadProgress: (p) => print('${(p * 100).toInt()}%'),
);
```

### 2. Pre-Bundled in Assets
If you prefer to include the 72.7MB model inside your app build:
```yaml
# In your pubspec.yaml
flutter:
  assets:
    - assets/model/zipformer_p_arabic_v3.int8.onnx
```
```dart
await tracker.initialize(
  bundledAssetPath: 'assets/model/zipformer_p_arabic_v3.int8.onnx',
);
```

### 3. Custom External Downloader
If you use your own background downloader (e.g. `dio`, `background_downloader`):
```dart
await tracker.initialize(
  onnxModelPath: '/path/to/my_downloaded_model.onnx',
);
```

---

## ⚙️ Configuration & Difficulty Presets

Customize math costs, thresholds, and Tajweed timing at runtime:

```dart
// Easy mode for beginners / children:
tracker.updateConfig(TrackerConfig.easy());

// Strict mode for certification exams:
tracker.updateConfig(TrackerConfig.strict());

// Custom tuning:
tracker.updateConfig(
  TrackerConfig(
    defaultMaxPathCost: 0.30,
    harakatDurationSeconds: 0.250,
    hideExpectedAsrNoise: true,
  ),
);
```

---

## 📖 Tajweed Error Output

When `isTajweed: true` is enabled, each matched word carries full duration and defect diagnostics:

```dart
tracker.onWordMatched.listen((event) {
  for (final error in event.tajweedErrors) {
    print('Rule: ${error.expectedRule?.name.ar}');
    print('Expected Duration: ${error.expectedDuration}s');
    print('Actual Duration: ${error.actualDuration}s');
    print('Status: ${error.durationStatus}'); // defect, excess, or valid
  }
});
```

---

## 📱 Interactive Example App & Reference

The complete, production-ready sample application using this package is located in the [`example/`](example/) directory and at the GitHub repository:

👉 **[Iam-Muslim/Natlu: الحمد لله رب العالمين](https://github.com/Iam-Muslim/Natlu)**

### How to Run the Example App Locally:
```bash
cd example
flutter pub get
flutter run -d chrome    # Web (with full WASM support)
flutter run -d windows   # Windows Desktop
flutter run -d android   # Android Phone
```

---

## (لوجه الله تعالى)

### **ما أسألكم عليه من أجر إن أجري إلا على رب العالمين**

> **THIS PACKAGE AND SOURCE CODE ARE DEDICATED FOR THE SAKE OF ALLAH ALONE.**

Before viewing, using, distributing, or modifying any part of this repository, you explicitly agree to the following sacred covenants:

1. **100% Free to End Users**:
   You may use, study, and redistribute this software or its logic **ONLY** in applications and services that are completely free of charge to all end users forever.
2. **Strict Prohibition on Commercialization & Profit**:
   You are **STRICTLY FORBIDDEN** from selling this application, placing it behind paywalls, subscription models, in-app purchases, charging download fees, monetizing it with advertisements (AdMob, Unity Ads, etc.), or extracting any financial revenue from this codebase, models, or outputs.
3. **Pass-Through**:
   These terms are immutable and strictly pass on to any fork, derivative work, or redistributed component.

---

*Alhamdulillah (الحمد لله رب العالمين)* — research and work from the following open-source projects:

- **[Zipformer Quran Streaming Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother - Mustafa 
- **[quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript)** by Brother - Abdullah Aml
- **[Quranic Universal Aligner (qua_sdk)](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner)** by Brother - Ahmad Ibrahim

---

<div align="center">

**هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم**

</div>
