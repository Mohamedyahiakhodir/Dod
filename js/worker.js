/* DSP worker: spectral noise reduction, gate, de-esser, WSOLA time/pitch. */
self.onmessage = (e) => {
  const m = e.data;
  try {
    const prog = (p) => self.postMessage({ id: m.id, progress: p });
    let out;
    if (m.type === 'clean') out = clean(m, prog);
    else if (m.type === 'stretch') out = stretch(m, prog);
    self.postMessage({ id: m.id, chs: out }, out.map((c) => c.buffer));
  } catch (err) {
    self.postMessage({ id: m.id, error: String(err && err.message || err) });
  }
};

function makeFFT(N) {
  const levels = Math.log2(N) | 0, rev = new Uint32Array(N);
  for (let i = 0; i < N; i++) rev[i] = (rev[i >> 1] >> 1) | ((i & 1) << (levels - 1));
  const cos = new Float64Array(N / 2), sin = new Float64Array(N / 2);
  for (let i = 0; i < N / 2; i++) { cos[i] = Math.cos((2 * Math.PI * i) / N); sin[i] = Math.sin((2 * Math.PI * i) / N); }
  return (re, im, inverse) => {
    for (let i = 0; i < N; i++) {
      const j = rev[i];
      if (j > i) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
    }
    for (let size = 2; size <= N; size <<= 1) {
      const half = size >> 1, step = N / size;
      for (let i = 0; i < N; i += size) {
        for (let j = i, k = 0; j < i + half; j++, k += step) {
          const wr = cos[k], wi = inverse ? sin[k] : -sin[k], l = j + half;
          const tr = re[l] * wr - im[l] * wi, ti = re[l] * wi + im[l] * wr;
          re[l] = re[j] - tr; im[l] = im[j] - ti; re[j] += tr; im[j] += ti;
        }
      }
    }
    if (inverse) for (let i = 0; i < N; i++) { re[i] /= N; im[i] /= N; }
  };
}

function clean(m, prog) {
  const { sr, params } = m;
  let chs = m.chs;
  const steps = (params.dn ? 1 : 0) + (params.gate ? 1 : 0) + (params.ds > 0 ? 1 : 0) || 1;
  let done = 0;
  const sub = (a, b) => (p) => prog((done + a + (b - a) * p) / steps);
  if (params.dn) {
    const fft = makeFFT(2048);
    chs = chs.map((c, i) => denoise(c, sr, params.amount, m.profile, fft, sub(i / chs.length, (i + 1) / chs.length)));
    done++;
  }
  if (params.gate) { gate(chs, sr, params.gateDb, params.gateRange); done++; prog(done / steps); }
  if (params.ds > 0) { deess(chs, sr, params.ds); done++; prog(done / steps); }
  return chs;
}

