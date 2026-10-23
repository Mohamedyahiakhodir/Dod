import { clamp, dbToGain } from './util.js';
import { EQ_BANDS, REVERB_TYPES } from './fx.js';

let _ctx;
export function getCtx() {
  if (!_ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    _ctx = new AC({ latencyHint: 'interactive' });
  }
  return _ctx;
}
export async function resumeCtx() {
  const c = getCtx();
  if (c.state !== 'running') await c.resume().catch(() => {});
  return c;
}

export function toBuffer(chs, sr) {
  const b = getCtx().createBuffer(chs.length, Math.max(1, chs[0].length), sr);
  chs.forEach((c, i) => b.copyToChannel(c, i));
  return b;
}
export const channelsOf = (buf) => Array.from({ length: buf.numberOfChannels }, (_, i) => buf.getChannelData(i).slice());

/* ---------- encoders ---------- */
export function encodeWav(chs, sr, bits = 16) {
  const n = chs[0].length, ch = chs.length, bps = bits / 8, dataLen = n * ch * bps;
  const buf = new ArrayBuffer(44 + dataLen), v = new DataView(buf);
  const ws = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  ws(0, 'RIFF'); v.setUint32(4, 36 + dataLen, true); ws(8, 'WAVE'); ws(12, 'fmt ');
  v.setUint32(16, 16, true); v.setUint16(20, bits === 32 ? 3 : 1, true); v.setUint16(22, ch, true);
  v.setUint32(24, sr, true); v.setUint32(28, sr * ch * bps, true); v.setUint16(32, ch * bps, true);
  v.setUint16(34, bits, true); ws(36, 'data'); v.setUint32(40, dataLen, true);
  let o = 44;
  for (let i = 0; i < n; i++) {
    for (let c = 0; c < ch; c++) {
      let x = chs[c][i];
      if (bits === 32) { v.setFloat32(o, x, true); o += 4; }
      else if (bits === 24) {
        const s = Math.round(clamp(x, -1, 1) * 8388607);
        v.setUint8(o, s & 255); v.setUint8(o + 1, (s >> 8) & 255); v.setUint8(o + 2, (s >> 16) & 255); o += 3;
      } else {
        x += (Math.random() - Math.random()) / 32768; // TPDF dither
        v.setInt16(o, Math.round(clamp(x, -1, 1) * 32767), true); o += 2;
      }
    }
  }
  return new Blob([buf], { type: 'audio/wav' });
}

let lameP;
export function loadLame() {
  if (window.lamejs && window.lamejs.Mp3Encoder) return Promise.resolve();
  return lameP || (lameP = new Promise((res, rej) => {
    const s = document.createElement('script');
    s.src = 'vendor/lame.min.js';
    s.onload = res;
    s.onerror = () => { lameP = null; rej(new Error('MP3 encoder failed to load')); };
    document.head.appendChild(s);
  }));
}

export async function encodeMp3(chs, sr, kbps, onProgress) {
  await loadLame();
  const ch = Math.min(2, chs.length), n = chs[0].length;
  const enc = new window.lamejs.Mp3Encoder(ch, sr, kbps);
  const toI16 = (a) => { const o = new Int16Array(a.length); for (let i = 0; i < a.length; i++) o[i] = clamp(a[i], -1, 1) * 32767; return o; };
  const block = 1152 * 8, parts = [];
  for (let i = 0, k = 0; i < n; i += block, k++) {
    const l = toI16(chs[0].subarray(i, i + block));
    const d = ch > 1 ? enc.encodeBuffer(l, toI16(chs[1].subarray(i, i + block))) : enc.encodeBuffer(l);
    if (d.length) parts.push(d);
    if (k % 40 === 0) { onProgress && onProgress(i / n); await new Promise((r) => setTimeout(r)); }
  }
  const d = enc.flush();
  if (d.length) parts.push(d);
  return new Blob(parts, { type: 'audio/mpeg' });
}

