import { uid, L } from './util.js';
import { encodeWav, getCtx, channelsOf } from './audio.js';
import { defaultFx, mergeFx } from './fx.js';
import { saveProject, getAudio, getMeta } from './db.js';

export function thumbOf(chs, bars = 90) {
  const n = chs[0].length, out = [], step = Math.max(1, Math.floor(n / bars));
  for (let b = 0; b < bars; b++) {
    let m = 0;
    const s = b * step, e = Math.min(n, s + step);
    for (let i = s; i < e; i += Math.max(1, step >> 6)) for (const c of chs) { const a = Math.abs(c[i]); if (a > m) m = a; }
    out.push(Math.round(Math.min(1, Math.sqrt(m)) * 100) / 100);
  }
  return out;
}

export function newProject(chs, sr, name) {
  const d = new Date();
  return {
    id: uid(), created: Date.now(), updated: Date.now(),
    name: name || L('تسجيل ', 'Recording ') + d.toLocaleDateString('en-GB').replace(/\//g, '-') + ' ' + d.toTimeString().slice(0, 5),
    chs, sr, markers: [], fx: defaultFx(),
  };
}

export async function persist(p) {
  p.updated = Date.now();
  const meta = {
    id: p.id, name: p.name, created: p.created, updated: p.updated,
    duration: p.chs[0].length / p.sr, sr: p.sr, ch: p.chs.length,
    fx: p.fx, markers: p.markers, thumb: thumbOf(p.chs),
  };
  await saveProject(meta, encodeWav(p.chs, p.sr, 16));
  return meta;
}

export async function decodeFile(file) {
  const ab = await file.arrayBuffer();
  const buf = await getCtx().decodeAudioData(ab);
  return { chs: channelsOf(buf), sr: buf.sampleRate };
}

export async function loadProject(id) {
  const meta = await getMeta(id), wav = await getAudio(id);
  if (!meta || !wav) throw new Error('not found');
  const { chs, sr } = await decodeFile(wav);
  return { ...meta, chs, sr, fx: mergeFx(meta.fx || {}) };
}
