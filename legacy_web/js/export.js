import { h, L, fmtBytes, fmtDur, storage } from './util.js';
import { btn, chips, section, toggle, toast, busy } from './ui.js';
import { processFull, encodeWav, encodeMp3 } from './audio.js';
import * as ops from './ops.js';

export function buildExport(ed) {
  const saved = storage.get('dod.export', {});
  const o = { fmt: 'wav', bits: 16, kbps: 192, rate: [44100, 48000].includes(ed.sr) ? ed.sr : 48000, range: 'all', ...saved };
  const name = h('input', { class: 'txt', type: 'text', value: ed.proj.name });
  const result = h('div', { class: 'export-result' });
  const qual = h('div');
  const mkQual = () => {
    qual.innerHTML = '';
    qual.append(o.fmt === 'wav'
      ? chips([{ v: 16, label: '16-bit' }, { v: 24, label: '24-bit' }, { v: 32, label: '32-bit float' }], o.bits, (v) => { o.bits = v; })
      : chips([{ v: 128, label: '128 kbps' }, { v: 192, label: '192 kbps' }, { v: 256, label: '256 kbps' }, { v: 320, label: '320 kbps' }], o.kbps, (v) => { o.kbps = v; }));
  };
  mkQual();

  async function run() {
    storage.set('dod.export', { fmt: o.fmt, bits: o.bits, kbps: o.kbps, rate: o.rate });
    let src = ed.source;
    if (o.range === 'sel') {
      const s = ed.selSamples();
      if (!s) return;
      src = ops.keep(src, ed.sr, s[0], s[1]);
    }
    const b = busy(L('جارٍ المعالجة والتصدير…', 'Rendering & exporting…'));
    try {
      b.set(0.1);
      const r = await processFull(src, ed.sr, ed.fx, { outRate: o.rate });
      b.set(0.55, L('جارٍ الترميز…', 'Encoding…'));
      const blob = o.fmt === 'wav' ? encodeWav(r.chs, r.sr, o.bits) : await encodeMp3(r.chs, r.sr, o.kbps, (p) => b.set(0.55 + p * 0.4));
      b.close();
      const ext = o.fmt === 'wav' ? 'wav' : 'mp3';
      const fname = (name.value.trim() || 'recording').replace(/[\\/:*?"<>|]+/g, '_') + '.' + ext;
      const url = URL.createObjectURL(blob);
      const file = new File([blob], fname, { type: blob.type });
      result.innerHTML = '';
      result.append(
        h('div', { class: 'ok-badge' }, '✓ ' + L('جاهز', 'Ready')),
        h('div', { class: 'info-card' },
          h('div', {}, h('bdi', {}, fname)),
          h('div', { class: 'meta' }, h('bdi', {}, fmtBytes(blob.size)), h('bdi', {}, fmtDur(r.chs[0].length / r.sr)), r.chs.length > 1 ? L('ستريو', 'Stereo') : L('مونو', 'Mono'), h('bdi', {}, r.sr / 1000 + ' kHz')),
          h('div', { class: 'meta' }, h('bdi', {}, isFinite(r.info.lufs) ? r.info.lufs.toFixed(1) + ' LUFS' : '—'), L('الذروة', 'Peak'), h('bdi', {}, r.info.peakDb.toFixed(1) + ' dB'))),
        h('div', { class: 'row wrap' },
          btn(L('حفظ / تنزيل', 'Save / download'), 'download', () => { const a = h('a', { href: url, download: fname }); document.body.append(a); a.click(); a.remove(); }, 'primary'),
          navigator.canShare && navigator.canShare({ files: [file] }) ? btn(L('مشاركة', 'Share'), 'share', () => navigator.share({ files: [file], title: fname }).catch(() => {}), 'ghost') : null),
        h('audio', { controls: true, src: url, class: 'result-audio' }));
    } catch (e) {
      b.close();
      toast(L('فشل التصدير: ', 'Export failed: ') + (e.message || e));
    }
  }

  return h('div', {},
    section(L('اسم الملف', 'File name'), name),
    section(L('الصيغة', 'Format'), chips([{ v: 'wav', label: 'WAV' }, { v: 'mp3', label: 'MP3' }], o.fmt, (v) => { o.fmt = v; mkQual(); }), qual),
    section(L('معدل العينة', 'Sample rate'), chips([{ v: 44100, label: '44.1 kHz' }, { v: 48000, label: '48 kHz' }], o.rate, (v) => { o.rate = v; })),
    ed.sel ? section(L('النطاق', 'Range'), chips([{ v: 'all', label: L('الكل', 'Everything') }, { v: 'sel', label: L('التحديد فقط', 'Selection only') }], o.range, (v) => { o.range = v; })) : null,
    h('p', { class: 'hint' }, L('يتم تطبيق كل التأثيرات (تنقية، إيكو، ضغط، صدى، تسوية الجهارة…) على الملف المُصدَّر.', 'All effects (cleanup, EQ, compression, reverb, loudness…) are applied to the exported file.')),
    btn(L('تصدير الآن', 'Export now'), 'download', run, 'primary block'),
    result);
}
