// This file acts as the bridge between Sherpa-ONNX WebAssembly and the Flutter Dart application.

console.log('[Sherpa] sherpa_official_app.js loaded.');

Module = {};

Module.locateFile = function(path, scriptDirectory = '') {
  console.log(`[Sherpa] locateFile called for: ${path} in ${scriptDirectory}`);
  if (scriptDirectory) return scriptDirectory + path;
  return path;
};

let recognizer = null;
let recognizer_stream = null;
let isRecognizerReady = false;
let isWasmLoaded = false;

Module.setStatus = function(status) {
  // console.log(`[Sherpa] Emscripten status: ${status}`);
};

Module.printErr = function(text) {
  console.error('[Sherpa WASM Error]', text);
};

Module.onAbort = function(what) {
  console.error('[Sherpa WASM Aborted]', what);
  const pTitleAr = document.querySelector('#progress-container .splash-title-ar');
  const pTitleEn = document.querySelector('#progress-container .splash-title-en');
  const pDescAr = document.querySelector('#progress-container .splash-desc-ar');
  const pDescEn = document.querySelector('#progress-container .splash-desc-en');
  if (pTitleAr) pTitleAr.innerText = 'تعذر تشغيل المحرك';
  if (pTitleEn) pTitleEn.innerText = 'Engine Initialization Failed';
  if (pDescAr) pDescAr.innerText = 'يرجى تحديث الصفحة أو استخدام متصفح حديث مثل Chrome أو Safari.';
  if (pDescEn) pDescEn.innerText = 'Please reload or use a modern browser (Chrome/Safari/Edge).';
};

Module.onRuntimeInitialized = function() {
  console.log('[Sherpa] WASM module loaded into memory.');
  isWasmLoaded = true;
};

window.isWasmModuleLoaded = function() {
    return isWasmLoaded;
};

// Called by Dart to write the asset bytes directly into the WASM filesystem
window.writeSherpaAssetToVFS = function(filename, bytes) {
    try {
        const fullPath = '/' + filename;
        if (Module.FS) {
            try {
                if (Module.FS.analyzePath && Module.FS.analyzePath(fullPath).exists) {
                    Module.FS.unlink(fullPath);
                }
            } catch (_) {}
            Module.FS.writeFile(fullPath, bytes);
            console.log(`[Sherpa] Wrote ${filename} to VFS. Size: ${bytes.length || bytes.byteLength} bytes`);
            return true;
        } else if (Module.FS_createDataFile) {
            try {
                if (Module.FS_unlink) Module.FS_unlink(fullPath);
            } catch (_) {}
            Module.FS_createDataFile('/', filename, bytes, true, true, true);
            console.log(`[Sherpa] Wrote ${filename} to VFS via createDataFile. Size: ${bytes.length || bytes.byteLength} bytes`);
            return true;
        } else {
            console.error('[Sherpa] No FS API found on Module!');
            return false;
        }
    } catch (e) {
        console.error(`[Sherpa] Failed to write ${filename} to VFS:`, e);
        return false;
    }
};

