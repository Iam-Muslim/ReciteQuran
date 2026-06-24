# Audio Pipeline — `lib/audio/audio_processor.dart`

## Purpose

The `AudioProcessor` is the first step in the pipeline. Its job is to:

1. Open the microphone
2. Detect when you start speaking (Voice Activity Detection / VAD)
3. Package the speech audio into fixed-size chunks
4. Send those chunks to the ASR engine

It is intentionally "dumb" — it does not know anything about Quran or words. It only understands: silence vs. noise.

---

## VAD: How Does It Know You Started Talking?

The VAD is an adaptive energy threshold tracker.

### Step 1: RMS Energy Per Frame

Every 20ms (a "frame") of audio is read. The processor computes the **RMS (Root Mean Square)** of the audio samples in that frame:

```
RMS = sqrt( (s1² + s2² + ... + sN²) / N )
```

RMS is basically the "loudness" of that 20ms slice. Silence might be RMS=40. Normal speech is RMS=300-800. A loud voice is RMS=1500+.

### Step 2: Adaptive Noise Floor

When you are NOT speaking, the processor updates a "noise floor" — a moving average of how loud the background ambient noise is:

```
noiseFloor = (1 - 0.05) × noiseFloor + 0.05 × currentRMS
```

This means if you are in a quiet room, the noise floor is ~40-60. In a loud environment, it adapts to ~200-300. **This makes the VAD work in noisy environments without configuration.**

### Step 3: Threshold Decision

```
vadThreshold = noiseFloor × 2.0   (SNR = 2x)
```

- If `currentRMS > vadThreshold` → **SPEAKING**
- If `currentRMS < vadThreshold` → **SILENT**

### Step 4: Silence Timeout

The VAD doesn't immediately stop when you pause. It waits for **40 consecutive silent frames (800ms)** before declaring the phrase ended. This prevents pauses between words from fragmenting the stream.

---

## Pre-Roll Buffer

There is a 600ms "pre-roll" buffer. The last 30 frames before speech is detected are stored. When speech starts, those frames are prepended to the first chunk sent to the ASR engine.

**Why?** The first consonant of a word often has very low energy (especially stops like `ب`, `ت`). Without pre-roll, the model might miss the `بِ` in `بِسمِ`.

---

## Chunk Size

Speech frames are buffered and emitted to the ASR engine in **160ms chunks** (not individual 20ms frames). This is the minimum chunk size the ZipFormer model needs for stable output. Smaller chunks = more latency-sensitive but faster response.

```
Timeline: [20ms][20ms][20ms][20ms][20ms][20ms][20ms][20ms] → emit 160ms chunk to Sherpa
```

---

## Configuration Reference

| Constant | Value | Meaning |
|---|---|---|
| `sampleRate` | 16000 Hz | Model requirement |
| `frameMs` | 20ms | VAD granularity |
| `preRollMs` | 600ms | Audio before speech onset kept |
| `maxSilenceMs` | 800ms | Pause before phrase ends |
| `chunkMs` | 160ms | Chunk sent to ASR |
| `kAlpha` | 0.05 | Noise floor learning rate |
| `kSnrThreshold` | 2.0 | Speech must be 2x louder than noise |
