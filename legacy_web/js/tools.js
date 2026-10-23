import { h, L, clamp, fmtTime } from './util.js';
import { icon, btn, slider, toggle, chips, section, row, toast, confirmBox, promptBox, busy, vslider } from './ui.js';
import { defaultFx, mergeFx, PRESETS, EQ_PRESETS, EQ_BANDS, REVERB_TYPES } from './fx.js';
import { eqResponse, processFull } from './audio.js';
import { runJob } from './dsp.js';
import { decodeFile } from './project.js';
import * as ops from './ops.js';
import { buildExport } from './export.js';

export const TOOL_ORDER = ['presets', 'noise', 'edit', 'level', 'dynamics', 'eq', 'reverb', 'fx', 'voice', 'markers', 'export'];
const hz = (v) => (v >= 1000 ? (v / 1000).toFixed(v % 1000 ? 1 : 0) + 'k' : v) + ' Hz';
const dB = (v) => (v > 0 ? '+' : '') + v + ' dB';

export function makeTools(ed) {
  const fxS = (obj, key, o, kind = 'live') => slider({ ...o, value: obj[key], onInput: (v) => { obj[key] = v; ed.fxChanged(kind); } });
  const fxT = (obj, key, label, kind = 'live', hint) => toggle(label, obj[key], (v) => { obj[key] = v; ed.fxChanged(kind); }, hint);
  const sel = () => ed.selSamples();

  const tools = {};

  /* ------------------------------------------------ presets */
  tools.presets = {
    icon: 'sparkle', label: () => L('قوالب', 'Presets'),
    active: () => false,
    build() {
      const grid = h('div', { class: 'preset-grid' });
      PRESETS.forEach((p) => {
        grid.append(h('button', {
          class: 'preset', type: 'button',
          onclick: () => {
            const keepFades = { fi: ed.fx.fadeIn, fo: ed.fx.fadeOut };
            const nf = mergeFx(p.patch);
            nf.fadeIn = keepFades.fi; nf.fadeOut = keepFades.fo;
            ed.setFx(nf);
            toast(L('تم تطبيق: ', 'Applied: ') + L(p.ar, p.en));
            ed.rerender();
          },
        }, icon(p.icon, 26), h('span', {}, L(p.ar, p.en))));
      });
      return h('div', {}, grid,
        h('div', { class: 'row wrap' },
          btn(L('إعادة ضبط كل التأثيرات', 'Reset all effects'), 'undo', () => { ed.setFx(defaultFx()); ed.rerender(); }, 'ghost sm'),
          btn(L('دمج التأثيرات في الملف', 'Bake effects into file'), 'merge', bake, 'ghost sm')),
        h('p', { class: 'hint' }, L('القوالب نقطة بداية — عدّل أي أداة بعد ذلك. التأثيرات غير مدمّرة ويمكن تعديلها في أي وقت.', 'Presets are a starting point — tweak any tool afterwards. Effects are non‑destructive until you bake or export.')));
    },
  };
  async function bake() {
    if (!(await confirmBox(L('سيتم دمج كل التأثيرات في الصوت نهائيًا (يمكنك التراجع).', 'All effects will be rendered into the audio (you can undo).'), L('دمج', 'Bake')))) return;
    const b = busy(L('جارٍ المعالجة…', 'Processing…'));
    try {
      const r = await processFull(ed.source, ed.sr, ed.fx, { outRate: ed.sr });
      await ed.edit(() => r.chs, { resetFx: true });
      ed.rerender();
    } catch (e) { toast(L('فشلت المعالجة', 'Processing failed')); }
    b.close();
  }

  /* ------------------------------------------------ noise */
  tools.noise = {
    icon: 'shield', label: () => L('تنقية', 'Clean'),
    active: (fx) => fx.clean.dn || fx.clean.gate || fx.hpf.on || fx.lpf.on || fx.hum.on,
    reset() { const fx = ed.fx, d = defaultFx(); fx.clean.dn = false; fx.clean.gate = false; Object.assign(fx.hpf, d.hpf); Object.assign(fx.lpf, d.lpf); Object.assign(fx.hum, d.hum); },
    build() {
      const fx = ed.fx, c = fx.clean;
      const infoCard = h('div', { class: 'info-card' }, L('جارٍ قياس مستوى الضوضاء…', 'Measuring noise level…'));
      setTimeout(() => {
        const n = ed.noiseInfo();
        const q = (db) => (db < -60 ? L('ممتاز', 'Excellent') : db < -48 ? L('جيد', 'Good') : db < -38 ? L('متوسط', 'Fair') : L('عالٍ', 'High'));
        infoCard.innerHTML = '';
        infoCard.append(h('div', {}, L('أرضية الضوضاء: ', 'Noise floor: '), h('b', {}, n.before.toFixed(0) + ' dB'), ' (' + q(n.before) + ')'));
        if (n.after != null) infoCard.append(h('div', {}, L('بعد التنقية: ', 'After cleaning: '), h('b', { class: 'good' }, n.after.toFixed(0) + ' dB'), ' (' + q(n.after) + ')'));
      }, 30);
      return h('div', {},
        infoCard,
        section(L('إزالة الضوضاء الاحترافية', 'Pro noise reduction'),
          fxT(c, 'dn', L('تفعيل إزالة الضوضاء الطيفية', 'Enable spectral noise reduction'), 'clean', L('تحليل ذكي لبصمة الضوضاء ثم إزالتها', 'Learns the noise fingerprint, then removes it')),
          fxS(c, 'amount', { label: L('القوة', 'Strength'), min: 0, max: 100, def: 55, fmt: (v) => v + '%' }, 'clean'),
          row(btn(L('التقاط بصمة من التحديد', 'Learn noise from selection'), 'wave', () => ed.learnProfile(), 'ghost sm'),
            ed.hasProfile ? btn(L('بصمة تلقائية', 'Auto profile'), 'x', () => ed.clearProfile(), 'ghost sm') : null),
          h('p', { class: 'hint' }, ed.hasProfile ? L('✓ تُستخدم الآن بصمة الضوضاء الملتقطة.', '✓ Using your captured noise profile.') : L('نصيحة: حدّد مقطعًا فيه ضوضاء فقط (سكوت) ثم "التقاط بصمة" لنتيجة أدق. وإلا تُكتشف الضوضاء تلقائيًا.', 'Tip: select a noise‑only stretch and tap "Learn" for best results. Otherwise noise is detected automatically.')),
        ),
        section(L('بوابة الضوضاء (Gate)', 'Noise gate'),
          fxT(c, 'gate', L('تفعيل البوابة', 'Enable gate'), 'clean', L('تكتم الصوت في فترات الصمت', 'Silences the gaps between words')),
          fxS(c, 'gateDb', { label: L('العتبة', 'Threshold'), min: -70, max: -20, def: -45, fmt: dB }, 'clean'),
          fxS(c, 'gateRange', { label: L('مقدار الخفض', 'Reduction'), min: -60, max: -6, def: -30, fmt: dB }, 'clean'),
        ),
        section(L('فلاتر', 'Filters'),
          fxT(fx.hpf, 'on', L('قص الترددات المنخفضة (هدير/نفخ)', 'Low‑cut (rumble / plosives)')),
          fxS(fx.hpf, 'f', { label: L('تردد القص', 'Cutoff'), min: 30, max: 300, def: 80, fmt: hz }),
          fxT(fx.lpf, 'on', L('قص الترددات العالية (هسهسة)', 'High‑cut (hiss)')),
          fxS(fx.lpf, 'f', { label: L('تردد القص', 'Cutoff'), min: 3000, max: 20000, step: 100, def: 12000, fmt: hz }),
          fxT(fx.hum, 'on', L('إزالة طنين الكهرباء (Hum)', 'Remove mains hum'), 'live', L('مع التوافقيات', 'Including harmonics')),
          chips([{ v: 50, label: '50 Hz' }, { v: 60, label: '60 Hz' }], fx.hum.f, (v) => { fx.hum.f = v; ed.fxChanged('live'); }),
        ),
      );
    },
  };

  /* ------------------------------------------------ edit */
  tools.edit = {
    icon: 'scissors', label: () => L('تحرير', 'Edit'),
    active: () => false,
    build() {
      const sr = ed.sr;
      let gainDb = 6, silenceTh = -45, silenceMin = 400, silencePad = 120, insLen = 1;
      const file = h('input', { type: 'file', accept: 'audio/*', class: 'hidden' });
      file.addEventListener('change', async () => {
        const f = file.files[0]; file.value = '';
        if (!f) return;
        const b = busy(L('جارٍ الاستيراد…', 'Importing…'));
        try { const d = await decodeFile(f); await ed.edit((c) => ops.append(c, d.chs)); toast(L('تمت الإضافة في نهاية التسجيل', 'Appended to the end')); } catch (e) { toast(L('تعذّر فتح الملف', 'Could not open file')); }
        b.close();
      });
      const act = (label, ic, fn, cls = '') => btn(label, ic, fn, 'tile ' + cls);
      const clearSel = () => ed.setSel(null);
      return h('div', {},
        section(L('التحديد', 'Selection'),
          h('div', { class: 'tiles' },
            act(L('بداية هنا', 'Start here'), 'flag', () => { const p = ed.pos(); ed.setSel(p, ed.sel && ed.sel.b > p ? ed.sel.b : ed.dur); }),
            act(L('نهاية هنا', 'End here'), 'flag', () => { const p = ed.pos(); ed.setSel(ed.sel && ed.sel.a < p ? ed.sel.a : 0, p); }),
            act(L('تحديد الكل', 'Select all'), 'check', () => ed.setSel(0, ed.dur)),
            act(L('إلغاء', 'Clear'), 'x', clearSel)),
          h('p', { class: 'hint' }, L('اسحب الخط الزمني لتحريك المؤشر الأبيض ثم استخدم الأزرار، أو اسحب مقابض التحديد مباشرة.', 'Drag the timeline to move the white playhead, then use the buttons — or drag the selection handles.'))),
        section(L('قص', 'Cut'),
          h('div', { class: 'tiles' },
            act(L('حذف التحديد', 'Delete selection'), 'trash', async () => { const s = sel(); if (!s) return; const d = s[1] - s[0]; await ed.edit((c) => ops.cut(c, sr, s[0], s[1]), { mm: (t) => (t * sr >= s[1] ? t - d / sr : t * sr > s[0] ? s[0] / sr : t) }); clearSel(); }, 'danger'),
            act(L('إبقاء التحديد فقط', 'Keep selection'), 'scissors', async () => { const s = sel(); if (!s) return; await ed.edit((c) => ops.keep(c, sr, s[0], s[1]), { mm: (t) => (t * sr < s[0] || t * sr > s[1] ? null : t - s[0] / sr) }); clearSel(); ed.seek(0); }),
            act(L('حذف ما قبل المؤشر', 'Cut before playhead'), 'rew', async () => { const p = Math.round(ed.pos() * sr); await ed.edit((c) => ops.cut(c, sr, 0, p), { mm: (t) => Math.max(0, t - p / sr) }); ed.seek(0); }),
            act(L('حذف ما بعد المؤشر', 'Cut after playhead'), 'fwd', async () => { const p = Math.round(ed.pos() * sr); await ed.edit((c) => ops.cut(c, sr, p, c[0].length), { mm: (t) => (t > p / sr ? null : t) }); })),
        ),
        section(L('تعديل التحديد', 'Modify selection'),
          h('div', { class: 'tiles' },
            act(L('كتم', 'Mute'), 'silence', async () => { const s = sel(); if (s) await ed.edit((c) => ops.silence(c, sr, s[0], s[1])); }),
            act(L('عكس', 'Reverse'), 'reverse', async () => { const s = sel(); if (s) await ed.edit((c) => ops.reverse(c, s[0], s[1])); }),
            act(L('تلاشي دخول', 'Fade in'), 'fade', async () => { const s = sel(); if (s) await ed.edit((c) => ops.fadeRegion(c, s[0], s[1], 'in')); }),
            act(L('تلاشي خروج', 'Fade out'), 'fade', async () => { const s = sel(); if (s) await ed.edit((c) => ops.fadeRegion(c, s[0], s[1], 'out')); })),
          slider({ label: L('مستوى التحديد', 'Selection gain'), min: -24, max: 24, value: gainDb, def: 6, fmt: dB, onInput: (v) => { gainDb = v; } }),
          btn(L('تطبيق المستوى على التحديد', 'Apply gain to selection'), 'volume', async () => { const s = sel(); if (s) await ed.edit((c) => ops.gainRegion(c, sr, s[0], s[1], gainDb)); }, 'ghost sm')),
        section(L('نسخ ولصق', 'Copy & paste'),
          h('div', { class: 'tiles' },
            act(L('نسخ', 'Copy'), 'copy', () => { const s = sel(); if (s) { ed.clip = ops.slice(ed.chs, s[0], s[1]); toast(L('تم النسخ', 'Copied')); } }),
            act(L('لصق عند المؤشر', 'Paste at playhead'), 'paste', async () => { if (!ed.clip) { toast(L('لا يوجد شيء منسوخ', 'Nothing copied')); return; } const k = ed.clip[0].length; const p = Math.round(ed.pos() * sr); await ed.edit((c) => ops.paste(c, sr, p, ed.clip), { mm: (t) => (t >= p / sr ? t + k / sr : t) }); }),
            act(L('تكرار التحديد', 'Duplicate'), 'dup', async () => { const s = sel(); if (!s) return; const part = ops.slice(ed.chs, s[0], s[1]), k = s[1] - s[0]; await ed.edit((c) => ops.paste(c, sr, s[1], part), { mm: (t) => (t >= s[1] / sr ? t + k / sr : t) }); }))),
        section(L('الصمت', 'Silence'),
          row(chips([0.5, 1, 2, 5].map((v) => ({ v, label: v + L(' ث', 's') })), insLen, (v) => { insLen = v; })),
          btn(L('إدراج صمت عند المؤشر', 'Insert silence at playhead'), 'plus', async () => { const p = Math.round(ed.pos() * sr); await ed.edit((c) => ops.insertSilence(c, sr, p, insLen), { mm: (t) => (t >= p / sr ? t + insLen : t) }); }, 'ghost sm'),
          slider({ label: L('عتبة الصمت', 'Silence threshold'), min: -70, max: -20, value: silenceTh, def: -45, fmt: dB, onInput: (v) => { silenceTh = v; } }),
          slider({ label: L('أقل مدة للحذف', 'Min. length'), min: 150, max: 2000, step: 50, value: silenceMin, def: 400, fmt: (v) => v + ' ms', onInput: (v) => { silenceMin = v; } }),
          slider({ label: L('هامش يُبقى حول الكلام', 'Padding kept'), min: 0, max: 400, step: 10, value: silencePad, def: 120, fmt: (v) => v + ' ms', onInput: (v) => { silencePad = v; } }),
          btn(L('حذف فترات الصمت تلقائيًا', 'Auto‑remove silences'), 'sparkle', async () => {
            let removed = 0, map = null;
            const ok = await ed.edit((c) => { const r = ops.removeSilences(c, sr, { thDb: silenceTh, minMs: silenceMin, padMs: silencePad }); removed = r.removed; map = r.map; return r.removed > 0 ? r.chs : null; }, { mm: (t) => (map ? map(t) : t) });
            toast(ok ? L('تم حذف ', 'Removed ') + removed.toFixed(1) + L(' ثانية من الصمت', ' s of silence') : L('لم يُعثر على صمت للحذف', 'No silence found'));
          }, 'primary sm')),
        section(L('إضافة', 'Add'), btn(L('إلحاق ملف صوتي بالنهاية', 'Append an audio file'), 'upload', () => file.click(), 'ghost sm'), file),
      );
    },
  };

  /* ------------------------------------------------ level */
  tools.level = {
    icon: 'volume', label: () => L('المستوى', 'Level'),
    active: (fx) => fx.gain !== 0 || fx.norm.on || fx.fadeIn > 0 || fx.fadeOut > 0,
    reset() { const fx = ed.fx, d = defaultFx(); fx.gain = 0; fx.norm = d.norm; fx.fadeIn = 0; fx.fadeOut = 0; },
    build() {
      const fx = ed.fx;
      const readout = h('div', { class: 'info-card' });
      const upd = (l) => {
        if (!l) { readout.textContent = L('جارٍ القياس…', 'Measuring…'); return; }
        readout.innerHTML = '';
        readout.append(h('div', {}, L('الجهارة: ', 'Loudness: '), h('b', {}, isFinite(l.lufs) ? l.lufs.toFixed(1) + ' LUFS' : '—')),
          h('div', {}, L('الذروة: ', 'Peak: '), h('b', { class: l.peakDb > -0.5 ? 'bad' : '' }, l.peakDb.toFixed(1) + ' dBFS')));
      };
      upd(ed.loud);
      ed.onLoud(upd);
      const el = h('div', {},
        readout,
        section(L('مستوى الصوت', 'Volume'),
          slider({ label: L('تضخيم', 'Gain'), min: -24, max: 24, step: 0.5, value: fx.gain, def: 0, fmt: dB, onInput: (v) => { fx.gain = v; ed.fxChanged('live'); } })),
        section(L('تسوية الجهارة (Normalize)', 'Loudness normalisation'),
          fxT(fx.norm, 'on', L('تفعيل تسوية الجهارة', 'Enable loudness target'), 'live', L('يضبط الجهارة تلقائيًا + محدّد قمم', 'Auto‑levels + true peak limiter')),
          chips([{ v: -23, label: L('إذاعة −23', 'Broadcast −23') }, { v: -16, label: L('بودكاست −16', 'Podcast −16') }, { v: -14, label: L('يوتيوب −14', 'Streaming −14') }, { v: -12, label: L('عالٍ −12', 'Loud −12') }], fx.norm.target, (v) => { fx.norm.target = v; fx.norm.on = true; ed.fxChanged('live'); ed.rerender(); }),
          fxS(fx.norm, 'ceil', { label: L('سقف القمم', 'Peak ceiling'), min: -6, max: 0, step: 0.1, def: -1, fmt: (v) => v + ' dB' })),
        section(L('تلاشي', 'Fades'),
          fxS(fx, 'fadeIn', { label: L('تلاشي في البداية', 'Fade in'), min: 0, max: 10, step: 0.1, def: 0, fmt: (v) => v.toFixed(1) + L(' ث', ' s') }),
          fxS(fx, 'fadeOut', { label: L('تلاشي في النهاية', 'Fade out'), min: 0, max: 10, step: 0.1, def: 0, fmt: (v) => v.toFixed(1) + L(' ث', ' s') })),
      );
      return el;
    },
  };

  /* ------------------------------------------------ dynamics */
  const COMP_PRESETS = {
    gentle: { th: -20, ratio: 2, attack: 25, release: 300, knee: 20, makeup: 2 },
    voice: { th: -24, ratio: 3.5, attack: 10, release: 200, knee: 12, makeup: 4 },
    broadcast: { th: -28, ratio: 5, attack: 5, release: 150, knee: 8, makeup: 6 },
    squash: { th: -34, ratio: 10, attack: 3, release: 100, knee: 4, makeup: 9 },
  };
  tools.dynamics = {
    icon: 'gauge', label: () => L('ديناميكس', 'Dynamics'),
    active: (fx) => fx.comp.on || fx.warm.on || fx.clean.ds > 0,
    reset() { const fx = ed.fx, d = defaultFx(); fx.comp = d.comp; fx.warm = d.warm; fx.clean.ds = 0; },
    build() {
      const fx = ed.fx, c = fx.comp;
      const sliders = h('div');
      const mk = () => {
        sliders.innerHTML = '';
        sliders.append(
          fxS(c, 'th', { label: L('العتبة', 'Threshold'), min: -60, max: 0, def: -24, fmt: dB }),
          fxS(c, 'ratio', { label: L('النسبة', 'Ratio'), min: 1, max: 20, step: 0.5, def: 3, fmt: (v) => v + ':1' }),
          fxS(c, 'attack', { label: L('الهجوم', 'Attack'), min: 1, max: 100, def: 10, fmt: (v) => v + ' ms' }),
          fxS(c, 'release', { label: L('الإفلات', 'Release'), min: 20, max: 1000, step: 10, def: 200, fmt: (v) => v + ' ms' }),
          fxS(c, 'makeup', { label: L('تعويض المستوى', 'Make‑up gain'), min: 0, max: 24, step: 0.5, def: 3, fmt: dB }));
      };
      mk();
      return h('div', {},
        section(L('الضاغط (Compressor)', 'Compressor'),
          fxT(c, 'on', L('تفعيل الضاغط', 'Enable compressor'), 'live', L('يوازن بين الصوت العالي والخافت', 'Evens out loud and quiet parts')),
          chips([['gentle', L('خفيف', 'Gentle')], ['voice', L('صوت', 'Voice')], ['broadcast', L('إذاعي', 'Broadcast')], ['squash', L('قوي', 'Heavy')]].map(([v, label]) => ({ v, label })), '', (v) => { Object.assign(c, COMP_PRESETS[v], { on: true }); ed.fxChanged('live'); mk(); ed.rerender(); }),
          sliders),
        section(L('إزالة حرف السين (De‑esser)', 'De‑esser'),
          slider({ label: L('القوة', 'Amount'), min: 0, max: 100, value: fx.clean.ds, def: 0, fmt: (v) => (v ? v + '%' : L('متوقف', 'Off')), onInput: (v) => { fx.clean.ds = v; ed.fxChanged('clean'); } })),
        section(L('دفء وتشبّع (Warmth)', 'Warmth / saturation'),
          fxT(fx.warm, 'on', L('تفعيل الدفء', 'Enable warmth'), 'live', L('لمسة تشبّع أنبوبي ناعمة', 'Soft tube‑style saturation')),
          fxS(fx.warm, 'amount', { label: L('المقدار', 'Amount'), min: 0, max: 100, def: 25, fmt: (v) => v + '%' })),
      );
    },
  };

  /* ------------------------------------------------ eq */
  tools.eq = {
    icon: 'sliders', label: () => L('إيكوالايزر', 'EQ'),
    active: (fx) => fx.eq.on,
    reset() { const fx = ed.fx; fx.eq = defaultFx().eq; },
    build() {
      const fx = ed.fx, eq = fx.eq;
      const cv = h('canvas', { class: 'eq-curve' });
      const draw = () => {
        const dpr = window.devicePixelRatio || 1, w = cv.clientWidth || 320, hh = 92;
        cv.width = w * dpr; cv.height = hh * dpr; cv.style.height = hh + 'px';
        const c = cv.getContext('2d'); c.setTransform(dpr, 0, 0, dpr, 0, 0);
        c.strokeStyle = 'rgba(255,255,255,.1)';
        [-12, -6, 0, 6, 12].forEach((g) => { const y = hh / 2 - (g / 15) * (hh / 2 - 4); c.beginPath(); c.moveTo(0, y); c.lineTo(w, y); c.stroke(); });
        const r = eqResponse(eq.bands, 100);
        c.beginPath();
        r.db.forEach((d, i) => { const x = (i / 99) * w, y = hh / 2 - (clamp(d, -15, 15) / 15) * (hh / 2 - 4); i ? c.lineTo(x, y) : c.moveTo(x, y); });
        c.strokeStyle = getComputedStyle(cv).getPropertyValue('--accent').trim() || '#25f4ee'; c.lineWidth = 2.5; c.stroke();
        c.lineTo(w, hh / 2); c.lineTo(0, hh / 2); c.fillStyle = 'rgba(37,244,238,.12)'; c.fill();
      };
      const sliders = [], labels = [];
      const bandsEl = h('div', { class: 'eq-bands' });
      eq.bands.forEach((g, i) => {
        const val = h('small', {}, dB(g));
        labels[i] = val;
        const v = vslider({ min: -12, max: 12, value: g, onInput: (nv) => { eq.bands[i] = nv; val.textContent = dB(nv); eq.on = true; draw(); ed.fxChanged('live'); onLabel(); } });
        sliders[i] = v;
        bandsEl.append(h('div', { class: 'eq-b' }, val, v, h('span', {}, hz(EQ_BANDS[i].f).replace(' Hz', ''))));
      });
      const onLabel = () => { enable.set(eq.on); };
      const enable = toggle(L('تفعيل الإيكوالايزر', 'Enable equalizer'), eq.on, (v) => { eq.on = v; ed.fxChanged('live'); });
      const root = h('div', {}, enable, cv, bandsEl,
        section(L('إعدادات جاهزة', 'Presets'),
          chips(EQ_PRESETS.map((p) => ({ v: p.id, label: L(p.ar, p.en) })), '', (id) => {
            const p = EQ_PRESETS.find((x) => x.id === id);
            eq.bands = p.g.slice(); eq.on = id !== 'flat' || eq.on;
            sliders.forEach((s, i) => s.set(eq.bands[i])); labels.forEach((l, i) => (l.textContent = dB(eq.bands[i])));
            enable.set(eq.on); draw(); ed.fxChanged('live');
          }, 'scroll')));
      requestAnimationFrame(draw);
      return root;
    },
  };

  /* ------------------------------------------------ reverb */
  tools.reverb = {
    icon: 'reverb', label: () => L('صدى مكان', 'Reverb'),
    active: (fx) => fx.reverb.on,
    reset() { ed.fx.reverb = defaultFx().reverb; },
    build() {
      const fx = ed.fx, r = fx.reverb;
      const dec = slider({ label: L('حجم المكان (مدة الصدى)', 'Size (decay)'), min: 0.3, max: 8, step: 0.1, value: r.decay, def: 1.2, fmt: (v) => v.toFixed(1) + L(' ث', ' s'), onInput: (v) => { r.decay = v; ed.fxChanged('live'); } });
      const dmp = fxS(r, 'damp', { label: L('امتصاص الترددات العالية', 'Damping'), min: 0, max: 100, def: 50, fmt: (v) => v + '%' });
      const pre = fxS(r, 'pre', { label: L('تأخير مسبق', 'Pre‑delay'), min: 0, max: 120, def: 15, fmt: (v) => v + ' ms' });
      return h('div', {},
        fxT(r, 'on', L('تفعيل الصدى', 'Enable reverb')),
        chips(Object.entries(REVERB_TYPES).map(([v, t]) => ({ v, label: L(t.ar, t.en) })), r.type, (v) => {
          const t = REVERB_TYPES[v]; r.type = v; r.decay = t.decay; r.damp = t.damp; r.pre = t.pre; r.on = true;
          dec.set(r.decay); dmp.set(r.damp); pre.set(r.pre); ed.fxChanged('live');
        }, 'scroll'),
        fxS(r, 'mix', { label: L('كمية الصدى (Mix)', 'Wet mix'), min: 0, max: 100, def: 25, fmt: (v) => v + '%' }),
        dec, dmp, pre,
        h('p', { class: 'hint' }, L('"مسجد / جامع" مناسب للتلاوة والأذان والخطب.', '"Mosque" suits recitation, adhan and sermons.')));
    },
  };

  /* ------------------------------------------------ echo / chorus */
  tools.fx = {
    icon: 'echo', label: () => L('أصداء', 'Echo'),
    active: (fx) => fx.echo.on || fx.chorus.on,
    reset() { const fx = ed.fx, d = defaultFx(); fx.echo = d.echo; fx.chorus = d.chorus; },
    build() {
      const fx = ed.fx;
      return h('div', {},
        section(L('تكرار الصوت (Echo / Delay)', 'Echo / delay'),
          fxT(fx.echo, 'on', L('تفعيل', 'Enable')),
          chips([{ v: 120, label: '120ms' }, { v: 250, label: '250ms' }, { v: 400, label: '400ms' }, { v: 600, label: '600ms' }], '', (v) => { fx.echo.time = v; fx.echo.on = true; ed.fxChanged('live'); ed.rerender(); }),
          fxS(fx.echo, 'time', { label: L('زمن التأخير', 'Time'), min: 40, max: 1500, step: 10, def: 320, fmt: (v) => v + ' ms' }),
          fxS(fx.echo, 'fb', { label: L('عدد التكرارات (Feedback)', 'Feedback'), min: 0, max: 90, def: 35, fmt: (v) => v + '%' }),
          fxS(fx.echo, 'mix', { label: L('الكمية', 'Mix'), min: 0, max: 100, def: 25, fmt: (v) => v + '%' }),
          fxS(fx.echo, 'tone', { label: L('نعومة التكرار', 'Tone'), min: 1000, max: 12000, step: 100, def: 5000, fmt: hz })),
        section(L('كورَس / مضاعفة الصوت', 'Chorus / doubler'),
          fxT(fx.chorus, 'on', L('تفعيل', 'Enable'), 'live', L('يعطي اتساعًا وكثافة (ستريو)', 'Adds width and thickness (stereo)')),
          fxS(fx.chorus, 'depth', { label: L('العمق', 'Depth'), min: 0, max: 100, def: 50, fmt: (v) => v + '%' }),
          fxS(fx.chorus, 'rate', { label: L('السرعة', 'Rate'), min: 0.1, max: 6, step: 0.1, def: 1.2, fmt: (v) => v.toFixed(1) + ' Hz' }),
          fxS(fx.chorus, 'mix', { label: L('الكمية', 'Mix'), min: 0, max: 100, def: 40, fmt: (v) => v + '%' })));
    },
  };

  /* ------------------------------------------------ voice */
  tools.voice = {
    icon: 'note', label: () => L('الصوت', 'Voice'),
    active: (fx) => fx.ring.on,
    reset() { ed.fx.ring = defaultFx().ring; },
    build() {
      const fx = ed.fx;
      let semis = 0, tempo = 100;
      const run = async () => {
        if (semis === 0 && tempo === 100) { toast(L('غيّر النغمة أو السرعة أولاً', 'Change pitch or speed first')); return; }
        const t = tempo / 100;
        const job = runJob('stretch', { chs: ed.chs, sr: ed.sr, tempo: t, semis });
        const b = busy(L('جارٍ المعالجة…', 'Processing…'), { cancel: () => job.cancel() });
        try {
          const out = await job.promise;
          b.close();
          await ed.edit(() => out, { mm: (x) => x / t });
          toast(L('تم التطبيق', 'Applied'));
        } catch (e) { b.close(); if (!e.cancelled) toast(L('فشلت المعالجة', 'Processing failed')); }
      };
      return h('div', {},
        section(L('تغيير النغمة والسرعة (دون تشويه)', 'Pitch & speed (high quality)'),
          slider({ label: L('النغمة (Pitch)', 'Pitch'), min: -12, max: 12, step: 0.5, value: 0, def: 0, fmt: (v) => (v > 0 ? '+' : '') + v + L(' نصف نغمة', ' st'), onInput: (v) => { semis = v; } }),
          slider({ label: L('السرعة (دون تغيير النغمة)', 'Speed (keeps pitch)'), min: 50, max: 200, step: 1, value: 100, def: 100, fmt: (v) => v + '%', onInput: (v) => { tempo = v; } }),
          btn(L('تطبيق على الملف', 'Apply to audio'), 'check', run, 'primary sm'),
          h('p', { class: 'hint' }, L('مفيد لمراجعة التلاوة بسرعة أبطأ، أو لتسريع المحتوى. يمكن التراجع.', 'Great for slowing down recitation for review, or speeding up content. Undoable.'))),
        section(L('تأثير صوت الروبوت', 'Robot voice'),
          fxT(fx.ring, 'on', L('تفعيل', 'Enable')),
          fxS(fx.ring, 'f', { label: L('التردد', 'Frequency'), min: 15, max: 400, def: 50, fmt: hz })),
        h('p', { class: 'hint' }, L('لتأثيرات مثل الهاتف والميجافون والكهف راجع "قوالب".', 'For telephone, megaphone and cave looks see "Presets".')));
    },
  };

  /* ------------------------------------------------ markers */
  tools.markers = {
    icon: 'flag', label: () => L('علامات', 'Markers'),
    active: () => false,
    build() {
      const list = h('div', { class: 'mk-list' });
      const render = () => {
        list.innerHTML = '';
        const ms = ed.markers();
        if (!ms.length) list.append(h('p', { class: 'hint' }, L('لا توجد علامات. أضف علامة عند أي نقطة مهمة (بداية آية، خطأ يحتاج إعادة، فاصل…).', 'No markers yet. Drop one at any important point (a verse start, a retake, a chapter…).')));
        ms.forEach((m, i) => {
          list.append(h('div', { class: 'mk' },
            h('button', { class: 'mk-go', type: 'button', onclick: () => ed.seek(m.t) }, icon('flag', 16), h('b', {}, fmtTime(m.t, 1)), h('span', {}, m.name)),
            h('button', { class: 'ibtn tiny', type: 'button', onclick: async () => { const n = await promptBox(L('اسم العلامة', 'Marker name'), m.name); if (n != null) { m.name = n; ed.markersChanged(); render(); } } }, icon('edit', 16)),
            h('button', { class: 'ibtn tiny', type: 'button', onclick: () => { ms.splice(i, 1); ed.markersChanged(); render(); } }, icon('trash', 16))));
        });
      };
      render();
      return h('div', {},
        btn(L('إضافة علامة عند المؤشر', 'Add marker at playhead'), 'plus', () => { ed.markers().push({ t: ed.pos(), name: L('علامة ', 'Marker ') + (ed.markers().length + 1) }); ed.markerSort(); ed.markersChanged(); render(); }, 'primary sm'),
        list);
    },
  };

  /* ------------------------------------------------ export */
  tools.export = {
    icon: 'download', label: () => L('تصدير', 'Export'),
    active: () => false,
    build() { return buildExport(ed); },
  };

  return tools;
}