// Called by Dart after writing the model files to initialize the engine
window.initSherpaRecognizer = function(modelFilename) {
    try {
        if (modelFilename) {
            Module.modelPath = modelFilename.startsWith('./') ? modelFilename : ('./' + modelFilename);
        }
        recognizer = createOnlineRecognizer(Module);
        if (!recognizer || !recognizer.handle) {
            throw new Error('OnlineRecognizer created with null or invalid handle');
        }
        isRecognizerReady = true;
        console.log("[Sherpa] Recognizer created successfully!");

        // Free 72MB VFS RAM immediately (model is already loaded in C++ recognizer)
        try {
            const modelFile = modelFilename || 'zipformer_p_arabic_v3.int8.onnx';
            const fullPath = modelFile.startsWith('/') ? modelFile : ('/' + modelFile);
            if (Module.FS && Module.FS.analyzePath && Module.FS.analyzePath(fullPath).exists) {
                Module.FS.unlink(fullPath);
                console.log(`[Sherpa] Unlinked ${fullPath} from VFS to release 72MB RAM.`);
            }
        } catch(unlinkErr) {
            console.warn('[Sherpa] Non-critical unlink notice:', unlinkErr);
        }
        activeModelDownloadPromise = null;
        
        // Engine is completely loaded into WASM memory and ready!
        // Now we can safely remove the HTML splash screen.
        const splash = document.getElementById('splash-overlay');
        if (splash) {
            splash.style.opacity = '0';
            setTimeout(() => splash.remove(), 500);
        }
        return true;
    } catch (e) {
        console.error('[Sherpa] Failed to create recognizer:', e);
        const pTitleAr = document.querySelector('#progress-container .splash-title-ar');
        const pTitleEn = document.querySelector('#progress-container .splash-title-en');
        const pDescAr = document.querySelector('#progress-container .splash-desc-ar');
        const pDescEn = document.querySelector('#progress-container .splash-desc-en');
        if (pTitleAr) pTitleAr.innerText = 'تعذر تشغيل المحرك';
        if (pTitleEn) pTitleEn.innerText = 'Engine Initialization Failed';
        if (pDescAr) pDescAr.innerText = 'حدث خطأ أثناء تهيئة المحرك. يرجى تحديث الصفحة.';
        if (pDescEn) pDescEn.innerText = 'Error initializing engine. Please refresh the page.';
        return false;
    }
};

let audioCtx;
let mediaStream;
let expectedSampleRate = 16000;
let recordSampleRate;  
let recorder = null;   

let lastResult = '';
let processedChunks = 0;
let frameBuffer = new Float32Array(0);
const RECORD_CHUNK_SAMPLES = 5120; // 320ms at 16000Hz


function downsampleBuffer(buffer, exportSampleRate) {
  if (exportSampleRate === recordSampleRate) {
    return buffer;
  }
  var sampleRateRatio = recordSampleRate / exportSampleRate;
  var newLength = Math.round(buffer.length / sampleRateRatio);
  var result = new Float32Array(newLength);
  var offsetResult = 0;
  var offsetBuffer = 0;
  while (offsetResult < result.length) {
    var nextOffsetBuffer = Math.round((offsetResult + 1) * sampleRateRatio);
    var accum = 0, count = 0;
    for (var i = offsetBuffer; i < nextOffsetBuffer && i < buffer.length; i++) {
      accum += buffer[i];
      count++;
    }
    result[offsetResult] = accum / count;
    offsetResult++;
    offsetBuffer = nextOffsetBuffer;
  }
  return result;
}

function primeRecognizer() {
    if (recognizer && recognizer_stream) {
        let primingBuffer = new Float32Array(4800); // 300ms at 16000Hz
        recognizer_stream.acceptWaveform(expectedSampleRate, primingBuffer);
        while (recognizer.isReady(recognizer_stream)) {
            recognizer.decode(recognizer_stream);
        }
        console.log('[Sherpa] Injected 300ms priming preroll zeros.');
    }
}

let workletNode = null;