/* ---------- loudness (ITU-R BS.1770 K-weighted, gated) ---------- */
function kCoefs(fs) {
  const shelf = (() => {
    const G = 3.999843853973347, Q = 0.7071752369554196, fc = 1681.9744509555319;
    const K = Math.tan(Math.PI * fc / fs), Vh = Math.pow(10, G / 20), Vb = Math.pow(Vh, 0.4996667741545416);
    const a0 = 1 + K / Q + K * K;
    return { b: [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0], a: [2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0] };
  })();
  const hp = (() => {
    const Q = 0.5003270373253953, fc = 38.13547087613982;
    const K = Math.tan(Math.PI * fc / fs), a0 = 1 + K / Q + K * K;
    return { b: [1, -2, 1], a: [2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0] };
  })();
  return [shelf, hp];
}
function biquad(x, c) {
  const y = new Float32Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  const [b0, b1, b2] = c.b, [a1, a2] = c.a;
  for (let i = 0; i < x.length; i++) {
    const xi = x[i], yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = xi; y2 = y1; y1 = yi; y[i] = yi;
  }
  return y;
}

export function measureLoudness(chs, sr) {
  const n = chs[0].length;
  let peak = 0;
  for (const c of chs) for (let i = 0; i < n; i++) { const a = Math.abs(c[i]); if (a > peak) peak = a; }
  const step = Math.round(sr * 0.1), sub = Math.floor(n / step);
  const peakDb = 20 * Math.log10(Math.max(peak, 1e-9));
  if (sub < 4) return { lufs: -Infinity, peakDb };
  const sums = new Float64Array(sub);
  const [s1, s2] = kCoefs(sr);
  for (const c of chs) {
    const f = biquad(biquad(c, s1), s2);
    for (let k = 0; k < sub; k++) { let s = 0; for (let i = k * step, e = i + step; i < e; i++) s += f[i] * f[i]; sums[k] += s; }
  }
  const blocks = [];
  for (let k = 0; k + 4 <= sub; k++) blocks.push((sums[k] + sums[k + 1] + sums[k + 2] + sums[k + 3]) / (4 * step));
  const lk = (z) => -0.691 + 10 * Math.log10(z);
  let g = blocks.filter((z) => z > 0 && lk(z) > -70);
  if (!g.length) return { lufs: -Infinity, peakDb };
  const rel = lk(g.reduce((a, b) => a + b, 0) / g.length) - 10;
  g = g.filter((z) => lk(z) > rel);
  if (!g.length) return { lufs: -Infinity, peakDb };
  return { lufs: lk(g.reduce((a, b) => a + b, 0) / g.length), peakDb };
}

/** Rough noise floor (dBFS RMS of the quietest 10% of 50ms windows). */
export function noiseFloorDb(chs, sr) {
  const w = Math.round(sr * 0.05), n = chs[0].length, vals = [];
  for (let i = 0; i + w <= n; i += w) {
    let s = 0;
    for (const c of chs) for (let j = i; j < i + w; j++) s += c[j] * c[j];
    vals.push(s / (w * chs.length));
  }
  if (!vals.length) return -120;
  vals.sort((a, b) => a - b);
  const k = Math.max(1, Math.floor(vals.length * 0.1));
  let m = 0;
  for (let i = 0; i < k; i++) m += vals[i];
  return 10 * Math.log10(Math.max(m / k, 1e-12));
}

/* ---------- lookahead peak limiter + fades (export path) ---------- */
export function limit(chs, sr, ceilDb) {
  const c = dbToGain(ceilDb), n = chs[0].length, la = Math.max(8, Math.round(sr * 0.002));
  const need = new Float32Array(n);
  let any = false;
  for (let i = 0; i < n; i++) {
    let m = 0;
    for (const ch of chs) { const a = Math.abs(ch[i]); if (a > m) m = a; }
    if (m > c) { need[i] = c / m; any = true; } else need[i] = 1;
  }
  if (!any) return;
  const gmin = new Float32Array(n), dq = new Int32Array(n);
  let head = 0, tail = 0;
  for (let i = n - 1; i >= 0; i--) {
    while (tail > head && need[dq[tail - 1]] >= need[i]) tail--;
    dq[tail++] = i;
    while (dq[head] > i + la - 1) head++;
    gmin[i] = need[dq[head]];
  }
  const rel = 1 - Math.exp(-1 / (0.08 * sr));
  let acc = 0, prev = 1;
  for (let i = 0; i < n; i++) {
    acc += gmin[i];
    if (i >= la) acc -= gmin[i - la];
    const avg = acc / Math.min(i + 1, la);
    let g = Math.min(avg, prev + (1 - prev) * rel);
    prev = g;
    for (const ch of chs) ch[i] *= g;
  }
}

