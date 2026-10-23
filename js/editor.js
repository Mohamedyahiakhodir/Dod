import { h, L, clamp, fmtTime, debounce, deepMerge } from './util.js';
import { icon, iconBtn, toast, promptBox, confirmBox, busy } from './ui.js';
import { Player } from './player.js';
import { defaultFx, cleanActive } from './fx.js';
import { analyzeFx, noiseFloorDb } from './audio.js';
import { runJob } from './dsp.js';
import { persist } from './project.js';
import { makeTools, TOOL_ORDER } from './tools.js';

const nice = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800];

export function createEditor({ onClose }) {
  const player = new Player();
  const root = h('div', { class: 'editor hidden' });

  /* ---- session state ---- */
  let proj = null, chs = null, cleanChs = null, cleanDone = '', sr = 48000, fx = defaultFx();
  let sel = null, center = 0, pps = 100, loopOn = false, peaks = null, dirty = true, cleanJob = null, profile = null, profileId = 0;
  let undo = [], redo = [], clip = null, loud = null, status = '', anId = 0, activeTool = null, raf = 0, closed = true;
  const loudListeners = new Set();

  /* ---- DOM ---- */
  const titleBtn = h('button', { class: 'ed-title', type: 'button', onclick: rename });
  const exportBtn = h('button', { class: 'btn primary sm', type: 'button', onclick: () => openTool('export') }, icon('download', 16), L('تصدير', 'Export'));
  const head = h('header', { class: 'ed-head' }, iconBtn('back', () => close(), 'plain flip', L('رجوع', 'Back')), titleBtn, exportBtn);

  const curEl = h('span', { class: 'cur' }, '00:00.0'), totEl = h('span', { class: 'tot' }, '/ 00:00.0');
  const loudChip = h('span', { class: 'chip-info' }), statChip = h('span', { class: 'chip-info stat hidden' });
  const info = h('div', { class: 'ed-info' }, h('div', { class: 'ed-time' }, curEl, totEl), h('div', { class: 'ed-chips' }, statChip, loudChip));
  const tl = h('canvas', { class: 'tl' });
  const abBtn = h('button', { class: 'ab-btn', type: 'button', onclick: toggleBypass, title: L('مقارنة قبل/بعد', 'A/B compare') }, icon('ab', 16), h('span', {}, L('بعد', 'After')));
  const zoomBox = h('div', { class: 'zoom-box' }, iconBtn('zoomin', () => zoom(1.6), 'tiny', L('تكبير', 'Zoom in')), iconBtn('zoomout', () => zoom(1 / 1.6), 'tiny', L('تصغير', 'Zoom out')));
  const spec = h('canvas', { class: 'spec' });
  const stage = h('div', { class: 'ed-stage' }, info, h('div', { class: 'tl-wrap' }, tl, abBtn, zoomBox), spec);

  const playBtn = h('button', { class: 'play-btn', type: 'button', onclick: togglePlay, 'aria-label': 'play' }, icon('play', 28));
  const loopBtn = iconBtn('loop', toggleLoop, '', L('تكرار التحديد', 'Loop selection'));
  const undoBtn = iconBtn('undo', doUndo, '', L('تراجع', 'Undo')), redoBtn = iconBtn('redo', doRedo, '', L('إعادة', 'Redo'));
  const transport = h('div', { class: 'ed-transport' },
    undoBtn, redoBtn, iconBtn('rew', () => seek(pos() - 5), '', L('-5 ثوانٍ', '-5s')), playBtn,
    iconBtn('fwd', () => seek(pos() + 5), '', L('+5 ثوانٍ', '+5s')), loopBtn,
    iconBtn('flag', () => addMarkerHere(), '', L('علامة', 'Marker')));

  const toolbar = h('div', { class: 'toolbar' });
  const panelTitle = h('div', { class: 'p-title' }), panelBody = h('div', { class: 'p-body' });
  const resetBtn = h('button', { class: 'p-reset hidden', type: 'button' }, L('إعادة ضبط', 'Reset'));
  const panel = h('div', { class: 'tool-panel hidden' },
    h('div', { class: 'p-head' }, panelTitle, resetBtn, iconBtn('check', () => openTool(null), 'primary-i', L('تم', 'Done'))),
    panelBody);
  const bottom = h('div', { class: 'ed-bottom' }, toolbar, panel);
  root.append(head, stage, transport, bottom);

  /* ---- ed context for tools ---- */
  const ed = {
    get fx() { return fx; },
    get chs() { return chs; },
    get cleanChs() { return cleanChs; },
    get sr() { return sr; },
    get dur() { return chs ? chs[0].length / sr : 0; },
    get sel() { return sel; },
    get proj() { return proj; },
    get clip() { return clip; },
    set clip(v) { clip = v; },
    get loud() { return loud; },
    get hasProfile() { return !!profile; },
    pos, seek, setSel, fxChanged, edit, rerender: () => openTool(activeTool, true), toast,
    onLoud(fn) { loudListeners.add(fn); return () => loudListeners.delete(fn); },
    selSamples(warn = true) {
      if (!sel || sel.b - sel.a < 0.005) { if (warn) toast(L('حدّد جزءًا من التسجيل أولاً (اسحب المقابض)', 'Select a part of the recording first')); return null; }
      return [Math.round(sel.a * sr), Math.round(sel.b * sr)];
    },
    learnProfile() {
      const s = ed.selSamples();
      if (!s) return;
      if (s[1] - s[0] < 4096) { toast(L('التحديد قصير جدًا (اختر نصف ثانية على الأقل)', 'Selection too short (pick at least 0.5 s)')); return; }
      profile = chs[0].slice(s[0], s[1]); profileId++;
      fx.clean.dn = true;
      fxChanged('clean');
      toast(L('تم التقاط بصمة الضوضاء', 'Noise profile captured'));
      ed.rerender();
    },
    clearProfile() { profile = null; profileId++; fxChanged('clean'); ed.rerender(); },
    noiseInfo() {
      return { before: noiseFloorDb(chs, sr), after: cleanChs ? noiseFloorDb(cleanChs, sr) : null };
    },
    setFx(newFx) { fx = newFx; proj.fx = fx; fxChanged('clean'); },
    async bake(newChs, newSr) { await edit(() => newChs, { keepFx: false, resetFx: true }); },
    player,
    get source() { return cleanChs || chs; },
    setLoopOn,
    markers: () => proj.markers,
    markersChanged() { dirty = true; saveSoon(); },
    markerSort() { proj.markers.sort((a, b) => a.t - b.t); },
  };

  const tools = makeTools(ed);

  function buildToolbar() {
    toolbar.innerHTML = '';
    TOOL_ORDER.forEach((id) => {
      const t = tools[id];
      const on = t.active && t.active(fx);
      toolbar.append(h('button', { class: 'tool' + (on ? ' on' : '') + (activeTool === id ? ' cur' : ''), type: 'button', onclick: () => openTool(id) },
        icon(t.icon, 24), h('span', {}, t.label()), on ? h('i', { class: 'dot' }) : null));
    });
  }

  function openTool(id, force) {
    if (id === activeTool && !force && id) id = null;
    activeTool = id;
    if (!id) {
      loudListeners.clear();
      panel.classList.add('hidden'); toolbar.classList.remove('hidden');
      root.classList.remove('has-panel');
      buildToolbar();
      layout();
      return;
    }
    loudListeners.clear();
    const t = tools[id];
    panelTitle.textContent = t.label();
    panelBody.innerHTML = '';
    panelBody.append(t.build());
    resetBtn.classList.toggle('hidden', !t.reset);
    resetBtn.onclick = () => { t.reset(); fxChanged('clean'); openTool(id, true); };
    panel.classList.remove('hidden'); toolbar.classList.add('hidden');
    root.classList.add('has-panel');
    layout();
  }

  /* ---- playback ---- */
  function pos() { return player.pos(); }
  function seek(t) {
    t = clamp(t, 0, ed.dur);
    center = t; player.seek(t); dirty = true;
  }
  async function togglePlay() {
    if (player.playing) player.pause();
    else {
      if (center >= ed.dur - 0.02) center = 0;
      await player.play(center);
    }
    updatePlayBtn();
  }
  function updatePlayBtn() {
    playBtn.innerHTML = '';
    playBtn.append(icon(player.playing ? 'pause' : 'play', 28));
  }
  player.onEnd = () => { updatePlayBtn(); center = ed.dur; dirty = true; };
  function toggleLoop() { setLoopOn(!loopOn); }
  function setLoopOn(v) {
    if (v && !sel) { toast(L('حدّد جزءًا أولاً لتكراره', 'Select a part to loop first')); return; }
    loopOn = v;
    loopBtn.classList.toggle('on', loopOn);
    syncLoop();
  }
  function syncLoop() { player.setLoop(loopOn && sel ? { a: sel.a, b: sel.b } : null); }
  function toggleBypass() {
    player.setBypass(!player.bypass);
    abBtn.classList.toggle('on', player.bypass);
    abBtn.lastChild.textContent = player.bypass ? L('الأصلي', 'Original') : L('بعد', 'After');
  }

  function setSel(a, b) {
    if (a == null) sel = null;
    else { a = clamp(a, 0, ed.dur); b = clamp(b, 0, ed.dur); sel = a <= b ? { a, b } : { a: b, b: a }; }
    if (sel && sel.b - sel.a < 0.01) sel = null;
    if (!sel && loopOn) { loopOn = false; loopBtn.classList.remove('on'); }
    syncLoop(); dirty = true;
  }

  function zoom(f) { pps = clamp(pps * f, 1, 4000); dirty = true; }

  function addMarkerHere() {
    const n = proj.markers.length + 1;
    proj.markers.push({ t: pos(), name: L('علامة ', 'Marker ') + n });
    ed.markerSort(); saveSoon(); dirty = true;
    toast(L('تمت إضافة علامة', 'Marker added'));
    if (activeTool === 'markers') openTool('markers', true);
  }

  /* ---- editing / history ---- */
  const bytesOf = (s) => (s.chs.length * s.chs[0].length * 4) + (s.clean ? s.clean.length * s.clean[0].length * 4 : 0);
  function snapshot() { return { chs, clean: cleanChs, key: cleanDone, markers: proj.markers.map((m) => ({ ...m })) }; }
  function pushUndo() {
    undo.push(snapshot()); redo = [];
    let tot = undo.reduce((s, x) => s + bytesOf(x), 0);
    while (undo.length > 1 && (undo.length > 25 || tot > 350e6)) tot -= bytesOf(undo.shift());
    syncHist();
  }
  function syncHist() { undoBtn.disabled = !undo.length; redoBtn.disabled = !redo.length; }
  function restore(s) {
    chs = s.chs; cleanChs = s.clean; cleanDone = s.key; proj.markers = s.markers;
    afterBase(true);
  }
  function doUndo() { if (!undo.length) return; redo.push(snapshot()); restore(undo.pop()); syncHist(); }
  function doRedo() { if (!redo.length) return; undo.push(snapshot()); restore(redo.pop()); syncHist(); }

  /** Apply a destructive edit. fn(chs) -> chs | Promise<chs>. opts.mm maps marker times. */
  async function edit(fn, opts = {}) {
    const next = await fn(chs);
    if (!next || next === chs) return false;
    pushUndo();
    chs = next; cleanChs = null; cleanDone = '';
    if (opts.mm) proj.markers = proj.markers.map((m) => ({ ...m, t: opts.mm(m.t) })).filter((m) => m.t != null);
    if (opts.resetFx) { fx = defaultFx(); proj.fx = fx; loud = null; }
    afterBase(false);
    return true;
  }

  function afterBase(fromHistory) {
    buildPeaks(cleanChs || chs);
    player.setBuffers(chs, cleanChs, sr);
    center = clamp(center, 0, ed.dur);
    if (sel) setSel(sel.a, sel.b);
    if (cleanActive(fx) && (!cleanChs || cleanDone !== cleanKey())) { cleanChs = null; player.setBuffers(chs, null, sr); buildPeaks(chs); scheduleClean(fromHistory ? 200 : 400); }
    scheduleAnalyze(); saveSoon(); dirty = true; buildToolbar();
    syncHist();
  }

  /* ---- fx changes ---- */
  const cleanKey = () => JSON.stringify(fx.clean) + '|' + profileId;
  function fxChanged(kind) {
    proj.fx = fx;
    player.setFx(fx);
    if (kind === 'clean') scheduleClean(600);
    scheduleAnalyze(); saveSoon();
    if (activeTool == null) buildToolbar(); else refreshToolbarDots();
  }
  function refreshToolbarDots() {
    toolbar.querySelectorAll('.tool').forEach((el, i) => {
      const t = tools[TOOL_ORDER[i]], on = t.active && t.active(fx);
      el.classList.toggle('on', !!on);
    });
  }

  const scheduleClean = debounce(() => runClean(), 500);
  async function runClean() {
    if (closed) return;
    if (cleanJob) { cleanJob.cancel(); cleanJob = null; }
    if (!cleanActive(fx)) {
      if (cleanChs) { cleanChs = null; cleanDone = ''; player.setBuffers(chs, null, sr); buildPeaks(chs); dirty = true; scheduleAnalyze(); }
      setStatus('');
      return;
    }
    const key = cleanKey();
    if (cleanChs && cleanDone === key) { setStatus(''); return; }
    const base = chs, c = fx.clean;
    setStatus(L('جارٍ التنقية…', 'Cleaning…'));
    const job = runJob('clean', { chs: base, sr, params: { dn: c.dn, amount: c.amount, gate: c.gate, gateDb: c.gateDb, gateRange: c.gateRange, ds: c.ds }, profile: c.dn ? profile : null },
      (p) => setStatus(L('جارٍ التنقية ', 'Cleaning ') + Math.round(p * 100) + '%'));
    cleanJob = job;
    try {
      const out = await job.promise;
      if (base !== chs || key !== cleanKey()) return;
      cleanChs = out; cleanDone = key;
      player.setBuffers(chs, cleanChs, sr);
      buildPeaks(cleanChs); dirty = true;
      scheduleAnalyze();
      if (activeTool === 'noise') openTool('noise', true);
    } catch (e) {
      if (!e.cancelled) toast(L('فشلت التنقية: ', 'Cleaning failed: ') + e.message);
    } finally {
      if (cleanJob === job) { cleanJob = null; setStatus(''); }
    }
  }
  function setStatus(s) {
    status = s;
    statChip.textContent = s;
    statChip.classList.toggle('hidden', !s);
  }

  const scheduleAnalyze = debounce(async () => {
    if (closed) return;
    const id = ++anId;
    try {
      const info2 = await analyzeFx(cleanChs || chs, sr, fx);
      if (id !== anId || closed) return;
      const db = fx.norm.on && isFinite(info2.lufs) ? clamp(fx.norm.target - info2.lufs, -30, 30) : 0;
      loud = { lufs: info2.lufs + db, peakDb: fx.norm.on ? Math.min(info2.peakDb + db, fx.norm.ceil) : info2.peakDb };
      player.setNorm(db);
      loudChip.textContent = isFinite(loud.lufs) ? loud.lufs.toFixed(1) + ' LUFS' : '— LUFS';
      loudListeners.forEach((f) => f(loud));
    } catch (e) {}
  }, 900);

  const saveSoon = debounce(save, 1800);
  async function save() {
    if (!proj || closed) return;
    try {
      const src = { ...proj, chs, sr };
      await persist(src);
      proj.updated = src.updated;
    } catch (e) { toast(L('تعذّر الحفظ (المساحة ممتلئة؟)', 'Could not save (storage full?)')); }
  }

  async function rename() {
    const n = await promptBox(L('اسم المشروع', 'Project name'), proj.name);
    if (n) { proj.name = n; titleBtn.textContent = n; saveSoon(); }
  }

  /* ---- waveform peaks ---- */
  function buildPeaks(src) {
    const n = src[0].length, B1 = 64, B2 = 4096;
    const l1 = new Float32Array(Math.ceil(n / B1) + 1);
    for (const c of src) for (let b = 0; b < l1.length; b++) {
      let m = l1[b];
      const e = Math.min(n, (b + 1) * B1);
      for (let i = b * B1; i < e; i++) { const a = c[i] < 0 ? -c[i] : c[i]; if (a > m) m = a; }
      l1[b] = m;
    }
    const k = B2 / B1, l2 = new Float32Array(Math.ceil(l1.length / k) + 1);
    for (let b = 0; b < l1.length; b++) { const j = (b / k) | 0; if (l1[b] > l2[j]) l2[j] = l1[b]; }
    peaks = { n, l1, l2, B1, B2, src };
  }
  function peakAt(a, b) {
    const P = peaks;
    a = Math.max(0, Math.floor(a)); b = Math.min(P.n, Math.ceil(b));
    if (b <= a) return 0;
    let m = 0;
    if (b - a >= P.B2 * 2) { for (let i = Math.floor(a / P.B2); i <= Math.floor(b / P.B2); i++) if (P.l2[i] > m) m = P.l2[i]; }
    else if (b - a >= P.B1 * 2) { for (let i = Math.floor(a / P.B1); i <= Math.floor(b / P.B1); i++) if (P.l1[i] > m) m = P.l1[i]; }
    else for (const c of P.src) for (let i = a; i < b; i++) { const v = c[i] < 0 ? -c[i] : c[i]; if (v > m) m = v; }
    return m;
  }

  /* ---- timeline drawing ---- */
  let W = 0, H = 0, dpr = 1;
  function sizeCanvas(cv) {
    const w = cv.clientWidth, hh = cv.clientHeight;
    if (!w || !hh) return false;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(hh * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(hh * dpr); dirty = true; }
    return true;
  }
  function layout() { dirty = true; }
  const css = (n, d) => getComputedStyle(root).getPropertyValue(n).trim() || d;

  function drawTL() {
    dpr = window.devicePixelRatio || 1;
    if (!sizeCanvas(tl) || !peaks) return;
    W = tl.clientWidth; H = tl.clientHeight;
    const c = tl.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, W, H);
    const accent = css('--accent', '#25f4ee'), dur = ed.dur, RH = 26, top = RH + 6, bot = H - 8, mid = (top + bot) / 2, amp = (bot - top) / 2;
    const xOf = (t) => W / 2 + (t - center) * pps;
    const tOf = (x) => center + (x - W / 2) / pps;
    // ruler
    let step = nice.find((s) => s * pps >= 80) || nice[nice.length - 1];
    c.font = '11px system-ui, sans-serif'; c.textBaseline = 'top'; c.fillStyle = css('--muted', '#888'); c.strokeStyle = 'rgba(255,255,255,.14)';
    const t0 = Math.floor(tOf(0) / step) * step;
    c.textAlign = 'left';
    for (let t = t0; t <= tOf(W) + step; t += step) {
      if (t < -1e-6 || t > dur + step) continue;
      const x = xOf(t);
      c.beginPath(); c.moveTo(x, RH - 6); c.lineTo(x, RH); c.stroke();
      const lbl = step < 1 ? fmtTime(t, 2) : fmtTime(t, 0);
      c.fillText(lbl, x + 4, 4);
      for (let k = 1; k < 5; k++) { const xs = x + (k * step * pps) / 5; c.beginPath(); c.moveTo(xs, RH - 3); c.lineTo(xs, RH); c.stroke(); }
    }
    const x0 = xOf(0), x1 = xOf(dur);
    // selection background
    if (sel) {
      c.fillStyle = 'rgba(37,244,238,.16)';
      c.fillRect(xOf(sel.a), top - 4, xOf(sel.b) - xOf(sel.a), bot - top + 8);
    }
    // baseline
    c.strokeStyle = 'rgba(255,255,255,.12)'; c.beginPath(); c.moveTo(Math.max(0, x0), mid); c.lineTo(Math.min(W, x1), mid); c.stroke();
    // bars
    const sp = ed.sr, colW = 3;
    for (let x = 0; x < W; x += colW) {
      const ta = tOf(x), tb = tOf(x + colW);
      if (tb < 0 || ta > dur) continue;
      const p = peakAt(ta * sp, tb * sp);
      const hh = Math.max(1.2, Math.pow(Math.min(1, p), 0.72) * amp);
      const played = x + colW / 2 < W / 2;
      const inSel = sel && ta >= sel.a && tb <= sel.b;
      c.fillStyle = p >= 0.995 ? '#ff453a' : inSel ? '#fff' : played ? accent : 'rgba(255,255,255,.62)';
      c.fillRect(x, mid - hh, colW - 1, hh * 2);
    }
    // boundaries
    c.fillStyle = 'rgba(0,0,0,.45)';
    if (x0 > 0) c.fillRect(0, top - 4, Math.min(W, x0), bot - top + 8);
    if (x1 < W) c.fillRect(Math.max(0, x1), top - 4, W - x1, bot - top + 8);
    // markers
    c.textAlign = 'left'; c.font = '10.5px system-ui, sans-serif';
    proj.markers.forEach((m) => {
      const x = xOf(m.t);
      if (x < -60 || x > W + 60) return;
      c.strokeStyle = '#ffd60a'; c.lineWidth = 1.5; c.beginPath(); c.moveTo(x, RH); c.lineTo(x, bot + 4); c.stroke(); c.lineWidth = 1;
      c.fillStyle = '#ffd60a'; c.beginPath(); c.moveTo(x, RH); c.lineTo(x + 7, RH + 5); c.lineTo(x, RH + 10); c.fill();
      c.fillStyle = '#ffd60a'; c.fillText(m.name || '', x + 9, RH + 1);
    });
    // selection handles
    if (sel) {
      [sel.a, sel.b].forEach((t, i) => {
        const x = xOf(t);
        c.fillStyle = '#fff'; c.fillRect(x - 1.5, top - 6, 3, bot - top + 12);
        c.beginPath(); const r = 9;
        const cx = i === 0 ? x - r + 1 : x + r - 1;
        c.arc(cx, mid, r, 0, 7); c.fill();
        c.fillStyle = '#111'; c.fillRect(cx - 3, mid - 4, 1.6, 8); c.fillRect(cx + 1.4, mid - 4, 1.6, 8);
      });
    }
    // playhead
    c.fillStyle = '#fff'; c.fillRect(W / 2 - 1, 0, 2, H);
    c.beginPath(); c.moveTo(W / 2 - 6, 0); c.lineTo(W / 2 + 6, 0); c.lineTo(W / 2, 8); c.fill();
  }

  let lastSpec = 0;
  function drawSpec() {
    dpr = window.devicePixelRatio || 1;
    if (!sizeCanvas(spec)) return;
    const w = spec.clientWidth, hh = spec.clientHeight, c = spec.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, w, hh);
    const accent = css('--accent', '#25f4ee');
    const n = 48, bw = w / n;
    const fd = player.playing ? player.spectrum() : null;
    if (!fd) { c.fillStyle = 'rgba(255,255,255,.08)'; c.fillRect(0, hh - 2, w, 1); return; }
    for (let i = 0; i < n; i++) {
      let m = 0;
      if (fd) {
        const f0 = Math.floor(Math.pow(i / n, 2.1) * fd.length * 0.75), f1 = Math.max(f0, Math.floor(Math.pow((i + 1) / n, 2.1) * fd.length * 0.75));
        for (let k = f0; k <= f1; k++) m = Math.max(m, fd[k]);
      }
      const v = (m / 255) * (hh - 4);
      c.fillStyle = accent; c.globalAlpha = 0.85;
      c.fillRect(i * bw + 1, hh - Math.max(2, v), bw - 2, Math.max(2, v));
    }
    c.globalAlpha = 1;
    // peak level meter line
    const pk = player.playing ? player.level() : 0, db = 20 * Math.log10(Math.max(pk, 1e-5));
    c.fillStyle = db > -1 ? '#ff453a' : db > -9 ? '#ffd60a' : 'rgba(255,255,255,.6)';
    c.fillRect(0, 0, clamp((db + 60) / 60, 0, 1) * w, 2.5);
  }

  function frame() {
    raf = requestAnimationFrame(frame);
    if (closed || !peaks) return;
    if (player.playing && !dragging) { center = player.pos(); dirty = true; }
    if (dirty || player.playing) {
      curEl.textContent = fmtTime(center, 1);
      drawTL(); dirty = false;
    }
    const now = performance.now();
    if (now - lastSpec > 50) { drawSpec(); lastSpec = now; }
  }

  /* ---- pointer interaction ---- */
  let dragging = false;
  const pts = new Map();
  let gesture = null;
  const xOfT = (t) => W / 2 + (t - center) * pps;
  tl.addEventListener('pointerdown', (e) => {
    tl.setPointerCapture(e.pointerId);
    const r = tl.getBoundingClientRect();
    pts.set(e.pointerId, { x: e.clientX - r.left, y: e.clientY - r.top });
    if (pts.size === 2) {
      const [a, b] = [...pts.values()];
      gesture = { type: 'pinch', d: Math.hypot(a.x - b.x, a.y - b.y), pps };
      return;
    }
    const x = e.clientX - r.left;
    let mode = 'pan';
    if (sel) {
      const da = Math.abs(x - xOfT(sel.a)), db = Math.abs(x - xOfT(sel.b));
      if (Math.min(da, db) < 26) mode = da < db ? 'ha' : 'hb';
    }
    gesture = { type: mode, x0: x, c0: center, t0: performance.now(), moved: false, was: player.playing };
    dragging = true;
    if (mode === 'pan' && player.playing) player.pause();
  });
  tl.addEventListener('pointermove', (e) => {
    if (!pts.has(e.pointerId)) return;
    const r = tl.getBoundingClientRect(), x = e.clientX - r.left;
    pts.get(e.pointerId).x = x; pts.get(e.pointerId).y = e.clientY - r.top;
    if (!gesture) return;
    if (gesture.type === 'pinch' && pts.size === 2) {
      const [a, b] = [...pts.values()];
      pps = clamp(gesture.pps * (Math.hypot(a.x - b.x, a.y - b.y) / gesture.d), 1, 4000); dirty = true;
      return;
    }
    if (Math.abs(x - gesture.x0) > 4) gesture.moved = true;
    if (gesture.type === 'pan') {
      center = clamp(gesture.c0 - (x - gesture.x0) / pps, 0, ed.dur);
      player.offset = center; dirty = true;
    } else if (gesture.type === 'ha' || gesture.type === 'hb') {
      const t = clamp(center + (x - W / 2) / pps, 0, ed.dur);
      if (gesture.type === 'ha') setSel(t, sel.b); else setSel(sel.a, t);
      if (!sel) gesture = null;
    }
  });
  const up = (e) => {
    pts.delete(e.pointerId);
    if (!gesture) { dragging = false; return; }
    if (gesture.type === 'pinch') { if (pts.size < 2) gesture = null; dragging = pts.size > 0; return; }
    if (gesture.type === 'pan') {
      if (!gesture.moved && performance.now() - gesture.t0 < 400) {
        const r = tl.getBoundingClientRect();
        center = clamp(center + (e.clientX - r.left - W / 2) / pps, 0, ed.dur);
        player.offset = center;
      }
      if (gesture.was) player.play(center).then(updatePlayBtn);
    }
    gesture = null; dragging = false; dirty = true;
  };
  tl.addEventListener('pointerup', up);
  tl.addEventListener('pointercancel', up);
  tl.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (e.ctrlKey || Math.abs(e.deltaY) >= Math.abs(e.deltaX)) zoom(Math.exp(-e.deltaY * 0.0015));
    else { center = clamp(center + e.deltaX / pps, 0, ed.dur); player.seek(center); }
  }, { passive: false });

  window.addEventListener('keydown', (e) => {
    if (closed || e.target.closest && e.target.closest('input,textarea,select')) return;
    if (e.code === 'Space') { e.preventDefault(); togglePlay(); }
    else if ((e.ctrlKey || e.metaKey) && e.key === 'z') { e.preventDefault(); e.shiftKey ? doRedo() : doUndo(); }
    else if ((e.ctrlKey || e.metaKey) && e.key === 'y') { e.preventDefault(); doRedo(); }
    else if (e.key === 'ArrowLeft') seek(pos() - 1);
    else if (e.key === 'ArrowRight') seek(pos() + 1);
  });
  window.addEventListener('resize', () => { dirty = true; });

  /* ---- lifecycle ---- */
  async function open(p) {
    proj = p; chs = p.chs; sr = p.sr; fx = p.fx; proj.fx = fx; proj.markers = proj.markers || [];
    cleanChs = null; cleanDone = ''; sel = null; center = 0; undo = []; redo = []; clip = null; profile = null; loud = null; loopOn = false;
    player.setLoop(null); player.setBypass(false); player.setNorm(0); player.offset = 0;
    abBtn.classList.remove('on'); abBtn.lastChild.textContent = L('بعد', 'After');
    loopBtn.classList.remove('on'); loudChip.textContent = '';
    titleBtn.textContent = p.name;
    totEl.textContent = '/ ' + fmtTime(ed.dur, 1);
    closed = false; activeTool = null;
    root.classList.remove('hidden');
    document.body.classList.add('editing');
    buildPeaks(chs);
    player.setFx(fx);
    player.setBuffers(chs, null, sr);
    pps = clamp(((tl.clientWidth || 360) / 2 - 24) / Math.max(ed.dur, 0.5), 8, 400);
    openTool(null);
    syncHist(); updatePlayBtn(); setStatus('');
    if (cleanActive(fx)) scheduleClean(100);
    scheduleAnalyze();
    dirty = true;
    cancelAnimationFrame(raf); frame();
  }

  async function close() {
    if (player.playing) player.pause();
    if (cleanJob) { cleanJob.cancel(); cleanJob = null; }
    scheduleClean.cancel(); scheduleAnalyze.cancel(); saveSoon.cancel();
    const b = busy(L('جارٍ الحفظ…', 'Saving…'));
    await save();
    b.close();
    closed = true;
    cancelAnimationFrame(raf);
    root.classList.add('hidden');
    document.body.classList.remove('editing');
    onClose();
  }

  // keep total label fresh
  setInterval(() => { if (!closed && chs) totEl.textContent = '/ ' + fmtTime(ed.dur, 1); }, 500);

  return { el: root, open, close, get isOpen() { return !closed; } };
}
