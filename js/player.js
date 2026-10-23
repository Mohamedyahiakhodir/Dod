import { getCtx, resumeCtx, toBuffer, buildChain } from './audio.js';
import { defaultFx } from './fx.js';
import { clamp, dbToGain } from './util.js';

export class Player {
  constructor() {
    this.ctx = getCtx();
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 2048;
    this.analyser.smoothingTimeConstant = 0.8;
    this.analyser.connect(this.ctx.destination);
    this.td = new Float32Array(this.analyser.fftSize);
    this.fd = new Uint8Array(this.analyser.frequencyBinCount);
    this.playing = false;
    this.offset = 0;
    this.loop = null;
    this.bypass = false;
    this.normDb = 0;
    this.fx = defaultFx();
    this.dur = 0;
    this.onEnd = null;
    this._rs = null;
  }

  setBuffers(base, clean, sr) {
    this.bufBase = toBuffer(base, sr);
    this.bufClean = clean ? toBuffer(clean, sr) : null;
    this.dur = this.bufBase.duration;
    this.offset = Math.min(this.offset, this.dur);
    if (this.playing) this.restart();
  }

  get buf() { return (!this.bypass && this.bufClean) || this.bufBase; }

  pos() {
    if (!this.playing) return this.offset;
    let p = this.offset + (this.ctx.currentTime - this.t0);
    if (this.looping && this.loop && p >= this.loop.b) {
      const len = this.loop.b - this.loop.a;
      p = this.loop.a + ((p - this.loop.a) % len);
    }
    return clamp(p, 0, this.dur);
  }

  async play(from) {
    await resumeCtx();
    if (from != null) this.offset = from;
    this._start();
  }

  _start() {
    this._stopSrc();
    const ctx = this.ctx;
    if (!this.bufBase) return;
    if (this.offset >= this.dur - 0.02 && !this.loop) this.offset = 0;
    const src = ctx.createBufferSource();
    src.buffer = this.buf;
    this.looping = false;
    if (this.loop && this.loop.b > this.loop.a) {
      this.looping = true;
      src.loop = true; src.loopStart = this.loop.a; src.loopEnd = this.loop.b;
      if (this.offset < this.loop.a || this.offset >= this.loop.b) this.offset = this.loop.a;
    }
    const fx = this.bypass ? defaultFx() : this.fx;
    const chain = buildChain(ctx, src, fx, { live: true, normDb: this.bypass ? 0 : this.normDb, offset: this.offset, duration: this.dur });
    chain.output.connect(this.analyser);
    src.start(0, this.offset);
    this.t0 = ctx.currentTime;
    this.src = src; this.chain = chain; this.playing = true;
    src.onended = () => {
      if (this.src !== src) return;
      this._stopSrc();
      this.playing = false;
      this.offset = this.dur;
      this.onEnd && this.onEnd();
    };
  }

  _stopSrc() {
    if (!this.src) return;
    const s = this.src, ch = this.chain;
    this.src = null; this.chain = null;
    s.onended = null;
    try { s.stop(); } catch (e) {}
    try { s.disconnect(); ch && ch.output.disconnect(); } catch (e) {}
    ch && ch.stop();
  }

  pause() {
    if (!this.playing) return;
    this.offset = this.pos();
    this.playing = false;
    this._stopSrc();
  }

  seek(t) {
    this.offset = clamp(t, 0, this.dur);
    if (this.playing) this._start();
  }

  restart() {
    if (!this.playing) return;
    this.offset = this.pos();
    this._start();
  }

  setFx(fx) {
    this.fx = fx;
    if (!this.playing) return;
    clearTimeout(this._rs);
    this._rs = setTimeout(() => this.restart(), 120);
  }

  setNorm(db) {
    this.normDb = db;
    if (this.chain && this.chain.normNode) this.chain.normNode.gain.setTargetAtTime(dbToGain(db), this.ctx.currentTime, 0.05);
  }

  setLoop(l) { this.loop = l; if (this.playing) this.restart(); }
  setBypass(b) { this.bypass = b; if (this.playing) this.restart(); }

  level() {
    this.analyser.getFloatTimeDomainData(this.td);
    let pk = 0;
    for (let i = 0; i < this.td.length; i++) { const a = Math.abs(this.td[i]); if (a > pk) pk = a; }
    return pk;
  }
  spectrum() { this.analyser.getByteFrequencyData(this.fd); return this.fd; }

  dispose() { this.pause(); try { this.analyser.disconnect(); } catch (e) {} }
}