function denoise(x, sr, amount, profile, fft, prog) {
  const N = 2048, H = 512, bins = N / 2 + 1, n = x.length;
  const win = new Float64Array(N);
  for (let i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / N);
  const re = new Float64Array(N), im = new Float64Array(N);
  const noise = new Float64Array(bins);

  const analyse = (src, s, cb) => {
    for (let i = 0; i < N; i++) { const idx = s + i; re[i] = idx >= 0 && idx < src.length ? src[idx] * win[i] : 0; im[i] = 0; }
    fft(re, im, false);
    cb();
  };
  const loE = Math.floor((100 / sr) * N), hiE = Math.floor((6000 / sr) * N);

  if (profile && profile.length >= N) {
    let cnt = 0;
    for (let s = 0; s + N <= profile.length; s += H) {
      analyse(profile, s, () => { for (let k = 0; k < bins; k++) noise[k] += re[k] * re[k] + im[k] * im[k]; });
      cnt++;
    }
    for (let k = 0; k < bins; k++) noise[k] /= Math.max(1, cnt);
  } else {
    const energies = [];
    for (let s = -N + H; s < n; s += H * 2) {
      let e = 0;
      for (let i = 0; i < N; i++) { const idx = s + i; if (idx >= 0 && idx < n) { const v = x[idx]; e += v * v; } }
      energies.push(e);
    }
    const sorted = Float64Array.from(energies).sort();
    const thr = sorted[Math.max(0, Math.floor(sorted.length * 0.12) - 1)];
    let cnt = 0;
    let idx = 0;
    for (let s = -N + H; s < n; s += H * 2, idx++) {
      if (energies[idx] > thr) continue;
      analyse(x, s, () => { for (let k = 0; k < bins; k++) noise[k] += re[k] * re[k] + im[k] * im[k]; });
      cnt++;
    }
    for (let k = 0; k < bins; k++) noise[k] /= Math.max(1, cnt);
  }
  // smooth noise spectrum across frequency
  const ns = new Float64Array(bins);
  for (let k = 0; k < bins; k++) {
    let s = 0, c = 0;
    for (let j = Math.max(0, k - 3); j <= Math.min(bins - 1, k + 3); j++) { s += noise[j]; c++; }
    ns[k] = s / c;
  }

  const alpha = 1 + (amount / 100) * 2.2, floor = Math.pow(10, -(8 + (amount / 100) * 28) / 20);
  const prev = new Float64Array(bins).fill(1), g = new Float64Array(bins);
  const out = new Float32Array(n), scale = 1 / 1.5;
  let frame = 0;
  const total = Math.ceil((n + N) / H);
  for (let s = -N + H; s < n; s += H, frame++) {
    analyse(x, s, () => {
      for (let k = 0; k < bins; k++) {
        const p = re[k] * re[k] + im[k] * im[k] + 1e-20;
        let v = Math.sqrt(Math.max((p - alpha * ns[k]) / p, floor * floor));
        v = 0.55 * v + 0.45 * prev[k];
        g[k] = v;
      }
      for (let k = 0; k < bins; k++) {
        const sm = 0.25 * g[Math.max(0, k - 1)] + 0.5 * g[k] + 0.25 * g[Math.min(bins - 1, k + 1)];
        prev[k] = g[k];
        re[k] *= sm; im[k] *= sm;
        if (k > 0 && k < N / 2) { re[N - k] *= sm; im[N - k] *= sm; }
      }
    });
    fft(re, im, true);
    for (let i = 0; i < N; i++) { const idx = s + i; if (idx >= 0 && idx < n) out[idx] += re[i] * win[i] * scale; }
    if (frame % 400 === 0) prog(frame / total);
  }
  return out;
}

function gate(chs, sr, db, rangeDb) {
  const n = chs[0].length, thr = Math.pow(10, db / 20), floor = Math.pow(10, rangeDb / 20);
  const envRel = Math.exp(-1 / (0.03 * sr)), gAtt = Math.exp(-1 / (0.004 * sr)), gRel = Math.exp(-1 / (0.08 * sr));
  const hold = Math.round(0.06 * sr), look = Math.round(0.005 * sr);
  const g = new Float32Array(n);
  let env = 0, gs = 1, hc = 0;
  for (let i = 0; i < n; i++) {
    let p = 0;
    for (const c of chs) { const a = Math.abs(c[i]); if (a > p) p = a; }
    env = p > env ? p : env * envRel;
    let target = floor;
    if (env > thr) { target = 1; hc = hold; } else if (hc > 0) { hc--; target = 1; }
    gs = target + (gs - target) * (target > gs ? gAtt : gRel);
    g[i] = gs;
  }
  for (const c of chs) for (let i = 0; i < n; i++) c[i] *= g[Math.min(n - 1, i + look)];
}

