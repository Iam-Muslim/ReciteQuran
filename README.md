# The Great Quran — القرآن العظيم
# Recite Quran - اتلو القران
# RealTime (Live Recording) Memorize Checking for the great Quran without internet connection.

**YOU ARE NOT ALLOWED TO SELL THIS APP OR GAIN ANY MONEY OR SUPPORTS FROM IT , IT IS ONLY FOR THE SAKE OF ALLAH THE GREATEST"**
**IF YOU USED ANY LOGIC , CODES , IDEAS OR ANYTHING FROM THIS PROJECT THEN YOU ARE NOT ALLOWED TO SELL THIS APP OR GAIN ANY MONEY OR SUPPORTS FROM IT , IT IS ONLY FOR THE SAKE OF ALLAH THE GREATEST**

##  Credits
Thanks to ALLAH only , elhamdule Allah

## Screenshots





______________________________________________________________________

##  Architecture

```
lib/
├── core/          # App-wide state, settings service, i18n strings, primitive types
├── data/          # Quran data models, repository, JSON database loader
├── engine/        # Sherpa-ONNX ASR engine (background Isolate) + token segmenter
├── utils/      # Levenshtein distance, DP alignment, Arabic normalizer, word matcher
├── recording/     # Microphone ring-buffer + live recitation state machine
└── screens/       # UI: tracking screen
```

---

##  Features
100% Offline - No API Usage

| Feature | Description |
|---|---|
|  **Live Recitation** | Real-time word-by-word green/red highlighting as you recite |
|  **100 % Offline ASR** | NeMo CTC model runs locally via Sherpa-ONNX — no internet required |
|  **All 114 Surahs** | Full Uthmani text with Scheherazde font |
|  **2 Themes** | White/Dark Themes
|  **Offline First** | All preferences stored locally via SharedPreferences |

---

### 1. Clone (with LFS)

```bash
git lfs install
git clone https://github.com/YOUR_USERNAME/the_great_quran.git
cd the_great_quran
git lfs pull   # downloads the 130 MB ONNX model
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run on device

```bash
flutter run --release      # release build recommended for real-time inference
```

---

## Asset setup (developers)

The ONNX model file is tracked by Git LFS:

| File | Size | LFS |
|---|---|---|
| `assets/model/fastconformer_ar_ctc_q8.onnx` | ~130 MB | ✅ |
| `assets/model/tokens.txt` | in Repo |
| `assets/model/quran.json` |in Repo |

If you see a 134-byte pointer file instead of the model binary after cloning:

```bash
git lfs pull
```


## Projects Used :
- **[offline-tarteel](https://github.com/yazinsai/offline-tarteel)** — Levenshtein alignment logic and matching architecture and FastConformer Model ....

- **Scheherazade New** — Quran Font
