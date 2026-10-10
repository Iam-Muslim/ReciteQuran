# 📦 Neural Model & Assets Deployment Guide (On-Demand vs Bundled)

A comprehensive guide for managing the **69MB ONNX neural acoustic model** (`zipformer_p_arabic_v3.int8.onnx`) and Quranic phoneme assets in **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Overview: The Dual-Deployment Strategy](#1-overview-the-dual-deployment-strategy)
2. [Strategy A: On-Demand Streaming Download (Recommended for Small App Store Size)](#2-strategy-a-on-demand-streaming-download)
3. [Strategy B: Manual Asset Bundling (100% Offline-First, Zero-Network)](#3-strategy-b-manual-asset-bundling)
4. [File Integrity & Storage Locations per Platform](#4-file-integrity--storage-locations-per-platform)
5. [Lightweight Bundled Metadata Assets](#5-lightweight-bundled-metadata-assets)
6. [Complete 1-File Model Downloader Screen (Flutter)](#6-complete-1-file-model-downloader-screen-flutter)
7. [Production Best Practices & Troubleshooting](#7-production-best-practices--troubleshooting)

---

## 1. Overview: The Dual-Deployment Strategy

The neural acoustic model powering `recite_quran` is a quantized **Zipformer2 CTC** model ($\approx 69\text{MB}$) trained on tens of thousands of hours of Quranic recitation.

Mobile app publishers face a choice between two deployment architectures:

| Feature | Strategy A: On-Demand Streaming | Strategy B: Manual Asset Bundling |
| :--- | :--- | :--- |
| **Initial App Install Size** | **Minimal ($\approx 10-15\text{MB}$)** | Larger ($\approx 80-90\text{MB}$) |
| **First Launch Experience** | Requires a quick 69MB download | **Instant 0-second launch** |
| **Network Requirement** | Requires internet on first launch only | **100% Offline from day one** |
| **App Store Optimization (ASO)**| Higher install conversions (small download) | Ideal for remote areas without internet |
| **Recommended For** | Consumer apps, App Store / Play Store | Airplane mode apps, offline kiosks |

---

## 2. Strategy A: On-Demand Streaming Download

In Strategy A, the app binary does not include the heavy `.onnx` file. Instead, the app uses **`ModelDownloader`** ([`lib/data/model_downloader.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/data/model_downloader.dart)) to download the model once to the user's device during onboarding or on first launch.

### Step 1: Check if Model is Already Downloaded
```dart
import 'package:recite_quran/recite_quran.dart';

final downloader = ModelDownloader();
final bool isReady = await downloader.isModelReady();

if (isReady) {
  print('Model is verified on disk! Launching recitation engine...');
} else {
  print('Model missing. Showing download progress screen...');
}
```

### Step 2: Stream Download with Real-Time Progress
```dart
await downloader.downloadModel(
  onProgress: (int receivedBytes, int totalBytes) {
    if (totalBytes > 0) {
      final double progress = receivedBytes / totalBytes;
      print('Downloading ASR model: ${(progress * 100).toStringAsFixed(1)}%');
    }
  },
);
```

Once downloaded, `ModelDownloader` caches the file permanently. Subsequent app launches will return `isModelReady() == true` instantly.

---

## 3. Strategy B: Manual Asset Bundling (100% Offline-First)

If your app must work immediately out-of-the-box without requiring any internet connection on first launch:

### Step 1: Download the Neural Model File
Download `zipformer_p_arabic_v3.int8.onnx` from either official mirror:
- **HuggingFace:** [https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)
- **GitHub Release Mirror:** [https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/zipformer_p_arabic_v3.int8.onnx](https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/zipformer_p_arabic_v3.int8.onnx)

### Step 2: Place in Your Project Assets
Place the downloaded file in your Flutter app's assets folder:
```
my_quran_app/
└── assets/
    └── model/
        └── zipformer_p_arabic_v3.int8.onnx   <-- Place file here
```

### Step 3: Declare in `pubspec.yaml`
```yaml
flutter:
  assets:
    - assets/model/zipformer_p_arabic_v3.int8.onnx
```

### How the Engine Resolves Bundled Assets
`SherpaEngine` automatically inspects the local asset bundle first. If the file is bundled inside the app, it **skips network downloads completely** and boots up the neural engine immediately.

---

## 4. File Integrity & Storage Locations per Platform

When using on-demand download, `ModelDownloader` saves the asset in the standard application documents directory under `recite_quran_assets/`:

| Platform | Destination Storage Path |
| :--- | :--- |
| **Android** | `/data/user/0/<package_name>/app_flutter/recite_quran_assets/` |
| **iOS** | `/var/mobile/Containers/Data/Application/<UUID>/Documents/recite_quran_assets/` |
| **Windows** | `C:\Users\<User>\AppData\Local\<App>\recite_quran_assets\` |
| **macOS** | `~/Library/Containers/<App>/Data/Documents/recite_quran_assets/` |
| **Linux** | `~/.local/share/<App>/recite_quran_assets/` |

### Integrity Verification
The engine verifies that the file exists and exceeds **$10\text{MB}$** (preventing truncated downloads or corrupted partial files from crashing the C++ ONNX runtime).

---

## 5. Lightweight Bundled Metadata Assets

While the neural model is $69\text{MB}$, all other metadata files are extremely lightweight and are already bundled directly inside `package:recite_quran`:

| Asset File | Size | Purpose |
| :--- | :-: | :--- |
| `tokens.txt` | $\approx 2\text{KB}$ | Character-to-index vocabulary for the Zipformer tokenizer |
| `ordered_quran_phonemes.json` | $\approx 1.2\text{MB}$ | Word-by-word phonemes & Tajweed rules for Hafs |
| `ref_norm_ph.txt` | $\approx 600\text{KB}$ | Pre-normalized phonetic string for 6,236 Ayah voice search |
| `ph_index.npy` | $\approx 50\text{KB}$ | Ayah offset lookup index for Myers bit-parallel search |
| `riwayat.json` | $\approx 3\text{KB}$ | Canonical metadata descriptors for the 20 Mutawatir Rawis |

---

## 6. Complete 1-File Model Downloader Screen (Flutter)

Here is a complete, production-ready Flutter onboarding screen that verifies model status, shows an animated progress bar, handles network interruptions, and transitions to the main app:

```dart
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

class ModelDownloadScreen extends StatefulWidget {
  final Widget nextScreen;

  const ModelDownloadScreen({super.key, required this.nextScreen});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  final ModelDownloader _downloader = ModelDownloader();
  double _progress = 0.0;
  String _statusText = 'Checking recitation engine assets...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _checkAndDownload();
  }

  Future<void> _checkAndDownload() async {
    setState(() {
      _hasError = false;
      _statusText = 'Checking model files...';
    });

    final bool isReady = await _downloader.isModelReady();
    if (isReady) {
      _navigateToNextScreen();
      return;
    }

    // Begin on-demand download
    setState(() {
      _statusText = 'Downloading neural recitation model (~69MB)...';
    });

    final bool success = await _downloader.downloadModel(
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() {
            _progress = received / total;
          });
        }
      },
    );

    if (success && mounted) {
      _navigateToNextScreen();
    } else if (mounted) {
      setState(() {
        _hasError = true;
        _statusText = 'Download failed. Please check your internet connection.';
      });
    }
  }

  void _navigateToNextScreen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic_none, size: 64, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                'Setting Up Recitation AI',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(color: _hasError ? Colors.red : Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              if (!_hasError) ...[
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                const SizedBox(height: 12),
                Text('${(_progress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
              ] else ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Download'),
                  onPressed: _checkAndDownload,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 7. Production Best Practices & Troubleshooting

1. **Cellular Data Warning:** When downloading on cellular connections, notify users with a dialog before starting the 69MB download.
2. **Never Delete Cached Assets:** Once downloaded, do not delete `recite_quran_assets/` during app cache cleans.
3. **App Updates:** Model weights remain valid across package patch updates. The engine will not re-download the model unless the filename changes.
4. **Offline Resilience:** Once downloaded, `recite_quran` operates **100% offline with zero network connectivity** required   .
