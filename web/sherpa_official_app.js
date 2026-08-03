// This file acts as the bridge between Sherpa-ONNX WebAssembly and the Flutter Dart application.

console.log('[Sherpa] sherpa_official_app.js loaded.');

Module = {};

Module.locateFile = function(path, scriptDirectory = '') {
  console.log(`[Sherpa] locateFile called for: ${path} in ${scriptDirectory}`);
  return scriptDirectory + path;
};

let recognizer = null;
let recognizer_stream = null;
let isRecognizerReady = false;
let isWasmLoaded = false;

Module.setStatus = function(status) {
  // console.log(`[Sherpa] Emscripten status: ${status}`);
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
        if (Module.FS_createDataFile) {
            Module.FS_createDataFile('/', filename, bytes, true, true, true);
        } else if (Module.FS) {
            Module.FS.writeFile('/' + filename, bytes);
        } else {
            console.error('[Sherpa] No FS API found on Module!');
            return false;
        }
        console.log(`[Sherpa] Wrote ${filename} to VFS. Size: ${bytes.length} bytes`);
        return true;
    } catch (e) {
        console.error(`[Sherpa] Failed to write ${filename} to VFS:`, e);
        return false;
    }
};

// Called by Dart after writing the model files to initialize the engine
window.initSherpaRecognizer = function() {
    try {
        recognizer = createOnlineRecognizer(Module);
        isRecognizerReady = true;
        console.log("[Sherpa] Recognizer created successfully!");
        
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

window.startOfficialSherpa = function() {
  console.log('[Sherpa] startOfficialSherpa called from Dart');
  if (!navigator.mediaDevices.getUserMedia) {
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

  let onSuccess = function(stream) {
    console.log('[Sherpa] Microphone access granted. Initializing AudioContext...');
    if (!audioCtx) {
      audioCtx = new AudioContext({sampleRate: 16000});
    }
    recordSampleRate = audioCtx.sampleRate;
    mediaStream = audioCtx.createMediaStreamSource(stream);

    console.log(`[Sherpa] AudioContext started. Record sample rate: ${recordSampleRate}`);

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
      processedChunks++;
      if (processedChunks % 50 === 0) {
          console.log(`[Sherpa] onaudioprocess running... processed ${processedChunks} chunks so far. isRecognizerReady: ${isRecognizerReady}`);
      }

      if (!isRecognizerReady || !recognizer) {
          if (processedChunks % 50 === 0) console.warn('[Sherpa] Recognizer not ready, dropping audio chunk.');
          return;
      }

      let samples = new Float32Array(e.inputBuffer.getChannelData(0))
      samples = downsampleBuffer(samples, expectedSampleRate);



      if (recognizer_stream == null) {
        console.log('[Sherpa] Creating recognizer stream...');
        recognizer_stream = recognizer.createStream();
        primeRecognizer();
      }

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

          // Feed directly to Sherpa (No VAD)
          recognizer_stream.acceptWaveform(expectedSampleRate, chunk);
          while (recognizer.isReady(recognizer_stream)) {
            recognizer.decode(recognizer_stream);
          }
      }

      // Keep remainder
      if (offset < frameBuffer.length) {
          frameBuffer = frameBuffer.slice(offset);
      } else {
          frameBuffer = new Float32Array(0);
      }

      let isEndpoint = recognizer.isEndpoint(recognizer_stream);
      let fullResult = recognizer.getResult(recognizer_stream);
      let resultText = fullResult.text;

      // Send intermediate results to Dart
      if (resultText.length > 0 && lastResult != resultText) {
        console.log(`[Sherpa] Partial result: ${resultText}`);
        lastResult = resultText;
        if (window.dartSherpaOnResult) {
            window.dartSherpaOnResult(JSON.stringify(fullResult), false);
        } else {
            console.warn('[Sherpa] window.dartSherpaOnResult callback is not defined!');
        }
      }

      if (isEndpoint) {
        console.log(`[Sherpa] Endpoint detected. Final result: ${lastResult}`);
        if (window.dartSherpaOnResult) {
            window.dartSherpaOnResult(JSON.stringify(fullResult), true); // Finalize word
        }
        lastResult = '';
        recognizer.reset(recognizer_stream);
        primeRecognizer();
        console.log('[Sherpa] Engine reset and primed. Returning to IDLE state.');
      }
    };

    mediaStream.connect(recorder);
    recorder.connect(audioCtx.destination);
    console.log('[Sherpa] Recorder connected and started collecting audio!');
  };

  let onError = function(err) {
    console.error('[Sherpa] Failed to get microphone access: ', err);
  };

  navigator.mediaDevices.getUserMedia(constraints).then(onSuccess, onError);
};

window.stopOfficialSherpa = function() {
  console.log('[Sherpa] stopOfficialSherpa called from Dart');
  if (recorder && audioCtx) {
    recorder.disconnect(audioCtx.destination);
  }
  if (mediaStream && recorder) {
    mediaStream.disconnect(recorder);
  }
  if (mediaStream && mediaStream.mediaStream) {
    mediaStream.mediaStream.getTracks().forEach(track => track.stop());
  }
  
  // Flush final word
  if (lastResult.length > 0) {
      console.log(`[Sherpa] Flushing final result: ${lastResult}`);
      if (window.dartSherpaOnResult) {
          window.dartSherpaOnResult(lastResult, true); 
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

async function cacheModel(url, buffer) {
    try {
        const db = await openDB();
        return new Promise((resolve) => {
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);
            store.clear();
            store.put(buffer, url);
            tx.oncomplete = () => resolve();
            tx.onerror = () => resolve();
        });
    } catch(e) {}
}

// Fetches the ONNX model from a given URL and returns a Uint8Array
window.fetchSherpaModel = async function(url) {
    try {
        // 1. Check if we already downloaded it previously!
        const cachedBuffer = await getCachedModel(url);
        if (cachedBuffer && cachedBuffer.byteLength > 50000000) { // Validate it's a full model (> 50MB)
            console.log(`[Sherpa] Found model in IndexedDB (${cachedBuffer.byteLength} bytes). Bypassing download prompt!`);
            // Default HTML is already "Initializing...", so we do nothing to the UI!
            return new Uint8Array(cachedBuffer);
        }

        // --- MODEL NOT FOUND: SHOW DOWNLOAD PROMPT ---
        const title = document.querySelector('#prompt-section .splash-title');
        const desc = document.querySelector('#prompt-section .splash-desc');
        const btn = document.getElementById('accept-download-btn');
        
        if (title) title.innerText = 'AI Engine Required';
        if (desc) desc.innerText = 'To process your recitation offline with complete privacy, we need to download the AI model (~115MB). This only happens once.';
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

        console.log(`[Sherpa] Starting fetch from ${url}...`);
        const response = await fetch(url, { cache: 'no-store' });
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        const contentLength = response.headers.get('content-length') || 120000000;
        const total = parseInt(contentLength, 10);
        let loaded = 0;

        const reader = response.body.getReader();
        const chunks = [];

        while(true) {
            const {done, value} = await reader.read();
            if (done) break;
            chunks.push(value);
            loaded += value.length;
            
            // Update UI Progress Bar
            const percent = Math.min(100, Math.round((loaded / total) * 100));
            const fill = document.getElementById('progress-bar-fill');
            const text = document.getElementById('progress-text');
            if (fill) fill.style.width = percent + '%';
            if (text) text.innerText = percent + '% (' + Math.round(loaded/1024/1024) + 'MB / ' + Math.round(total/1024/1024) + 'MB)';
        }

        // Change text to initializing after download hits 100%
        const progressTitle = document.querySelector('#progress-container .splash-title');
        const progressDesc = document.querySelector('#progress-container .splash-desc');
        if (progressTitle) progressTitle.innerText = 'Initializing AI Engine...';
        if (progressDesc) progressDesc.innerText = 'Loading into memory. Almost ready!';

        const arrayBuffer = new Uint8Array(loaded);
        let position = 0;
        for(let chunk of chunks) {
            arrayBuffer.set(chunk, position);
            position += chunk.length;
        }
        
        // 2. Save it to IndexedDB so they NEVER have to download it again!
        console.log(`[Sherpa] Saving model to IndexedDB for future offline access...`);
        await cacheModel(url, arrayBuffer.buffer);
        
        console.log(`[Sherpa] Successfully fetched model: ${arrayBuffer.byteLength} bytes`);
        return arrayBuffer;
    } catch (e) {
        console.error('[Sherpa] Failed to fetch model:', e);
        const text = document.getElementById('progress-text');
        if (text) {
           text.innerText = 'Download Failed!';
           text.style.color = 'red';
        }
        return null;
    }
};
