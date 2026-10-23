import { getCtx, resumeCtx } from './audio.js';
import { dbToGain, clamp } from './util.js';

const WORKLET = `
class RecProc extends AudioWorkletProcessor {
  constructor() {
    super(); this.on = false; this.l = []; this.r = []; this.n = 0;
    this.port.onmessage = (e) => {
      if (e.data.on !== undefined) this.on = e.data.on;
      if (e.data.flush) { this.flush(true); }
    };
  }
  flush(final) {
    const l = new Float32Array(this.n), r = new Float32Array(this.n);
    let o = 0;
    for (let i = 0; i < this.l.length; i++) { l.set(this.l[i], o); r.set(this.r[i], o); o += this.l[i].length; }
    this.l = []; this.r = []; this.n = 0;
    this.port.postMessage({ l, r, final: !!final }, [l.buffer, r.buffer]);
  }
  process(inputs) {
    const i = inputs[0];
    if (!this.on || !i || !i.length) return true;
    this.l.push(new Float32Array(i[0])); this.r.push(new Float32Array(i[1] || i[0]));
    this.n += i[0].length;
    if (this.n >= 4096) this.flush(false);
    return true;
  }
}
registerProcessor('rec-proc', RecProc);
`;

let workletReady = null;
function ensureWorklet(ctx) {
  if (!ctx.audioWorklet) return Promise.reject(new Error('no worklet'));
  return workletReady || (workletReady = ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([WORKLET], { type: 'text/javascript' }))));
}

export class Recorder {
  constructor() {
    this.opts = { ns: true, ec: true, agc: false, gainDb: 0, stereo: false, deviceId: '', monitor: false };
    this.state = 'idle'; // idle | recording | paused
    this.stream = null;
    this.chunksL = []; this.chunksR = []; this.samples = 0; this.channels = 1;
    this.onChunk = null;
    this.markers = [];
    this.clips = 0;
  }

  get sr() { return getCtx().sampleRate; }
  get time() { return this.samples / this.sr; }

  async open() {
    const ctx = await resumeCtx();
    this.close();
    const o = this.opts;
    const audio = {
      echoCancellation: o.ec, noiseSuppression: o.ns, autoGainControl: o.agc,
      channelCount: o.stereo ? 2 : 1,
    };
    if (o.deviceId) audio.deviceId = { ideal: o.deviceId };
    this.stream = await navigator.mediaDevices.getUserMedia({ audio });
    const track = this.stream.getAudioTracks()[0];
    this.trackSettings = track.getSettings();
    this.channels = clamp(this.trackSettings.channelCount || 1, 1, 2);
    if (!o.stereo) this.channels = 1;
    this.src = ctx.createMediaStreamSource(this.stream);
    this.inGain = ctx.createGain();
    this.inGain.gain.value = dbToGain(o.gainDb);
    this.analyser = ctx.createAnalyser();
    this.analyser.fftSize = 2048;
    this.analyser.smoothingTimeConstant = 0.7;
    this.mon = ctx.createGain();
    this.mon.gain.value = o.monitor ? 1 : 0;
    this.sink = ctx.createGain();
    this.sink.gain.value = 0;
    this.src.connect(this.inGain);
    this.inGain.connect(this.analyser);
    this.inGain.connect(this.mon);
    this.mon.connect(ctx.destination);
    await this.makeCapture(ctx);
    this.sink.connect(ctx.destination);
    this.td = new Float32Array(this.analyser.fftSize);
    this.fd = new Uint8Array(this.analyser.frequencyBinCount);
    return this.trackSettings;
  }