function deess(chs, sr, amount) {
  const n = chs[0].length, w0 = (2 * Math.PI * 5500) / sr, cs = Math.cos(w0), al = Math.sin(w0) / (2 * 0.707);
  const a0 = 1 + al, b0 = (1 + cs) / 2 / a0, b1 = -(1 + cs) / a0, b2 = b0, a1 = (-2 * cs) / a0, a2 = (1 - al) / a0;
  const att = Math.exp(-1 / (0.001 * sr)), rel = Math.exp(-1 / (0.03 * sr)), gsm = Math.exp(-1 / (0.0008 * sr));
  for (const c of chs) {
    const hi = new Float32Array(n);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0, sq = 0;
    for (let i = 0; i < n; i++) {
      const x = c[i], y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1; x1 = x; y2 = y1; y1 = y; hi[i] = y; sq += y * y;
    }
    const rms = Math.sqrt(sq / n) + 1e-9, thr = rms * (3.2 - 2.4 * (amount / 100));
    let env = 0, gs = 1;
    for (let i = 0; i < n; i++) {
      const a = Math.abs(hi[i]);
      env = a > env ? a + (env - a) * att : a + (env - a) * rel;
      const target = env > thr ? Math.pow(thr / env, 0.8) : 1;
      gs = target + (gs - target) * gsm;
      c[i] -= hi[i] * (1 - gs);
    }
  }
}

function stretch(m, prog) {
  const { sr, tempo, semis } = m;
  const r = Math.pow(2, semis / 12);
  let chs = m.chs;
  const rate = tempo / r;
  if (Math.abs(rate - 1) > 1e-4) chs = wsola(chs, sr, rate, (p) => prog(p * (Math.abs(r - 1) > 1e-4 ? 0.85 : 1)));
  if (Math.abs(r - 1) > 1e-4) chs = chs.map((c) => resample(c, r));
  return chs;
}

function wsola(chs, sr, rate, prog) {
  const n = chs[0].length;
  const win = Math.round((sr * 0.046) / 2) * 2, hs = win / 2, tol = Math.round(sr * 0.012), dec = 4;
  const w = new Float32Array(win);
  for (let i = 0; i < win; i++) w[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / win);
  const outLen = Math.ceil(n / rate) + win;
  const out = chs.map(() => new Float32Array(outLen));
  const mono = new Float32Array(n);
  for (let i = 0; i < n; i++) { let s = 0; for (const c of chs) s += c[i]; mono[i] = s / chs.length; }
  const place = (c0, o0) => {
    for (let ci = 0; ci < chs.length; ci++) {
      const src = chs[ci], dst = out[ci];
      for (let i = 0; i < win; i++) { const idx = c0 + i; if (idx < n) dst[o0 + i] += src[idx] * w[i]; }
    }
  };
  place(0, 0);
  for (let ci = 0; ci < chs.length; ci++) for (let i = 0; i < hs && i < n; i++) out[ci][i] = chs[ci][i];
  let prev = 0;
  for (let k = 1; ; k++) {
    const outPos = k * hs, target = Math.round(k * hs * rate);
    if (outPos + win > outLen || target >= n) break;
    const ref = prev + hs;
    let best = target, bestC = -Infinity;
    if (ref + hs <= n) {
      const lo = Math.max(0, target - tol), hi = Math.min(n - hs, target + tol);
      for (let c = lo; c <= hi; c += 2) {
        let s = 0, e = 1e-9;
        for (let j = 0; j < hs; j += dec) { const b = mono[c + j]; s += mono[ref + j] * b; e += b * b; }
        const sc = s / Math.sqrt(e);
        if (sc > bestC) { bestC = sc; best = c; }
      }
    }
    place(best, outPos);
    prev = best;
    if (k % 300 === 0) prog(target / n);
  }
  const finalLen = Math.floor(n / rate);
  return out.map((o) => o.slice(0, finalLen));
}

function resample(x, r) {
  const n = Math.floor(x.length / r), y = new Float32Array(n), L = x.length;
  for (let i = 0; i < n; i++) {
    const p = i * r, i1 = Math.floor(p), f = p - i1;
    const p0 = x[Math.max(0, i1 - 1)], p1 = x[i1], p2 = x[Math.min(L - 1, i1 + 1)], p3 = x[Math.min(L - 1, i1 + 2)];
    y[i] = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)));
  }
  return y;
}
