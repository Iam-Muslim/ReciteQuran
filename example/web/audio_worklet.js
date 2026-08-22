class AudioStreamProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this._buffer = new Float32Array(0);
    this._targetChunkSize = 5120; // 320ms at 16kHz
    this._outputSampleRate = 16000;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;

    const inputData = input[0];
    const inputSampleRate = sampleRate; // Hardware sample rate

    // Accumulation downsampler matching downsampleBuffer
    let samples;
    if (inputSampleRate === this._outputSampleRate) {
      samples = inputData;
    } else {
      const sampleRateRatio = inputSampleRate / this._outputSampleRate;
      const newLength = Math.round(inputData.length / sampleRateRatio);
      samples = new Float32Array(newLength);
      let offsetResult = 0;
      let offsetBuffer = 0;
      while (offsetResult < samples.length) {
        const nextOffsetBuffer = Math.round((offsetResult + 1) * sampleRateRatio);
        let accum = 0;
        let count = 0;
        for (let i = offsetBuffer; i < nextOffsetBuffer && i < inputData.length; i++) {
          accum += inputData[i];
          count++;
        }
        samples[offsetResult] = count > 0 ? (accum / count) : 0;
        offsetResult++;
        offsetBuffer = nextOffsetBuffer;
      }
    }

    const merged = new Float32Array(this._buffer.length + samples.length);
    merged.set(this._buffer);
    merged.set(samples, this._buffer.length);
    this._buffer = merged;

    while (this._buffer.length >= this._targetChunkSize) {
      const chunk = this._buffer.slice(0, this._targetChunkSize);
      this._buffer = this._buffer.slice(this._targetChunkSize);
      this.port.postMessage({ samples: chunk.buffer }, [chunk.buffer]);
    }

    return true;
  }
}

registerProcessor('audio-stream-processor', AudioStreamProcessor);

