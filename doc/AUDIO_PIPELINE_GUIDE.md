# 🎙️ Production Audio & Microphone Architecture Guide

A comprehensive architectural and systems guide for building robust, studio-grade audio capture pipelines for Quran recitation applications using **`package:recite_quran`**.

---

## 📑 Table of Contents

1. [Audio Architecture Overview](#1-audio-architecture-overview)
2. [Acoustic Requirements of Quranic Speech Recognition](#2-acoustic-requirements-of-quranic-speech-recognition)
3. [The Critical Pitfall: Hardware DSP Filters (AEC / AGC / NS)](#3-the-critical-pitfall-hardware-dsp-filters-aec--agc--ns)
   - [Why Standard Noise Suppression Ruins Tajweed](#why-standard-noise-suppression-ruins-tajweed)
   - [How `AudioProcessor` Configures Raw Audio](#how-audioprocessor-configures-raw-audio)
4. [Platform Permissions & Manifest Configuration](#4-platform-permissions--manifest-configuration)
   - [Android (14+ Foreground Service & Audio)](#android-14-foreground-service--audio)
   - [iOS (AVAudioSession & Info.plist)](#ios-avaudiosession--infoplist)
   - [macOS (Hardened Runtime Entitlements)](#macos-hardened-runtime-entitlements)
   - [Windows & Linux](#windows--linux)
   - [Flutter Web (getUserMedia Constraints)](#flutter-web-getusermedia-constraints)
5. [Handling Audio Interruptions & Hardware Transitions](#5-handling-audio-interruptions--hardware-transitions)
   - [Incoming Phone & VOIP Calls](#incoming-phone--voip-calls)
   - [Bluetooth AirPods & Headset Switching](#bluetooth-airpods--headset-switching)
   - [App Lifecycle (Backgrounding & Locking)](#app-lifecycle-backgrounding--locking)
6. [Complete Production Audio Manager Implementation (Flutter)](#6-complete-production-audio-manager-implementation-flutter)
7. [Production Checklist & Troubleshooting](#7-production-checklist--troubleshooting)

---

## 1. Audio Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                 Hardware Microphone Capsule                 │
│              (Mobile Mic, Bluetooth, USB, Web)              │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Native 44.1kHz / 48kHz PCM)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│               AudioProcessor (Record Plugin)                │
│  - Bypasses AEC (Echo Cancellation)                         │
│  - Bypasses AGC (Auto Gain Control)                         │
│  - Bypasses NS (Noise Suppression)                          │
│  - Hardware-resamples to 16,000 Hz Mono 16-bit PCM          │
└──────────────────────────────┬──────────────────────────────┘
                               │ (480ms / 15,360 Byte Chunks)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│               Float32 Linear Normalization                  │
│       Transforms Int16 [-32768, 32767] ➔ Float32 [-1.0, 1.0] │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 ReciteQuran SDK (SherpaEngine)              │
│       Feeds Float32 buffer into Zipformer neural model      │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Acoustic Requirements of Quranic Speech Recognition

The quantized ONNX Zipformer acoustic model expects audio matching these exact parameters:

| Parameter | Specification | Purpose |
| :--- | :--- | :--- |
| **Sample Rate** | **16,000 Hz (16 kHz)** | Standard speech recognition bandwidth |
| **Channels** | **1 (Mono)** | Voice is a single point source |
| **Bit Depth** | **16-bit Little Endian PCM** | Linear PCM representation |
| **Float Format** | **Normalized Float32 `[-1.0, 1.0]`** | Neural tensor input format |
| **Chunk Window** | **480 ms (7,680 float samples)** | Optimal causal receptive field |

---

## 3. The Critical Pitfall: Hardware DSP Filters (AEC / AGC / NS)

Standard mobile VoIP apps (like WhatsApp, Zoom, or Google Meet) enable three aggressive hardware Digital Signal Processors (DSP):
1. **AEC (Acoustic Echo Cancellation)**
2. **AGC (Automatic Gain Control)**
3. **NS (Noise Suppression)**

### Why Standard Noise Suppression Ruins Tajweed

In Quranic recitation, enabling standard DSP filters produces catastrophic recognition failures:

#### 1. Muffled Hams Letters (حروف الهمس)
Letters like `هـ` (Haa), `ح` (Haa'), `ث` (Thaa), and `ش` (Sheen) rely on gentle breath friction through the vocal tract. Standard noise suppressors mistake this natural air escape for background room hiss or wind noise, filtering it out and causing the ASR model to miss the consonant.

#### 2. Madd Elongation Truncation (قطع المدود)
When a reciter holds an elongated vowel for 4 to 6 Harakat (e.g., *الضَّالِّينَ* or *جَاءَتْ*), standard VoIP algorithms interpret sustained acoustic frequencies as background hum and artificially compress or attenuate the amplitude after 300ms. This prevents the Tajweed engine from measuring the true vowel duration!

#### 3. Ghunnah Nasal Distortion (تشويه الغنة)
Nasal resonance on Mushaddad Noon and Meem (`نّ`, `مّ`) produces distinct harmonic overtones that standard aggressive voice compressors flatten.

### How `AudioProcessor` Configures Raw Audio

In [`lib/audio/audio_processor_io.dart`](file:///d:/there%20is%20no%20god%20unless%20ALLAH/Playstore/ReciteQuran/lib/audio/audio_processor_io.dart), hardware filters are strictly turned off:

```dart
final recordStream = await _recorder!.startStream(
  const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: false,       // DO NOT compress vowel dynamics
    echoCancel: false,     // DO NOT suppress steady frequencies
    noiseSuppress: false,  // DO NOT filter gentle breath consonants
  ),
);
```

---

## 4. Platform Permissions & Manifest Configuration

### Android (14+)

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Mandatory for microphone access -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

    <!-- Optional: If recitation tracking continues when screen turns off -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application ...>
        <!-- Service declaration if using foreground recording -->
    </application>
</manifest>
```

### iOS

Edit `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to listen to your Quran recitation and provide real-time Tajweed and pronunciation feedback.</string>
```

### macOS

Add the microphone entitlement in:
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Windows & Linux
No manifest permissions required. Desktop platforms directly access system audio devices via native PortAudio or WASAPI drivers.

### Flutter Web
Ensure the browser requests permissions via HTTPS. Local development is permitted on `localhost`.

---

## 5. Handling Audio Interruptions & Hardware Transitions

In real-world mobile apps, users experience audio events while reciting:
- Incoming telephone calls
- Alarms or countdown timers
- Connecting or disconnecting Bluetooth AirPods
- Leaving the app to check another screen

### Handling Audio Interruptions Gracefully

```dart
class AppAudioLifecycleObserver with WidgetsBindingObserver {
  final AudioProcessor audioProcessor;
  final ReciteQuran tracker;

  AppAudioLifecycleObserver({required this.audioProcessor, required this.tracker});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Pause mic stream to preserve battery when user leaves app
      audioProcessor.stop();
      tracker.resetBuffer();
    } else if (state == AppLifecycleState.resumed) {
      // Prompt user to tap mic to resume recitation
    }
  }
}
```

---

## 6. Complete Production Audio Manager Implementation (Flutter)

Here is a robust, production-grade audio manager wrapper that handles permission checks, audio chunk feeding, and graceful error handling:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:recite_quran/recite_quran.dart';

enum AudioCaptureState {
  stopped,
  starting,
  recording,
  paused,
  error,
}

class QuranAudioManager {
  final AudioProcessor _processor = AudioProcessor();
  final ReciteQuran tracker;

  AudioCaptureState _state = AudioCaptureState.stopped;
  AudioCaptureState get state => _state;

  final ValueNotifier<AudioCaptureState> stateNotifier =
      ValueNotifier<AudioCaptureState>(AudioCaptureState.stopped);

  QuranAudioManager({required this.tracker});

  /// Checks if microphone access has been granted by the OS.
  Future<bool> checkPermission() async {
    try {
      return await _processor.hasPermission();
    } catch (e) {
      debugPrint('Error checking audio permission: $e');
      return false;
    }
  }

  /// Starts streaming raw audio into the recitation engine.
  Future<bool> start() async {
    if (_state == AudioCaptureState.recording) return true;

    _updateState(AudioCaptureState.starting);

    final bool hasPerm = await checkPermission();
    if (!hasPerm) {
      _updateState(AudioCaptureState.error);
      return false;
    }

    try {
      await _processor.start(
        onChunk: (Float32List chunk, bool isFinal) {
          tracker.feedAudioChunk(chunk, isFinal: isFinal);
        },
      );
      _updateState(AudioCaptureState.recording);
      return true;
    } catch (e) {
      debugPrint('Failed to start audio stream: $e');
      _updateState(AudioCaptureState.error);
      return false;
    }
  }

  /// Stops audio recording and resets tracking buffers.
  Future<void> stop() async {
    if (_state == AudioCaptureState.stopped) return;

    try {
      await _processor.stop();
      tracker.resetBuffer();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    } finally {
      _updateState(AudioCaptureState.stopped);
    }
  }

  void _updateState(AudioCaptureState newState) {
    _state = newState;
    stateNotifier.value = newState;
  }

  void dispose() {
    stop();
    stateNotifier.dispose();
  }
}
```

---

## 7. Production Checklist & Troubleshooting

- [x] **Verify Hardware Filters are Disabled:** Never turn on hardware echo cancellation or noise suppression for Quran recitation; it will clip Madd vowels and breath letters.
- [x] **Always Normalize Audio:** Feed audio in Float32 format scaled between `-1.0` and `+1.0`.
- [x] **Monitor Sample Rates:** On iOS, ensure the sample rate does not drop when Bluetooth AirPods connect (iOS often forces 8kHz Bluetooth SCO unless configured for wideband speech).
- [x] **Dispose on Route Pop:** Always stop the audio recorder and cancel streams when navigating away from recitation screens.