function processAudioSamples(samples) {
  processedChunks++;
  if (processedChunks % 50 === 0) {
      console.log(`[Sherpa] onaudioprocess running... processed ${processedChunks} chunks so far. isRecognizerReady: ${isRecognizerReady}`);
  }

  if (!isRecognizerReady || !recognizer) {
      if (processedChunks % 50 === 0) console.warn('[Sherpa] Recognizer not ready, dropping audio chunk.');
      return;
  }

  if (recognizer_stream == null) {
    console.log('[Sherpa] Creating recognizer stream...');
    recognizer_stream = recognizer.createStream();
    primeRecognizer();
  }

  // Feed directly to Sherpa (No VAD)
  recognizer_stream.acceptWaveform(expectedSampleRate, samples);
  while (recognizer.isReady(recognizer_stream)) {
    recognizer.decode(recognizer_stream);
  }

  let isEndpoint = recognizer.isEndpoint(recognizer_stream);
  let fullResult = recognizer.getResult(recognizer_stream);
  let resultText = fullResult.text;

  // Send intermediate results to Dart
  if (resultText.length > 0 && lastResult != resultText) {
    console.log(`%c[Sherpa ASR] 🗣️ Partial: "${resultText}" (tokens: ${fullResult.tokens ? fullResult.tokens.length : 0})`, 'color: #059669; font-weight: bold;');
    lastResult = resultText;
    if (window.dartSherpaOnResult) {
        window.dartSherpaOnResult(JSON.stringify(fullResult), false);
    } else {
        console.warn('[Sherpa] window.dartSherpaOnResult callback is not defined!');
    }
  }

  if (isEndpoint) {
    console.log(`%c[Sherpa ASR] ⚡ Endpoint detected (pause/breath). Accumulated text: "${lastResult}"`, 'color: #0284c7; font-weight: bold;');
    if (window.dartSherpaOnResult) {
        window.dartSherpaOnResult(JSON.stringify(fullResult), true); // Notify final segment
    }
  }
}

let activeMicrophoneStream = null;

window.startOfficialSherpa = function() {
  console.log('[Sherpa] startOfficialSherpa called from Dart');
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    console.error('[Sherpa] getUserMedia not supported on your browser!');
    return;
  }

  const constraints = {
      audio: {
          autoGainControl: false,
          echoCancellation: false,
          noiseSuppression: false
      }
  };

  let onSuccess = async function(stream) {
    console.log('[Sherpa] Microphone access granted. Initializing AudioContext...');
    activeMicrophoneStream = stream;
    
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!audioCtx) {
      try {
        audioCtx = new AudioContextClass({sampleRate: 16000});
      } catch(e) {
        // Fallback for iOS Safari / WebKit which requires hardware sampleRate
        audioCtx = new AudioContextClass();
      }
    }
    
    if (audioCtx.state === 'suspended') {
      audioCtx.resume().catch(console.warn);
    }

    recordSampleRate = audioCtx.sampleRate;
    mediaStream = audioCtx.createMediaStreamSource(stream);

    console.log(`[Sherpa] AudioContext started. Record sample rate: ${recordSampleRate}`);

    // Try AudioWorklet first (off-main-thread audio sampling)
    let usedWorklet = false;
    if (audioCtx.audioWorklet) {
      try {
        await audioCtx.audioWorklet.addModule('audio_worklet.js');
        workletNode = new AudioWorkletNode(audioCtx, 'audio-stream-processor');
        workletNode.port.onmessage = (event) => {
          if (event.data && event.data.samples) {
            const chunk = new Float32Array(event.data.samples);
            processAudioSamples(chunk);
          }
        };
        mediaStream.connect(workletNode);
        workletNode.connect(audioCtx.destination);
        usedWorklet = true;
        console.log('[Sherpa] AudioWorkletNode connected and started collecting audio!');
      } catch (workletErr) {
        console.warn('[Sherpa] AudioWorklet failed, falling back to ScriptProcessor:', workletErr);
      }
    }

    // Fallback to ScriptProcessor if AudioWorklet unavailable
    if (!usedWorklet) {
      var bufferSize = 4096;
      var numberOfInputChannels = 1;
      var numberOfOutputChannels = 2;
      if (audioCtx.createScriptProcessor) {
        recorder = audioCtx.createScriptProcessor(
            bufferSize, numberOfInputChannels, numberOfOutputChannels);
      } else {
        recorder = audioCtx.createJavaScriptNode(
            bufferSize, numberOfInputChannels, numberOfOutputChannels);
      }

      recorder.onaudioprocess = function(e) {
        let samples = new Float32Array(e.inputBuffer.getChannelData(0));
        samples = downsampleBuffer(samples, expectedSampleRate);

        // Concat to frame buffer
        let newBuffer = new Float32Array(frameBuffer.length + samples.length);
        newBuffer.set(frameBuffer);
        newBuffer.set(samples, frameBuffer.length);
        frameBuffer = newBuffer;

        // Process in EXACT 320ms chunks (5120 samples)
        let offset = 0;
        while (frameBuffer.length - offset >= RECORD_CHUNK_SAMPLES) {
            let chunk = frameBuffer.slice(offset, offset + RECORD_CHUNK_SAMPLES);
            offset += RECORD_CHUNK_SAMPLES;
            processAudioSamples(chunk);
        }

        // Keep remainder
        if (offset < frameBuffer.length) {
            frameBuffer = frameBuffer.slice(offset);
        } else {
            frameBuffer = new Float32Array(0);
        }
      };

      mediaStream.connect(recorder);
      recorder.connect(audioCtx.destination);
      console.log('[Sherpa] ScriptProcessor fallback connected and started collecting audio!');
    }
  };

  let onError = function(err) {
    console.error('[Sherpa] Failed to get microphone access: ', err);
  };

  navigator.mediaDevices.getUserMedia(constraints).then(onSuccess, onError);
};