export function applyFades(chs, sr, fadeIn, fadeOut) {
  const n = chs[0].length, fi = Math.round(fadeIn * sr), fo = Math.round(fadeOut * sr);
  for (const ch of chs) {
    for (let i = 0; i < Math.min(fi, n); i++) ch[i] *= i / fi;
    for (let i = 0; i < Math.min(fo, n); i++) ch[n - 1 - i] *= i / fo;
  }
}

/* ---------- reverb impulse responses ---------- */
const irCache = new Map();
export function getIR(ctx, r) {
  const key = [ctx.sampleRate, r.type, r.decay, r.damp].join('|');
  if (irCache.has(key) && irCache.get(key).ctx === ctx) return irCache.get(key).buf;
  const sr = ctx.sampleRate, len = Math.max(64, Math.floor(sr * r.decay * 1.05));
  const buf = ctx.createBuffer(2, len, sr), T = REVERB_TYPES[r.type] || REVERB_TYPES.room;
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    let lp = 0;
    for (let i = 0; i < len; i++) {
      const t = i / sr, env = Math.pow(10, (-3 * t) / r.decay);
      const a = clamp(1 - (r.damp / 100) * (0.2 + 0.78 * Math.min(1, (t / r.decay) * 1.2)), 0.02, 1);
      lp += a * ((Math.random() * 2 - 1) - lp);
      d[i] = lp * env;
    }
    if (T.er) {
      for (let k = 0; k < 8; k++) {
        const p = Math.floor((0.003 + Math.random() * 0.06) * sr);
        if (p < len) d[p] += (Math.random() < 0.5 ? -1 : 1) * (0.9 - k * 0.07) * 2;
      }
    }
    const fin = Math.floor(sr * 0.002);
    for (let i = 0; i < fin; i++) d[i] *= i / fin;
    const fout = Math.floor(len * 0.05);
    for (let i = 0; i < fout; i++) d[len - 1 - i] *= i / fout;
  }
  irCache.set(key, { ctx, buf });
  if (irCache.size > 8) irCache.delete(irCache.keys().next().value);
  return buf;
}

function satCurve(amount) {
  const n = 1024, c = new Float32Array(n), k = 1 + (amount / 100) * 8;
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    c[i] = Math.tanh(k * x) / Math.tanh(k);
  }
  return c;
}

