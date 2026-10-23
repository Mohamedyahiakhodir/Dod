import { h, L, fmtTime, fmtBytes, clamp, storage, sleep } from './util.js';
import { Recorder } from './recorder.js';
import { icon, iconBtn, toggle, slider, chips, toast, section } from './ui.js';
import { noiseFloorDb } from './audio.js';

export function createRecordView({ onFinish, setNavHidden }) {
  const rec = new Recorder();
  Object.assign(rec.opts, storage.get('dod.rec', {}));
  const saveOpts = () => storage.set('dod.rec', rec.opts);
  let view = 'wave', panelOpen = false, micState = 'idle', raf = 0, bars = [], floorHist = [], peakHold = 0, peakHoldT = 0, countdown = 0;
  let wake = null;

  const root = h('div', { class: 'view rec-view' });
  const canvas = h('canvas', { class: 'rec-canvas' });
  const timer = h('div', { class: 'rec-time' }, '00:00.0');
  const sub = h('div', { class: 'rec-sub' });
  const meterFill = h('i'), meterPeak = h('b'), meterTxt = h('span', { class: 'm-db' }, '-∞');
  const meter = h('div', { class: 'meter-wrap' }, h('div', { class: 'meter' }, meterFill, meterPeak), meterTxt);
  const roomChip = h('div', { class: 'chip-info' });
  const clipChip = h('div', { class: 'chip-info warn hidden' }, L('تقطيع!', 'CLIP!'));
  const cdEl = h('div', { class: 'countdown hidden' });
  const mainBtn = h('button', { class: 'rec-btn', type: 'button', 'aria-label': 'record' }, h('span', { class: 'rec-dot' }));
  const pauseBtn = iconBtn('pause', () => togglePause(), 'round hidden', L('إيقاف مؤقت', 'Pause'));
  const flagBtn = iconBtn('flag', () => addMarker(), 'round hidden', L('علامة', 'Marker'));
  const optBtn = iconBtn('sliders', () => setPanel(!panelOpen), 'round', L('خيارات', 'Options'));
  const viewBtn = iconBtn('wave', () => { view = view === 'wave' ? 'spec' : 'wave'; }, 'round', L('طريقة العرض', 'View'));
  const panel = h('div', { class: 'rec-panel' });
  const errBox = h('div', { class: 'err-box hidden' });

  root.append(
    h('header', { class: 'top' }, h('h1', {}, L('ستوديو الصوت', 'Voice Studio')), h('div', { class: 'top-r' }, roomChip, clipChip)),
    h('div', { class: 'rec-stage' }, canvas, cdEl, errBox),
    h('div', { class: 'rec-info' }, timer, sub),
    meter,
    h('div', { class: 'rec-ctl' }, optBtn, flagBtn, mainBtn, pauseBtn, viewBtn),
    panel,
  );

  function setPanel(v) {
    panelOpen = v;
    root.classList.toggle('panel-open', v);
    optBtn.classList.toggle('on', v);
    if (v) buildPanel();
  }

  function buildPanel() {
    panel.innerHTML = '';
    const recording = rec.state !== 'idle';
    const o = rec.opts;
    const devSel = h('select', { class: 'sel' }, h('option', { value: '' }, L('الميكروفون الافتراضي', 'Default microphone')));
    rec.devices().then((ds) => {
      ds.forEach((d, i) => devSel.append(h('option', { value: d.deviceId }, d.label || L('ميكروفون ', 'Microphone ') + (i + 1))));
      devSel.value = o.deviceId || '';
    });
    devSel.addEventListener('change', async () => { o.deviceId = devSel.value; saveOpts(); if (!recording) await openMic(); else toast(L('سيُطبَّق في التسجيل القادم', 'Applies to next recording')); });

    panel.append(
      h('div', { class: 'panel-handle', onclick: () => setPanel(false) }, h('span')),
      h('div', { class: 'panel-body' },
        section(L('معالجة الميكروفون', 'Microphone processing'),
          toggle(L('إلغاء الضوضاء (حي)', 'Noise suppression (live)'), o.ns, async (v) => { o.ns = v; saveOpts(); await rec.applyProcessing(); }, L('يقلل ضوضاء الخلفية أثناء التسجيل', 'Reduces background noise while recording')),
          toggle(L('إلغاء الصدى', 'Echo cancellation'), o.ec, async (v) => { o.ec = v; saveOpts(); await rec.applyProcessing(); }, L('مفيد عند استخدام السماعة', 'Useful with speakers')),
          toggle(L('ضبط تلقائي للمستوى (AGC)', 'Auto gain (AGC)'), o.agc, async (v) => { o.agc = v; saveOpts(); await rec.applyProcessing(); }, L('أطفئه للحصول على تسجيل نقي', 'Turn off for pure recordings')),
        ),
        section(L('المستوى والمراقبة', 'Level & monitoring'),
          slider({ label: L('تضخيم الدخل', 'Input gain'), min: -12, max: 30, step: 1, value: o.gainDb, def: 0, fmt: (v) => (v > 0 ? '+' : '') + v + ' dB', onInput: (v) => { rec.setGain(v); }, onChange: saveOpts }),
          toggle(L('مراقبة الصوت بالسماعات', 'Monitor in headphones'), o.monitor, (v) => { rec.setMonitor(v); saveOpts(); if (v) toast(L('استخدم سماعات لتجنب الصدى!', 'Use headphones to avoid feedback!')); }, L('استخدم سماعات فقط', 'Headphones only')),
        ),
        section(L('الإدخال', 'Input'),
          devSel,
          toggle(L('ستريو', 'Stereo'), o.stereo, async (v) => { o.stereo = v; saveOpts(); if (!recording) await openMic(); else toast(L('سيُطبَّق في التسجيل القادم', 'Applies to next recording')); }, L('يتطلب ميكروفون ستريو', 'Needs a stereo mic')),
          toggle(L('عدّ تنازلي قبل البدء (3 ثوانٍ)', 'Countdown before start (3s)'), !!o.countdown, (v) => { o.countdown = v; saveOpts(); }),
          toggle(L('إبقاء الشاشة مضاءة', 'Keep screen awake'), o.wake !== false, (v) => { o.wake = v; saveOpts(); }),
        ),
        h('p', { class: 'hint' }, L('نصيحة: سجّل بصوت خام (بدون AGC) وسيتولى المحرر التنقية والإيكو والضغط بشكل غير مدمّر.', 'Tip: record raw (no AGC) — the editor handles cleanup, EQ and compression non‑destructively.')),
      ),
    );
  }

  async function openMic() {
    errBox.classList.add('hidden');
    micState = 'opening';
    try {
      await rec.open();
      micState = 'ready';
      rec.onChunk = onChunk;
      floorHist = [];
    } catch (e) {
      micState = 'error';
      const denied = e && (e.name === 'NotAllowedError' || e.name === 'SecurityError');
      errBox.classList.remove('hidden');
      errBox.innerHTML = '';
      errBox.append(
        icon('mic', 34),
        h('p', {}, denied ? L('لم يتم السماح باستخدام الميكروفون. فعّل الإذن من إعدادات المتصفح ثم أعد المحاولة.', 'Microphone access was blocked. Allow it in your browser settings and retry.')
          : L('تعذّر فتح الميكروفون: ', 'Could not open the microphone: ') + (e.message || e.name)),
        h('button', { class: 'btn primary', onclick: openMic }, L('إعادة المحاولة', 'Retry')),
      );
    }
    updateUI();
  }

  function onChunk(l) {
    const g = 512;
    for (let i = 0; i + g <= l.length; i += g) {
      let m = 0;
      for (let j = i; j < i + g; j++) { const a = Math.abs(l[j]); if (a > m) m = a; }
      bars.push(m);
      if (m >= 0.99) rec.clips++;
    }
    if (bars.length > 2000) bars.splice(0, bars.length - 1500);
  }

  async function start() {
    if (micState !== 'ready') await openMic();
    if (micState !== 'ready') return;
    if (rec.opts.countdown) {
      for (let i = 3; i > 0; i--) { cdEl.textContent = i; cdEl.classList.remove('hidden'); cdEl.classList.remove('pop'); void cdEl.offsetWidth; cdEl.classList.add('pop'); await sleep(850); }
      cdEl.classList.add('hidden');
    }
    bars = [];
    rec.start();
    setNavHidden(true);
    try { if (rec.opts.wake !== false && navigator.wakeLock) wake = await navigator.wakeLock.request('screen'); } catch (e) {}
    if (!panelOpen && storage.get('dod.autopanel', true)) setPanel(true);
    else if (panelOpen) buildPanel();
    updateUI();
  }

  async function stop() {
    const r = await rec.stop();
    try { wake && wake.release(); } catch (e) {}
    wake = null;
    setNavHidden(false);
    setPanel(false);
    updateUI();
    if (r && r.chs[0].length > rec.sr * 0.3) onFinish(r);
    else toast(L('التسجيل قصير جدًا', 'Recording too short'));
  }

  function togglePause() {
    if (rec.state === 'recording') rec.pause(); else rec.resume();
    updateUI();
  }
  function addMarker() {
    const n = rec.addMarker();
    rec.markers[n - 1].name = L('علامة ', 'Marker ') + n;
    toast(L('تمت إضافة علامة عند ', 'Marker added at ') + fmtTime(rec.time, 1));
    if (navigator.vibrate) navigator.vibrate(20);
  }

  mainBtn.addEventListener('click', () => { if (rec.state === 'idle') start(); else stop(); });

  function updateUI() {
    const st = rec.state;
    root.classList.toggle('is-rec', st !== 'idle');
    mainBtn.classList.toggle('on', st !== 'idle');
    pauseBtn.classList.toggle('hidden', st === 'idle');
    flagBtn.classList.toggle('hidden', st === 'idle');
    pauseBtn.innerHTML = '';
    pauseBtn.append(icon(st === 'paused' ? 'play' : 'pause', 22));
    viewBtn.classList.toggle('hidden', false);
    sub.textContent = st === 'idle'
      ? (micState === 'ready' ? L('اضغط للتسجيل', 'Tap to record') : micState === 'opening' ? L('جارٍ تشغيل الميكروفون…', 'Starting microphone…') : '')
      : st === 'paused' ? L('متوقف مؤقتًا', 'Paused') : L('جارٍ التسجيل…', 'Recording…');
  }

  const floorTxt = (db) => db < -60 ? L('هادئة جدًا', 'Very quiet') : db < -48 ? L('هادئة', 'Quiet') : db < -38 ? L('ضوضاء متوسطة', 'Some noise') : L('ضوضاء عالية', 'Noisy');
  let lastFloor = 0;

  function draw() {
    raf = requestAnimationFrame(draw);
    if (!root.isConnected || root.classList.contains('hidden')) return;
    const dpr = window.devicePixelRatio || 1, W = canvas.clientWidth, H = canvas.clientHeight;
    if (!W) return;
    if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) { canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr); }
    const c = canvas.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.clearRect(0, 0, W, H);
    const lv = rec.level();
    const cs = getComputedStyle(root);
    const accent = cs.getPropertyValue('--accent').trim() || '#25f4ee', red = cs.getPropertyValue('--rec').trim() || '#ff3b5c';
    // idle bars tick so the display feels alive while the mic is open
    if (rec.state === 'idle' && micState === 'ready') {
      const now = performance.now();
      if (now - lastFloor > 40) { bars.push(lv.peak); if (bars.length > 600) bars.shift(); lastFloor = now; }
    }
    if (view === 'wave') {
      const bw = 4, gap = 2, cnt = Math.floor(W / (bw + gap)), mid = H / 2;
      const recording = rec.state !== 'idle';
      const slice = bars.slice(-cnt);
      c.strokeStyle = 'rgba(255,255,255,.08)'; c.beginPath(); c.moveTo(0, mid); c.lineTo(W, mid); c.stroke();
      for (let i = 0; i < slice.length; i++) {
        const x = W - (slice.length - i) * (bw + gap), v = Math.pow(clamp(slice[i], 0, 1), 0.6);
        const hh = Math.max(2, v * H * 0.46);
        c.fillStyle = slice[i] > 0.97 ? '#ff3b30' : recording ? red : accent;
        c.globalAlpha = recording ? 1 : 0.55;
        c.beginPath(); c.roundRect ? c.roundRect(x, mid - hh, bw, hh * 2, 2) : c.rect(x, mid - hh, bw, hh * 2); c.fill();
      }
      c.globalAlpha = 1;
    } else if (rec.analyser) {
      const fd = rec.spectrum(), n = 56, bw = W / n;
      for (let i = 0; i < n; i++) {
        const f0 = Math.pow(i / n, 2.2) * fd.length * 0.8, f1 = Math.pow((i + 1) / n, 2.2) * fd.length * 0.8;
        let m = 0;
        for (let k = Math.floor(f0); k <= Math.max(Math.floor(f0), Math.floor(f1)); k++) m = Math.max(m, fd[k] || 0);
        const hh = (m / 255) * H * 0.92;
        const g = c.createLinearGradient(0, H, 0, H - hh);
        g.addColorStop(0, rec.state !== 'idle' ? red : accent); g.addColorStop(1, '#ffffff55');
        c.fillStyle = g; c.fillRect(i * bw + 1, H - hh, bw - 2, hh);
      }
    }
    // meter
    const db = 20 * Math.log10(Math.max(lv.peak, 1e-5)), pct = clamp((db + 60) / 60, 0, 1);
    meterFill.style.width = pct * 100 + '%';
    meterFill.className = db > -3 ? 'hot' : db > -12 ? 'mid' : '';
    const now = performance.now();
    if (pct >= peakHold || now - peakHoldT > 1200) { peakHold = pct; peakHoldT = now; }
    meterPeak.style.left = peakHold * 100 + '%';
    meterTxt.textContent = lv.peak > 1e-4 ? db.toFixed(0) + ' dB' : '-∞';
    // timer / size
    if (rec.state !== 'idle') {
      timer.textContent = fmtTime(rec.time, 1);
      sub.innerHTML = '';
      sub.append((rec.state === 'paused' ? L('متوقف مؤقتًا', 'Paused') : L('جارٍ التسجيل…', 'Recording…')) + ' • ', h('bdi', {}, fmtBytes(rec.samples * 4 * rec.channels)));
    } else timer.textContent = '00:00.0';
    clipChip.classList.toggle('hidden', !rec.clips);
    // room noise indicator while idle
    if (rec.state === 'idle' && micState === 'ready') {
      floorHist.push(Math.max(lv.rms, 1e-6));
      if (floorHist.length > 300) floorHist.shift();
      if (floorHist.length > 30) {
        const sorted = floorHist.slice().sort((a, b) => a - b);
        const fl = 20 * Math.log10(sorted[Math.floor(sorted.length * 0.2)]);
        roomChip.textContent = L('الغرفة: ', 'Room: ') + floorTxt(fl);
        roomChip.className = 'chip-info ' + (fl < -48 ? 'ok' : fl < -38 ? 'mid' : 'warn');
      }
    } else if (rec.state !== 'idle') { roomChip.textContent = ''; roomChip.className = 'chip-info hidden'; }
  }

  return {
    el: root,
    rec,
    async show() {
      root.classList.remove('hidden');
      if (micState !== 'ready' && micState !== 'opening') await openMic();
      if (!raf) draw();
      updateUI();
    },
    hide() {
      if (rec.state === 'idle') { rec.close(); micState = 'idle'; }
      cancelAnimationFrame(raf); raf = 0;
    },
    isRecording: () => rec.state !== 'idle',
    refresh() { updateUI(); if (panelOpen) buildPanel(); },
  };
}
