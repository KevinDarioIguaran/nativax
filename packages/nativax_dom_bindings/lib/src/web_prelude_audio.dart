/// Minimal Web Audio surface. NativaX has no multimedia pipeline yet, so this
/// provides the object graph three.js needs to construct its audio manager and
/// play silently. `decodeAudioData` rejects so callers can fall back cleanly.
const String webAudio = r'''
// ============================================================================
// Web Audio (silent graph; decoding is not available yet)
// ============================================================================
class AudioParam {
  constructor(value = 0) { this.value = value; this.defaultValue = value; }
  setValueAtTime(value) { this.value = Number(value); return this; }
  linearRampToValueAtTime(value) { this.value = Number(value); return this; }
  exponentialRampToValueAtTime(value) { this.value = Number(value); return this; }
  setTargetAtTime(value) { this.value = Number(value); return this; }
  cancelScheduledValues() { return this; }
  cancelAndHoldAtTime() { return this; }
}
class AudioNode {
  constructor(context) { this.context = context; this.numberOfInputs = 1; this.numberOfOutputs = 1; }
  connect(destination) { return destination; }
  disconnect() {}
}
class AudioDestinationNode extends AudioNode {
  constructor(context) { super(context); this.maxChannelCount = 2; }
}
class AudioGainNode extends AudioNode {
  constructor(context) { super(context); this.gain = new AudioParam(1); }
}
class AudioPannerNode extends AudioNode {
  constructor(context) {
    super(context);
    this.panningModel = 'equalpower';
    this.distanceModel = 'inverse';
    this.refDistance = 1;
    this.maxDistance = 10000;
    this.rolloffFactor = 1;
    this.coneInnerAngle = 360;
    this.coneOuterAngle = 360;
    this.coneOuterGain = 0;
    this.positionX = new AudioParam(0);
    this.positionY = new AudioParam(0);
    this.positionZ = new AudioParam(0);
    this.orientationX = new AudioParam(1);
    this.orientationY = new AudioParam(0);
    this.orientationZ = new AudioParam(0);
  }
  setPosition(x, y, z) { this.positionX.value = x; this.positionY.value = y; this.positionZ.value = z; }
  setOrientation(x, y, z) { this.orientationX.value = x; this.orientationY.value = y; this.orientationZ.value = z; }
}
class AudioBufferSourceNode extends AudioNode {
  constructor(context) {
    super(context);
    this.buffer = null;
    this.loop = false;
    this.loopStart = 0;
    this.loopEnd = 0;
    this.onended = null;
    this.playbackRate = new AudioParam(1);
    this.detune = new AudioParam(0);
  }
  start() {}
  stop() {}
}
class AudioBuffer {
  constructor({ numberOfChannels = 1, length = 0, sampleRate = 44100 } = {}) {
    this.numberOfChannels = numberOfChannels;
    this.length = length;
    this.sampleRate = sampleRate;
    this.duration = sampleRate ? length / sampleRate : 0;
    this._channels = Array.from({ length: numberOfChannels }, () => new Float32Array(length));
  }
  getChannelData(channel) { return this._channels[channel] || this._channels[0]; }
  copyFromChannel(destination, channel) {
    const source = this.getChannelData(channel);
    destination.set(source.subarray(0, destination.length));
  }
  copyToChannel(source, channel) { this.getChannelData(channel).set(source); }
}
class AudioListenerNode {
  constructor() {
    this.positionX = new AudioParam(0);
    this.positionY = new AudioParam(0);
    this.positionZ = new AudioParam(0);
    this.forwardX = new AudioParam(0);
    this.forwardY = new AudioParam(0);
    this.forwardZ = new AudioParam(-1);
    this.upX = new AudioParam(0);
    this.upY = new AudioParam(1);
    this.upZ = new AudioParam(0);
  }
  setPosition(x, y, z) { this.positionX.value = x; this.positionY.value = y; this.positionZ.value = z; }
  setOrientation(x, y, z, ux, uy, uz) {
    this.forwardX.value = x; this.forwardY.value = y; this.forwardZ.value = z;
    this.upX.value = ux; this.upY.value = uy; this.upZ.value = uz;
  }
}
class AudioContext {
  constructor() {
    this._origin = performance.now();
    this.destination = new AudioDestinationNode(this);
    this.listener = new AudioListenerNode();
    this.sampleRate = 44100;
    this.state = 'suspended';
    this.baseLatency = 0;
    this.outputLatency = 0;
  }
  get currentTime() { return (performance.now() - this._origin) / 1000; }
  createGain() { return new AudioGainNode(this); }
  createPanner() { return new AudioPannerNode(this); }
  createBufferSource() { return new AudioBufferSourceNode(this); }
  createBuffer(numberOfChannels, length, sampleRate) {
    return new AudioBuffer({ numberOfChannels, length, sampleRate });
  }
  createAnalyser() { return new AudioNode(this); }
  createBiquadFilter() { return Object.assign(new AudioNode(this), { frequency: new AudioParam(350), Q: new AudioParam(1), type: 'lowpass' }); }
  decodeAudioData() {
    return Promise.reject(new DOMException('Audio decoding is not available in NativaX yet', 'NotSupportedError'));
  }
  resume() { this.state = 'running'; return Promise.resolve(); }
  suspend() { this.state = 'suspended'; return Promise.resolve(); }
  close() { this.state = 'closed'; return Promise.resolve(); }
}
const webkitAudioContext = AudioContext;
''';