window.stopOfficialSherpa = function() {
  console.log('[Sherpa] stopOfficialSherpa called from Dart');
  if (workletNode && audioCtx) {
    try { workletNode.disconnect(audioCtx.destination); } catch(e) {}
    try { workletNode.port.close(); } catch(e) {}
    workletNode = null;
  }
  if (mediaStream && workletNode) {
    try { mediaStream.disconnect(workletNode); } catch(e) {}
  }
  if (recorder && audioCtx) {
    try { recorder.disconnect(audioCtx.destination); } catch(e) {}
    recorder = null;
  }
  if (mediaStream && recorder) {
    try { mediaStream.disconnect(recorder); } catch(e) {}
  }
  if (activeMicrophoneStream) {
    try {
      activeMicrophoneStream.getTracks().forEach(track => track.stop());
    } catch(e) {}
    activeMicrophoneStream = null;
  }
  
  // Flush final word
  if (lastResult.length > 0) {
      console.log(`[Sherpa] Flushing final result: ${lastResult}`);
      if (window.dartSherpaOnResult) {
          window.dartSherpaOnResult(JSON.stringify({ text: lastResult, isFinal: true }), true); 
      }
  }
  lastResult = '';

  if (recognizer && recognizer_stream) {
      recognizer.reset(recognizer_stream);
      primeRecognizer();
  }
  console.log('[Sherpa] Recorder stopped successfully.');
    frameBuffer = new Float32Array(0);
};

window.resetOfficialSherpaBuffer = function() {
   console.log('[Sherpa] resetOfficialSherpaBuffer called from Dart');
   if (recognizer && recognizer_stream) {
       recognizer.reset(recognizer_stream);
       primeRecognizer();
       lastResult = '';
       frameBuffer = new Float32Array(0);
   }
};

let initializationError = '';

window.getOfficialSherpaError = function() {
    return initializationError;
};

window.isOfficialSherpaReady = function() {
   if (processedChunks % 100 === 0 && processedChunks !== 0) {
       console.log(`[Sherpa] isOfficialSherpaReady polled from Dart. Returning: ${isRecognizerReady}`);
   }
   return isRecognizerReady;
};

// --- IndexedDB Caching Helpers ---
const DB_NAME = 'SherpaModelDB';
const STORE_NAME = 'models';

function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, 1);
        request.onupgradeneeded = (e) => {
            const db = e.target.result;
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME);
            }
        };
        request.onsuccess = (e) => resolve(e.target.result);
        request.onerror = (e) => reject(e.target.error);
    });
}

