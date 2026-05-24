# The Great Quran - القرآن العظيم  Recite Quran - اتلو القران
# Recite Record Live Checking For Words

**YOU ARE NOT ALLOWED TO SELL THIS OR GAIN ANY MONEY OR SUPPORTS FROM IT , IT IS ONLY FOR THE SAKE OF ALLAH THE GREATEST"**

**IF YOU USED ANY LOGIC , CODES , IDEAS OR ANYTHING FROM THIS PROJECT THEN YOU ARE NOT ALLOWED TO SELL OR GAIN ANY MONEY OR SUPPORTS FROM IT , IT IS ONLY FOR THE SAKE OF ALLAH THE GREATEST**

##  Credits
Thanks to ALLAH only , elhamdule Allah

## Screenshots
<img width="270" height="585" alt="Screenshot_20260524-095510_Recite Quran" src="https://github.com/user-attachments/assets/d235c989-a400-40d4-994a-4ac7046defb9" /><img width="270" height="585" alt="Screenshot_20260524-121320_Recite Quran" src="https://github.com/user-attachments/assets/e8f1637a-e07f-4b67-b707-5864d2a1b3e8" />
______________________________________________________________________

##  Architecture

```
lib/
├── core/          # App state ( Colors , Language ,....)
├── data/          # Quran data models, repository, JSON database loader
├── engine/        # Sherpa-ONNX ASR engine (background Isolate) , token segmenter
├── utils/         # Arabic normalizer
├── recording/     # Microphone ring-buffer , live recitation state machine
└── screens/       # UI: tracking screen
```



## Asset setup (developers)

The ONNX model file is in https://github.com/yazinsai/offline-tarteel project 

| `assets/model/fastconformer_ar_ctc_q8.onnx` | ~130 MB |

| `assets/model/tokens.txt` | in Repo |

| `assets/model/quran.json` |in Repo |



## Projects Used :
- **[offline-tarteel](https://github.com/yazinsai/offline-tarteel)** 

- **Scheherazade New** — Quran Font
