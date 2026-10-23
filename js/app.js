import { h, L, lang, storage } from './util.js';
import { icon, iconBtn, toast, actionSheet, toggle, chips, confirmBox } from './ui.js';
import { createRecordView } from './record-view.js';
import { createLibraryView } from './library-view.js';
import { createEditor } from './editor.js';
import { newProject, persist, loadProject } from './project.js';
import { busy } from './ui.js';

lang.v = storage.get('dod.lang', 'ar');

let tab = 'record', deferredInstall = null;
const app = document.getElementById('app');

function applyLang() {
  document.documentElement.lang = lang.v;
  document.documentElement.dir = lang.v === 'ar' ? 'rtl' : 'ltr';
}

let recView, libView, editor, nav;

function build() {
  applyLang();
  app.innerHTML = '';
  const wasRecording = recView && recView.isRecording();
  recView = createRecordView({
    setNavHidden: (v) => { nav && nav.classList.toggle('hidden', v); document.body.classList.toggle('recording-active', v); },
    onFinish: async (r) => {
      const p = newProject(r.chs, r.sr);
      p.markers = r.markers.map((m, i) => ({ t: m.t, name: m.name || L('علامة ', 'Marker ') + (i + 1) }));
      const b = busy(L('جارٍ الحفظ…', 'Saving…'));
      try { await persist(p); } catch (e) { toast(L('تعذّر الحفظ', 'Could not save')); }
      b.close();
      recView.hide();
      openEditor(p);
    },
  });
  libView = createLibraryView({
    onOpen: async (id, loaded) => {
      if (loaded) return openEditor(loaded);
      const b = busy(L('جارٍ فتح التسجيل…', 'Opening…'));
      try { openEditor(await loadProject(id)); } catch (e) { toast(L('تعذّر فتح التسجيل', 'Could not open recording')); }
      b.close();
    },
  });
  editor = createEditor({ onClose: () => { go(tab); } });
  nav = h('nav', { class: 'nav' },
    h('button', { class: 'nav-i', 'data-t': 'library', onclick: () => go('library') }, icon('list', 24), h('span', {}, L('المكتبة', 'Library'))),
    h('button', { class: 'nav-i nav-rec', 'data-t': 'record', onclick: () => go('record') }, icon('mic', 26), h('span', {}, L('تسجيل', 'Record'))),
    h('button', { class: 'nav-i', 'data-t': 'settings', onclick: openSettings }, icon('gear', 24), h('span', {}, L('الإعدادات', 'Settings'))),
  );
  app.append(recView.el, libView.el, editor.el, nav);
  go(tab);
}

function go(t) {
  tab = t === 'settings' ? tab : t;
  recView.el.classList.toggle('hidden', tab !== 'record');
  libView.el.classList.toggle('hidden', tab !== 'library');
  if (tab === 'record') recView.show(); else recView.hide();
  if (tab === 'library') libView.show();
  nav.querySelectorAll('.nav-i').forEach((b) => b.classList.toggle('on', b.dataset.t === tab));
}

function openEditor(p) {
  recView.hide();
  editor.open(p);
}

async function openSettings() {
  const v = await actionSheet(L('الإعدادات', 'Settings'), [
    { v: 'lang', icon: 'note', label: lang.v === 'ar' ? 'English' : 'العربية' },
    ...(deferredInstall ? [{ v: 'install', icon: 'download', label: L('تثبيت التطبيق على الهاتف', 'Install app on device') }] : []),
    { v: 'about', icon: 'info', label: L('حول التطبيق', 'About') },
  ]);
  if (v === 'lang') {
    lang.v = lang.v === 'ar' ? 'en' : 'ar';
    storage.set('dod.lang', lang.v); storage.set('dod.langSet', true);
    if (recView.isRecording() || editor.isOpen) { toast(L('سيُطبَّق التغيير عند إعادة التشغيل', 'Applies after reload')); return; }
    build();
  } else if (v === 'install') {
    deferredInstall.prompt();
    deferredInstall = null;
  } else if (v === 'about') {
    await confirmBox(L('ستوديو الصوت — تسجيل وتنقية وتحرير ومعالجة احترافية للصوت مباشرة على هاتفك. كل المعالجة تتم محليًا على جهازك ولا يتم رفع أي صوت.', 'Voice Studio — pro recording, cleanup, editing and mastering right on your phone. All processing is local; no audio is uploaded.'), 'OK');
  }
}

window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredInstall = e; });

build();

if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
window.__dod = { go, openEditor, get editor() { return editor; }, get rec() { return recView; } };