async function getCachedModel(url) {
    try {
        const db = await openDB();
        return new Promise((resolve) => {
            if (!db.objectStoreNames.contains(STORE_NAME)) { resolve(null); return; }
            const tx = db.transaction(STORE_NAME, 'readonly');
            const store = tx.objectStore(STORE_NAME);
            const req = store.get(url);
            req.onsuccess = () => resolve(req.result);
            req.onerror = () => resolve(null);
        });
    } catch(e) { return null; }
}

async function ensurePersistentStorage() {
    try {
        if (navigator.storage && navigator.storage.persist) {
            const isPersisted = await navigator.storage.persist();
            console.log(`[Storage] Persistent storage active: ${isPersisted}`);
        }
    } catch (e) {
        console.warn('[Storage] Could not request persistent storage:', e);
    }
}

async function cacheModel(url, buffer) {
    try {
        const db = await openDB();
        return new Promise((resolve) => {
            try {
                const tx = db.transaction(STORE_NAME, 'readwrite');
                const store = tx.objectStore(STORE_NAME);
                store.clear();
                const req = store.put(buffer, url);
                tx.oncomplete = () => {
                    ensurePersistentStorage();
                    resolve();
                };
                tx.onerror = () => resolve();
                tx.onabort = () => resolve();
                req.onerror = () => resolve();
            } catch(err) {
                resolve();
            }
        });
    } catch(e) {
        console.warn('[Sherpa] IndexedDB caching error:', e);
    }
}

let activeModelDownloadPromise = null;

