class AudioStreamProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this._buffer = [];
    this._bufferSize = 5120; // 320ms at 16kHz (matching the native chunkMs)
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;

    const channelData = input[0];
    const inputSampleRate = sampleRate; // Browser's hardware rate
    const outputSampleRate = 16000;
    const ratio = inputSampleRate / outputSampleRate;

    // Very naive downsampling (matching external project)
    for (let i = 0; i < channelData.length; i += ratio) {
      this._buffer.push(channelData[Math.floor(i)]);
    }

    // When we have enough samples, send to the main thread
    if (this._buffer.length >= this._bufferSize) {
      // Convert Float32 [-1.0, 1.0] to Int16 PCM [-32768, 32767]
      const int16Buffer = new Int16Array(this._bufferSize);
      for (let i = 0; i < this._bufferSize; i++) {
        let s = Math.max(-1, Math.min(1, this._buffer[i]));
        int16Buffer[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
      }
      
      const chunk = new Uint8Array(int16Buffer.buffer);
      this.port.postMessage(chunk.buffer, [chunk.buffer]);
      this._buffer = [];
    }

    return true;
  }
}

registerProcessor("audio-stream-processor", AudioStreamProcessor);