/* ---------- effects chain (shared by live preview and offline render) ---------- */
export function buildChain(ctx, input, fx, o = {}) {
  let n = input;
  const oscs = [];
  const link = (node) => { n.connect(node); n = node; return node; };
  const bq = (type, f, q, gain) => {
    const b = ctx.createBiquadFilter();
    b.type = type; b.frequency.value = f; if (q != null) b.Q.value = q; if (gain != null) b.gain.value = gain;
    return link(b);
  };

  link(Object.assign(ctx.createGain(), {})).gain.value = dbToGain(fx.gain);
  if (fx.hpf.on) { bq('highpass', fx.hpf.f, 0.707); bq('highpass', fx.hpf.f, 0.707); }
  if (fx.lpf.on) { bq('lowpass', fx.lpf.f, 0.707); }
  if (fx.hum.on) for (let k = 1; k <= 3; k++) if (fx.hum.f * k < ctx.sampleRate / 2.2) bq('notch', fx.hum.f * k, 30);
  if (fx.eq.on) fx.eq.bands.forEach((g, i) => { if (Math.abs(g) >= 0.05) bq(EQ_BANDS[i].type, EQ_BANDS[i].f, EQ_BANDS[i].q, g); });
  if (fx.warm.on) {
    const ws = ctx.createWaveShaper();
    ws.curve = satCurve(fx.warm.amount); ws.oversample = '4x';
    link(ws);
    link(ctx.createGain()).gain.value = dbToGain(-fx.warm.amount * 0.06);
  }
  if (fx.comp.on) {
    const c = ctx.createDynamicsCompressor();
    c.threshold.value = fx.comp.th; c.knee.value = fx.comp.knee; c.ratio.value = fx.comp.ratio;
    c.attack.value = fx.comp.attack / 1000; c.release.value = fx.comp.release / 1000;
    link(c);
    link(ctx.createGain()).gain.value = dbToGain(fx.comp.makeup);
  }
  if (fx.ring.on) {
    const rg = ctx.createGain(); rg.gain.value = 0;
    const osc = ctx.createOscillator(); osc.frequency.value = fx.ring.f; osc.connect(rg.gain); osc.start();
    oscs.push(osc);
    link(rg);
  }

  if (fx.reverb.on || fx.echo.on || fx.chorus.on) {
    const dry = n, sum = ctx.createGain();
    dry.connect(sum);
    if (fx.echo.on) {
      const e = fx.echo, dl = ctx.createDelay(5), fb = ctx.createGain(), tone = ctx.createBiquadFilter(), wet = ctx.createGain();
      dl.delayTime.value = e.time / 1000; fb.gain.value = clamp(e.fb / 100, 0, 0.92);
      tone.type = 'lowpass'; tone.frequency.value = e.tone; wet.gain.value = e.mix / 100;
      dry.connect(dl); dl.connect(tone); tone.connect(fb); fb.connect(dl); tone.connect(wet); wet.connect(sum);
    }
    if (fx.chorus.on) {
      const c = fx.chorus, merger = ctx.createChannelMerger(2), wet = ctx.createGain();
      wet.gain.value = c.mix / 100;
      [0, 1].forEach((side) => {
        const dl = ctx.createDelay(0.1), base = side ? 0.027 : 0.02;
        dl.delayTime.value = base;
        const lfo = ctx.createOscillator(), depth = ctx.createGain();
        lfo.frequency.value = c.rate * (side ? 1.13 : 1); depth.gain.value = 0.0035 * (c.depth / 50);
        lfo.connect(depth); depth.connect(dl.delayTime); lfo.start(); oscs.push(lfo);
        dry.connect(dl); dl.connect(merger, 0, side);
      });
      merger.connect(wet); wet.connect(sum);
    }
    if (fx.reverb.on) {
      const r = fx.reverb, pre = ctx.createDelay(1), conv = ctx.createConvolver(), wet = ctx.createGain();
      pre.delayTime.value = r.pre / 1000; conv.buffer = getIR(ctx, r); wet.gain.value = (r.mix / 100) * 1.3;
      dry.connect(pre); pre.connect(conv); conv.connect(wet); wet.connect(sum);
    }
    n = sum;
  }

  const chain = { oscs, stop() { oscs.forEach((x) => { try { x.stop(); } catch (e) {} }); } };
  if (o.live) {
    const ng = ctx.createGain();
    ng.gain.value = dbToGain(o.normDb || 0);
    link(ng);
    const lim = ctx.createDynamicsCompressor();
    lim.threshold.value = fx.norm.on ? fx.norm.ceil : -0.5; lim.knee.value = 0; lim.ratio.value = 20;
    lim.attack.value = 0.001; lim.release.value = 0.1;
    link(lim);
    const fg = ctx.createGain();
    const dur = o.duration || 0, off = o.offset || 0, fi = fx.fadeIn, fo = fx.fadeOut;
    const f = (p) => clamp(Math.min(fi > 0 ? p / fi : 1, fo > 0 ? (dur - p) / fo : 1), 0, 1);
    const t0 = ctx.currentTime;
    fg.gain.setValueAtTime(f(off), t0);
    if (fi > 0 && off < fi) fg.gain.linearRampToValueAtTime(1, t0 + (fi - off));
    if (fo > 0) {
      const ts = dur - fo;
      if (off < ts) fg.gain.setValueAtTime(1, t0 + (ts - off));
      if (off < dur) fg.gain.linearRampToValueAtTime(0, t0 + (dur - off));
    }
    link(fg);
    chain.normNode = ng;
  }
  chain.output = n;
  return chain;
}

