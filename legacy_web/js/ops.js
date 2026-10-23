import { clamp, dbToGain } from './util.js';

const len = (chs) => chs[0].length;
const ms = (sr, v) => Math.max(1, Math.round(sr * v));

export function cut(chs, sr, a, b) {
  const n = len(chs);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  if (b <= a) return chs;
  const fm = ms(sr, 0.003);
  return chs.map((c) => {
    const o = new Float32Array(n - (b - a));
    o.set(c.subarray(0, a)); o.set(c.subarray(b), a);
    const fl = Math.min(fm, a), fr = Math.min(fm, o.length - a);
    for (let i = 0; i < fl; i++) o[a - fl + i] *= 1 - (i + 1) / fl;
    for (let i = 0; i < fr; i++) o[a + i] *= (i + 1) / fr;
    return o;
  });
}

export function keep(chs, sr, a, b) {
  const n = len(chs);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  if (b <= a) return chs;
  const f = Math.min(ms(sr, 0.002), (b - a) >> 1);
  return chs.map((c) => {
    const o = c.slice(a, b);
    for (let i = 0; i < f; i++) { o[i] *= i / f; o[o.length - 1 - i] *= i / f; }
    return o;
  });
}

export function silence(chs, sr, a, b) {
  const n = len(chs);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  const f = Math.min(ms(sr, 0.005), (b - a) >> 1);
  return chs.map((c) => {
    const o = c.slice();
    for (let i = a; i < b; i++) {
      const d = Math.min(i - a, b - 1 - i);
      // ramp down at the start, ramp up at the end of the muted region
      o[i] *= d < f ? 1 - (d + 1) / f : 0;
    }
    return o;
  });
}

export function gainRegion(chs, sr, a, b, db) {
  const n = len(chs), g = dbToGain(db);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  const f = Math.min(ms(sr, 0.01), (b - a) >> 1);
  return chs.map((c) => {
    const o = c.slice();
    for (let i = a; i < b; i++) {
      const d = Math.min(i - a, b - 1 - i);
      const k = d < f ? d / f : 1;
      o[i] *= 1 + (g - 1) * k;
    }
    return o;
  });
}

export function insertSilence(chs, sr, at, seconds) {
  const n = len(chs), k = Math.round(seconds * sr);
  at = clamp(at | 0, 0, n);
  return chs.map((c) => {
    const o = new Float32Array(n + k);
    o.set(c.subarray(0, at)); o.set(c.subarray(at), at + k);
    return o;
  });
}

export function reverse(chs, a, b) {
  const n = len(chs);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  return chs.map((c) => {
    const o = c.slice();
    for (let i = a, j = b - 1; i < b; i++, j--) o[i] = c[j];
    return o;
  });
}

export function slice(chs, a, b) {
  return chs.map((c) => c.slice(clamp(a | 0, 0, c.length), clamp(b | 0, 0, c.length)));
}

export function paste(chs, sr, at, clip) {
  const n = len(chs), k = len(clip);
  at = clamp(at | 0, 0, n);
  const f = Math.min(ms(sr, 0.002), k >> 1);
  return chs.map((c, ci) => {
    const src = clip[ci] || clip[0];
    const o = new Float32Array(n + k);
    o.set(c.subarray(0, at)); o.set(src, at); o.set(c.subarray(at), at + k);
    for (let i = 0; i < f; i++) { o[at + i] *= i / f; o[at + k - 1 - i] *= i / f; }
    return o;
  });
}

export function append(chs, other) {
  const n = len(chs), k = len(other);
  const count = Math.max(chs.length, other.length);
  return Array.from({ length: count }, (_, ci) => {
    const a = chs[ci] || chs[0], b = other[ci] || other[0];
    const o = new Float32Array(n + k);
    o.set(a); o.set(b, n);
    return o;
  });
}

export function fadeRegion(chs, a, b, dir) {
  const n = len(chs);
  a = clamp(a | 0, 0, n); b = clamp(b | 0, 0, n);
  const m = b - a;
  if (m < 2) return chs;
  return chs.map((c) => {
    const o = c.slice();
    for (let i = 0; i < m; i++) o[a + i] *= dir === 'in' ? i / m : 1 - i / m;
    return o;
  });
}

/** Remove (or shorten) silent stretches. Returns { chs, removed (seconds) }. */
export function removeSilences(chs, sr, { thDb = -45, minMs = 400, padMs = 120 } = {}) {
  const n = len(chs), w = Math.round(sr * 0.01), th = dbToGain(thDb);
  const nw = Math.floor(n / w), quiet = new Uint8Array(nw);
  for (let k = 0; k < nw; k++) {
    let s = 0;
    for (const c of chs) for (let i = k * w; i < (k + 1) * w; i++) s += c[i] * c[i];
    quiet[k] = Math.sqrt(s / (w * chs.length)) < th ? 1 : 0;
  }
  const minW = Math.round(minMs / 10), padW = Math.round(padMs / 10);
  const keepRanges = [];
  let cur = 0;
  for (let k = 0; k <= nw; k++) {
    if (k === nw || !quiet[k]) continue;
    let e = k;
    while (e < nw && quiet[e]) e++;
    if (e - k >= minW) {
      const cutA = (k + (k === 0 ? 0 : padW)) * w, cutB = (e - (e === nw ? 0 : padW)) * w;
      if (cutB > cutA) { keepRanges.push([cur, cutA]); cur = cutB; }
    }
    k = e - 1;
  }
  keepRanges.push([cur, n]);
  const total = keepRanges.reduce((s, [a, b]) => s + (b - a), 0);
  if (total >= n) return { chs, removed: 0, map: (t) => t };
  const f = ms(sr, 0.003);
  const out = chs.map((c) => {
    const o = new Float32Array(total);
    let p = 0;
    keepRanges.forEach(([a, b], idx) => {
      o.set(c.subarray(a, b), p);
      const m = b - a, ff = Math.min(f, m >> 1);
      if (idx > 0) for (let i = 0; i < ff; i++) o[p + i] *= i / ff;
      if (idx < keepRanges.length - 1) for (let i = 0; i < ff; i++) o[p + m - 1 - i] *= i / ff;
      p += m;
    });
    return o;
  });
  const map = (t) => {
    const x = t * sr;
    let acc = 0;
    for (const [a, b] of keepRanges) {
      if (x < a) return acc / sr;
      if (x <= b) return (acc + x - a) / sr;
      acc += b - a;
    }
    return acc / sr;
  };
  return { chs: out, removed: (n - total) / sr, map };
}