  async makeCapture(ctx) {
    const ch = this.channels;
    try {
      await ensureWorklet(ctx);
      const node = new AudioWorkletNode(ctx, 'rec-proc', { numberOfInputs: 1, numberOfOutputs: 1, channelCount: ch, channelCountMode: 'explicit', outputChannelCount: [1] });
      node.port.onmessage = (e) => this.push(e.data);
      this.inGain.connect(node);
      node.connect(this.sink);
      this.capture = { post: (m) => node.port.postMessage(m), node };
    } catch (err) {
      const sp = ctx.createScriptProcessor(4096, ch, 1);
      let on = false;
      sp.onaudioprocess = (e) => {
        if (!on) return;
        const l = new Float32Array(e.inputBuffer.getChannelData(0));
        const r = ch > 1 ? new Float32Array(e.inputBuffer.getChannelData(1)) : l;
        this.push({ l, r });
      };
      this.inGain.connect(sp);
      sp.connect(this.sink);
      this.capture = {
        node: sp,
        post: (m) => { if (m.on !== undefined) on = m.on; if (m.flush) { on = false; this.push({ l: new Float32Array(0), r: new Float32Array(0), final: true }); } },
      };
    }
  }

  push(d) {
    if (d.l.length && this.state !== 'idle') {
      this.chunksL.push(d.l);
      if (this.channels > 1) this.chunksR.push(d.r);
      this.samples += d.l.length;
      this.onChunk && this.onChunk(d.l);
    }
    if (d.final && this._flushRes) { this._flushRes(); this._flushRes = null; }
  }

  setGain(db) { this.opts.gainDb = db; if (this.inGain) this.inGain.gain.value = dbToGain(db); }
  setMonitor(on) { this.opts.monitor = on; if (this.mon) this.mon.gain.value = on ? 1 : 0; }

  async applyProcessing() {
    // try to change live; fall back to re-opening the mic when idle
    const track = this.stream && this.stream.getAudioTracks()[0];
    if (!track) return;
    try {
      await track.applyConstraints({ echoCancellation: this.opts.ec, noiseSuppression: this.opts.ns, autoGainControl: this.opts.agc });
      this.trackSettings = track.getSettings();
    } catch (e) {
      if (this.state === 'idle') await this.open();
    }
  }

  start() {
    this.chunksL = []; this.chunksR = []; this.samples = 0; this.markers = []; this.clips = 0;
    this.state = 'recording';
    this.capture.post({ on: true });
  }
  pause() { if (this.state === 'recording') { this.state = 'paused'; this.capture.post({ on: false }); this.capture.post({ flush: true }); } }
  resume() { if (this.state === 'paused') { this.state = 'recording'; this.capture.post({ on: true }); } }
  addMarker() { this.markers.push({ t: this.time, name: '' }); return this.markers.length; }

  async stop() {
    if (this.state === 'idle') return null;
    const wait = new Promise((r) => { this._flushRes = r; });
    this.capture.post({ on: false });
    this.capture.post({ flush: true });
    await Promise.race([wait, new Promise((r) => setTimeout(r, 800))]);
    this.state = 'idle';
    const join = (parts) => { const o = new Float32Array(this.samples); let p = 0; for (const c of parts) { o.set(c, p); p += c.length; } return o; };
    const L = join(this.chunksL);
    const chs = this.channels > 1 ? [L, join(this.chunksR)] : [L];
    const res = { chs, sr: this.sr, markers: this.markers };
    this.chunksL = []; this.chunksR = [];
    return res;
  }

  /** Current level snapshot from the analyser. */
  level() {
    if (!this.analyser) return { peak: 0, rms: 0 };
    this.analyser.getFloatTimeDomainData(this.td);
    let pk = 0, s = 0;
    for (let i = 0; i < this.td.length; i++) { const a = Math.abs(this.td[i]); if (a > pk) pk = a; s += a * a; }
    return { peak: pk, rms: Math.sqrt(s / this.td.length) };
  }
  spectrum() { this.analyser.getByteFrequencyData(this.fd); return this.fd; }

  close() {
    if (this.state !== 'idle') return;
    try { this.capture && this.capture.node.disconnect(); } catch (e) {}
    try { this.src && this.src.disconnect(); this.inGain && this.inGain.disconnect(); this.mon && this.mon.disconnect(); } catch (e) {}
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop());
    this.stream = null;
  }

  async devices() {
    try {
      return (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'audioinput');
    } catch (e) { return []; }
  }
}