export const fxTail = (fx) => {
  let t = 0.05;
  if (fx.reverb.on) t = Math.max(t, fx.reverb.decay + fx.reverb.pre / 1000 + 0.2);
  if (fx.echo.on) {
    const fb = clamp(fx.echo.fb / 100, 0, 0.92);
    t = Math.max(t, Math.min(8, (fx.echo.time / 1000) * Math.ceil(Math.log(0.01) / Math.log(Math.max(fb, 0.05)))));
  }
  return Math.min(t, 10);
};

export async function renderFx(chs, sr, fx, { outRate, tail = 0 } = {}) {
  const n = chs[0].length, rate = outRate || sr, len = Math.max(1, Math.ceil((n / sr + tail) * rate));
  const off = new OfflineAudioContext(2, len, rate);
  const buf = new AudioBuffer({ length: n, numberOfChannels: chs.length, sampleRate: sr });
  chs.forEach((c, i) => buf.copyToChannel(c, i));
  const src = off.createBufferSource();
  src.buffer = buf;
  const chain = buildChain(off, src, fx, { live: false });
  chain.output.connect(off.destination);
  src.start();
  const r = await off.startRendering();
  return { chs: [r.getChannelData(0).slice(), r.getChannelData(1).slice()], sr: rate };
}

/** Full export pipeline: effects -> gain/normalise -> limiter -> fades -> channel layout. */
export async function processFull(chs, sr, fx, { outRate, forceStereo } = {}) {
  const r = await renderFx(chs, sr, fx, { outRate, tail: fxTail(fx) });
  let out = r.chs;
  const stereo = chs.length > 1 || forceStereo || fx.reverb.on || fx.chorus.on;
  if (!stereo) {
    const m = new Float32Array(out[0].length);
    for (let i = 0; i < m.length; i++) m[i] = (out[0][i] + out[1][i]) * 0.5;
    out = [m];
  }
  let info = measureLoudness(out, r.sr);
  if (fx.norm.on && isFinite(info.lufs)) {
    const g = dbToGain(clamp(fx.norm.target - info.lufs, -30, 30));
    for (const c of out) for (let i = 0; i < c.length; i++) c[i] *= g;
  }
  limit(out, r.sr, fx.norm.on ? fx.norm.ceil : -0.3);
  applyFades(out, r.sr, fx.fadeIn, fx.fadeOut);
  info = measureLoudness(out, r.sr);
  return { chs: out, sr: r.sr, info };
}

/** Estimate loudness of the live chain (for normalisation preview). */
export async function analyzeFx(chs, sr, fx) {
  const f = JSON.parse(JSON.stringify(fx));
  f.fadeIn = f.fadeOut = 0;
  const rate = Math.min(sr, 24000);
  const r = await renderFx(chs, sr, f, { outRate: rate, tail: 0 });
  return measureLoudness(r.chs, r.sr);
}

export function eqResponse(bands, nPts = 120) {
  const ctx = getCtx();
  const freqs = new Float32Array(nPts), tot = new Float32Array(nPts).fill(1);
  for (let i = 0; i < nPts; i++) freqs[i] = 20 * Math.pow(1000, i / (nPts - 1));
  const mag = new Float32Array(nPts), ph = new Float32Array(nPts);
  bands.forEach((g, i) => {
    if (Math.abs(g) < 0.05) return;
    const b = ctx.createBiquadFilter();
    b.type = EQ_BANDS[i].type; b.frequency.value = EQ_BANDS[i].f; b.Q.value = EQ_BANDS[i].q; b.gain.value = g;
    b.getFrequencyResponse(freqs, mag, ph);
    for (let k = 0; k < nPts; k++) tot[k] *= mag[k];
  });
  return { freqs, db: Array.from(tot, (m) => 20 * Math.log10(m)) };
}
