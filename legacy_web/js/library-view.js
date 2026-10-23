import { h, L, fmtDur, fmtBytes } from './util.js';
import { icon, iconBtn, toast, confirmBox, promptBox, actionSheet, busy } from './ui.js';
import { listProjects, deleteProject, getAudio, saveProject, getMeta } from './db.js';
import { decodeFile, newProject, persist, loadProject } from './project.js';
import { uid } from './util.js';

export function createLibraryView({ onOpen }) {
  const root = h('div', { class: 'view lib-view hidden' });
  const list = h('div', { class: 'lib-list' });
  const search = h('input', { class: 'txt search', type: 'search', placeholder: L('ابحث في التسجيلات…', 'Search recordings…') });
  const file = h('input', { type: 'file', accept: 'audio/*,video/*', class: 'hidden' });
  const usage = h('div', { class: 'hint center' });
  let items = [];

  search.addEventListener('input', render);
  file.addEventListener('change', async () => {
    const f = file.files[0];
    file.value = '';
    if (!f) return;
    const b = busy(L('جارٍ استيراد الملف…', 'Importing file…'));
    try {
      const { chs, sr } = await decodeFile(f);
      const p = newProject(chs, sr, f.name.replace(/\.[^.]+$/, ''));
      await persist(p);
      b.close();
      onOpen(p.id, p);
    } catch (e) {
      b.close();
      toast(L('تعذّر فتح هذا الملف', 'Could not open this file'));
    }
  });

  root.append(
    h('header', { class: 'top' }, h('h1', {}, L('المكتبة', 'Library')), h('div', { class: 'top-r' }, iconBtn('upload', () => file.click(), '', L('استيراد', 'Import')))),
    h('div', { class: 'search-wrap' }, icon('search', 18), search),
    list, usage, file,
  );

  function thumb(t) {
    const c = h('canvas', { class: 'thumb', width: 180, height: 56 });
    const x = c.getContext('2d');
    const bw = 180 / t.length;
    x.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#25f4ee';
    t.forEach((v, i) => { const hh = Math.max(2, v * 50); x.fillRect(i * bw, 28 - hh / 2, Math.max(1, bw - 1.2), hh); });
    return c;
  }

  async function render() {
    const q = search.value.trim().toLowerCase();
    list.innerHTML = '';
    const vis = items.filter((m) => !q || m.name.toLowerCase().includes(q));
    if (!vis.length) {
      list.append(h('div', { class: 'empty' }, icon('mic', 44), h('p', {}, items.length ? L('لا نتائج', 'No results') : L('لا توجد تسجيلات بعد. ابدأ أول تسجيل لك!', 'No recordings yet. Make your first one!'))));
      return;
    }
    vis.forEach((m) => {
      const card = h('div', { class: 'card', onclick: () => onOpen(m.id) },
        thumb(m.thumb || []),
        h('div', { class: 'card-m' },
          h('div', { class: 'card-n' }, m.name),
          h('div', { class: 'card-s' }, fmtDur(m.duration) + ' • ' + new Date(m.updated).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) + ' • ' + (m.ch > 1 ? L('ستريو', 'Stereo') : L('مونو', 'Mono')))),
        iconBtn('more', (e) => { e.stopPropagation(); menu(m); }, 'plain', L('المزيد', 'More')),
      );
      list.append(card);
    });
  }

  async function menu(m) {
    const v = await actionSheet(m.name, [
      { v: 'open', icon: 'edit', label: L('فتح وتحرير', 'Open & edit') },
      { v: 'wav', icon: 'download', label: L('تصدير WAV (الأصل)', 'Export WAV (original)') },
      { v: 'rename', icon: 'edit', label: L('إعادة تسمية', 'Rename') },
      { v: 'dup', icon: 'dup', label: L('نسخة مكررة', 'Duplicate') },
      { v: 'del', icon: 'trash', label: L('حذف', 'Delete'), danger: true },
    ]);
    if (v === 'open') onOpen(m.id);
    else if (v === 'rename') {
      const n = await promptBox(L('اسم التسجيل', 'Recording name'), m.name);
      if (n) { const meta = await getMeta(m.id); meta.name = n; await saveProject(meta); refresh(); }
    } else if (v === 'dup') {
      const meta = await getMeta(m.id), wav = await getAudio(m.id);
      await saveProject({ ...meta, id: uid(), name: meta.name + L(' (نسخة)', ' (copy)'), updated: Date.now() }, wav);
      refresh();
    } else if (v === 'del') {
      if (await confirmBox(L('حذف "' + m.name + '" نهائيًا؟', 'Delete "' + m.name + '" permanently?'), L('حذف', 'Delete'), true)) { await deleteProject(m.id); refresh(); }
    } else if (v === 'wav') {
      const wav = await getAudio(m.id);
      const a = h('a', { href: URL.createObjectURL(wav), download: m.name + '.wav' });
      document.body.append(a); a.click(); a.remove();
    }
  }

  async function refresh() {
    items = await listProjects();
    render();
    try {
      const e = await navigator.storage.estimate();
      usage.textContent = L('المساحة المستخدمة: ', 'Storage used: ') + fmtBytes(e.usage || 0);
    } catch (e) {}
  }

  return { el: root, refresh, show() { root.classList.remove('hidden'); refresh(); }, hide() { root.classList.add('hidden'); } };
}