// Fetches the ONNX model from a given URL and returns a Uint8Array
window.fetchSherpaModel = async function(url) {
    if (activeModelDownloadPromise) {
        return activeModelDownloadPromise;
    }

    activeModelDownloadPromise = (async () => {
        try {
            // 1. Check if we already downloaded it previously!
            const cachedBuffer = await getCachedModel(url);
            if (cachedBuffer && cachedBuffer.byteLength > 50000000) { // Validate it's a full model (> 50MB)
                console.log(`[Sherpa] Found model in IndexedDB (${cachedBuffer.byteLength} bytes). Bypassing download prompt!`);
                return new Uint8Array(cachedBuffer);
            }

            // --- MODEL NOT FOUND: SHOW BILINGUAL ACCEPTANCE PROMPT ---
            const titleAr = document.querySelector('#prompt-section .splash-title-ar');
            const titleEn = document.querySelector('#prompt-section .splash-title-en');
            const descAr = document.querySelector('#prompt-section .splash-desc-ar');
            const descEn = document.querySelector('#prompt-section .splash-desc-en');
            const btn = document.getElementById('accept-download-btn');
            
            if (titleAr) titleAr.innerText = 'الموافقة مطلوبة';
            if (titleEn) titleEn.innerText = 'Acceptance Required';
            if (descAr) descAr.innerText = 'يستهلك تطبيق الويب حوالي 100 ميجابايت من باقة الإنترنت (بيانات الهاتف أو الواي فاي) لأول مرة فقط.';
            if (descEn) descEn.innerText = 'Web app uses ~100MB internet bandwidth (data or Wi-Fi) for the first time only.';
            if (btn) btn.style.display = 'block';

            console.log(`[Sherpa] Waiting for user download confirmation for ${url}...`);
            
            // Wait for user to click accept
            await new Promise((resolve) => {
                const btn = document.getElementById('accept-download-btn');
                if (!btn) { resolve(); return; }
                btn.addEventListener('click', () => {
                    document.getElementById('prompt-section').style.display = 'none';
                    document.getElementById('progress-container').style.display = 'block';
                    resolve();
                }, { once: true });
            });

        console.log(`[Sherpa] Starting 4-way parallel chunk download from ${url}...`);
        
        async function downloadSingleStream(targetUrl) {
            return new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();
                xhr.open('GET', targetUrl, true);
                xhr.responseType = 'arraybuffer';
                
                let lastUiUpdate = 0;
                const fill = document.getElementById('progress-bar-fill');
                const text = document.getElementById('progress-text');
                
                xhr.onprogress = (event) => {
                    if (event.lengthComputable) {
                        const total = event.total;
                        const loaded = event.loaded;
                        const now = performance.now();
                        if (now - lastUiUpdate > 80 || loaded === total) {
                            lastUiUpdate = now;
                            const percent = Math.min(100, Math.round((loaded / total) * 100));
                            if (fill) fill.style.width = percent + '%';
                            if (text) text.innerText = percent + '% (' + Math.round(loaded/1048576) + 'MB / ' + Math.round(total/1048576) + 'MB)';
                        }
                    }
                };
                
                xhr.onload = () => {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        resolve(xhr.response);
                    } else {
                        reject(new Error(`HTTP error! status: ${xhr.status}`));
                    }
                };
                
                xhr.onerror = () => reject(new Error('Network Error'));
                xhr.send();
            });
        }

        async function downloadParallelStream(targetUrl, numChunks = 4) {
            const fill = document.getElementById('progress-bar-fill');
            const text = document.getElementById('progress-text');
            let lastUiUpdate = 0;

            function updateProgress(loaded, total) {
                const now = performance.now();
                if (now - lastUiUpdate > 60 || loaded === total) {
                    lastUiUpdate = now;
                    const percent = Math.min(100, Math.round((loaded / total) * 100));
                    if (fill) fill.style.width = percent + '%';
                    if (text) text.innerText = percent + '% (' + Math.round(loaded / 1048576) + 'MB / ' + Math.round(total / 1048576) + 'MB)';
                }
            }

            // Probe total file size
            let totalSize = 72705392;
            try {
                const headRes = await fetch(targetUrl, { method: 'HEAD' });
                const len = headRes.headers.get('content-length');
                if (len) {
                    const parsed = parseInt(len, 10);
                    if (parsed > 10000000) totalSize = parsed;
                }
            } catch(e) {
                console.log('[Sherpa] HEAD size check skipped:', e);
            }

            const chunkSize = Math.ceil(totalSize / numChunks);
            const chunkPromises = [];
            const loadedPerChunk = new Array(numChunks).fill(0);

            for (let i = 0; i < numChunks; i++) {
                const start = i * chunkSize;
                const end = Math.min(start + chunkSize - 1, totalSize - 1);

                const chunkPromise = new Promise((resolve, reject) => {
                    const xhr = new XMLHttpRequest();
                    xhr.open('GET', targetUrl, true);
                    xhr.responseType = 'arraybuffer';
                    xhr.setRequestHeader('Range', `bytes=${start}-${end}`);

                    xhr.onprogress = (e) => {
                        loadedPerChunk[i] = e.loaded;
                        const totalLoaded = loadedPerChunk.reduce((a, b) => a + b, 0);
                        updateProgress(totalLoaded, totalSize);
                    };

                    xhr.onload = () => {
                        if (xhr.status === 206) {
                            loadedPerChunk[i] = xhr.response.byteLength;
                            const totalLoaded = loadedPerChunk.reduce((a, b) => a + b, 0);
                            updateProgress(totalLoaded, totalSize);
                            resolve({ index: i, buffer: xhr.response });
                        } else if (xhr.status === 200) {
                            // Server returned entire file instead of range chunk; reject to safely trigger single-stream
                            reject(new Error(`Server returned HTTP 200 instead of 206 for chunk ${i}`));
                        } else {
                            reject(new Error(`Chunk ${i} returned status ${xhr.status}`));
                        }
                    };

                    xhr.onerror = () => reject(new Error(`Chunk ${i} network failure`));
                    xhr.send();
                });

                chunkPromises.push(chunkPromise);
            }

            const results = await Promise.all(chunkPromises);
            
            // Assemble in exact sequence
            results.sort((a, b) => a.index - b.index);
            let totalBytes = 0;
            for (const r of results) totalBytes += r.buffer.byteLength;

            const assembled = new Uint8Array(totalBytes);
            let offset = 0;
            for (const r of results) {
                assembled.set(new Uint8Array(r.buffer), offset);
                offset += r.buffer.byteLength;
                r.buffer = null; // Release individual chunk buffer immediately
            }
            results.length = 0; // Clear results array references

            return assembled.buffer;
        }

        let arrayBuffer;
        try {
            arrayBuffer = await downloadParallelStream(url, 4);
        } catch(parallelErr) {
            console.warn('[Sherpa] 4-Way parallel download encountered an error, falling back to single stream:', parallelErr);
            arrayBuffer = await downloadSingleStream(url);
        }

        const fill = document.getElementById('progress-bar-fill');
        const text = document.getElementById('progress-text');
        if (fill) fill.style.width = '100%';
        if (text) text.innerText = '100% (' + Math.round(arrayBuffer.byteLength / 1048576) + 'MB / ' + Math.round(arrayBuffer.byteLength / 1048576) + 'MB)';

        // Change text to loading after data transfer hits 100%
        const pTitleAr = document.querySelector('#progress-container .splash-title-ar');
        const pTitleEn = document.querySelector('#progress-container .splash-title-en');
        const pDescAr = document.querySelector('#progress-container .splash-desc-ar');
        const pDescEn = document.querySelector('#progress-container .splash-desc-en');
        if (pTitleAr) pTitleAr.innerText = 'جارٍ التحميل...';
        if (pTitleEn) pTitleEn.innerText = 'Loading...';
        if (pDescAr) pDescAr.innerText = 'قاربت العملية على الانتهاء...';
        if (pDescEn) pDescEn.innerText = 'Almost ready...';

        // 2. Save it to IndexedDB in the background so they NEVER have to download it again!
        console.log(`[Sherpa] Saving model to IndexedDB for future offline access...`);
        cacheModel(url, arrayBuffer).then(() => {
            console.log(`[Sherpa] Successfully saved model to IndexedDB.`);
        }).catch(err => {
            console.warn(`[Sherpa] Failed to save model to IndexedDB:`, err);
        });
        
        console.log(`[Sherpa] Successfully fetched model: ${arrayBuffer.byteLength} bytes`);
        if (arrayBuffer.byteLength < 10000) {
            const textDecoder = new TextDecoder('utf-8');
            const fileText = textDecoder.decode(arrayBuffer);
            console.error('[DEBUG] The downloaded file is too small! Here are the exact contents of the 637 bytes:', fileText);
            throw new Error('Downloaded file is too small to be a valid ONNX model. See console for contents.');
        }
        return new Uint8Array(arrayBuffer);
        } catch (e) {
            console.error('[Sherpa] Failed to fetch model:', e);
            const pTitleAr = document.querySelector('#progress-container .splash-title-ar');
            const pTitleEn = document.querySelector('#progress-container .splash-title-en');
            const pDescAr = document.querySelector('#progress-container .splash-desc-ar');
            const pDescEn = document.querySelector('#progress-container .splash-desc-en');
            const text = document.getElementById('progress-text');
            if (pTitleAr) pTitleAr.innerText = 'تعذر التحميل';
            if (pTitleEn) pTitleEn.innerText = 'Loading Failed';
            if (pDescAr) pDescAr.innerText = 'يرجى التحقق من اتصالك بالإنترنت ثم تحديث الصفحة.';
            if (pDescEn) pDescEn.innerText = 'Please check your internet connection and reload.';
            if (text) {
               text.innerText = 'خطأ في الاتصال • Connection error';
               text.style.color = '#dc2626';
            }
            activeModelDownloadPromise = null;
            return null;
        }
    })();

    return activeModelDownloadPromise;
};

// Immediately check on startup so user sees the download prompt without waiting for WASM compilation
setTimeout(() => {
    window.fetchSherpaModel('/download-model?model=zipformer_p_arabic_v3.int8.onnx');
}, 50);

