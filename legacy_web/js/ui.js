import { h, L, clamp, sleep } from './util.js';
import { ic } from './icons.js';

export const icon = (name, size) => h('span', { class: 'ic', html: ic(name, size) });

export function btn(label, iconName, onclick, cls = '') {
  return h('button', { class: 'btn ' + cls, onclick, type: 'button' }, iconName ? icon(iconName, 18) : null, label ? h('span', {}, label) : null);
}

export function iconBtn(iconName, onclick, cls = '', title = '') {
  return h('button', { class: 'ibtn ' + cls, onclick, type: 'button', title, 'aria-label': title }, icon(iconName, 22));
}

export function slider({ label, min, max, step = 1, value, def, fmt = (v) => v, onInput, onChange }) {
  const val = h('span', { class: 'sl-val' }, fmt(value));
  const inp = h('input', { type: 'range', min, max, step, value });
  const paint = () => inp.style.setProperty('--p', ((inp.value - min) / (max - min)) * 100 + '%');
  paint();
  inp.addEventListener('input', () => { val.textContent = fmt(+inp.value); paint(); onInput && onInput(+inp.value); });
  inp.addEventListener('change', () => onChange && onChange(+inp.value));
  if (def != null) {
    inp.addEventListener('dblclick', () => { inp.value = def; inp.dispatchEvent(new Event('input')); inp.dispatchEvent(new Event('change')); });
  }
  const root = h('div', { class: 'sl' }, h('div', { class: 'sl-top' }, h('span', {}, label), val), inp);
  root.set = (v) => { inp.value = v; val.textContent = fmt(v); paint(); };
  return root;
}

export function toggle(label, value, onChange, hint) {
  const input = h('input', { type: 'checkbox', checked: !!value });
  input.addEventListener('change', () => onChange(input.checked));
  const root = h('label', { class: 'tg' }, h('span', { class: 'tg-l' }, h('span', {}, label), hint ? h('small', {}, hint) : null), input, h('span', { class: 'tg-sw' }));
  root.set = (v) => { input.checked = v; };
  return root;
}

export function chips(options, value, onChange, cls = '') {
  const root = h('div', { class: 'chips ' + cls });
  const render = (cur) => {
    root.innerHTML = '';
    options.forEach((o) => {
      root.append(h('button', {
        type: 'button', class: 'chip' + (o.v === cur ? ' on' : ''),
        onclick: () => { render(o.v); onChange(o.v); },
      }, o.icon ? icon(o.icon, 16) : null, o.label));
    });
  };
  render(value);
  root.set = render;
  return root;
}

export const section = (title, ...kids) => h('div', { class: 'sec' }, title ? h('div', { class: 'sec-t' }, title) : null, ...kids);
export const row = (...kids) => h('div', { class: 'row' }, ...kids);

let toastTimer;
export function toast(msg, ms = 2400) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), ms);
}

function modal(build) {
  return new Promise((resolve) => {
    const root = document.getElementById('modal-root');
    const close = (v) => { back.classList.remove('show'); setTimeout(() => back.remove(), 200); resolve(v); };
    const box = build(close);
    const back = h('div', { class: 'modal-back', onclick: (e) => { if (e.target === back) close(null); } }, box);
    root.append(back);
    requestAnimationFrame(() => back.classList.add('show'));
  });
}

export function confirmBox(msg, okLabel = L('تأكيد', 'Confirm'), danger = false) {
  return modal((close) => h('div', { class: 'modal' },
    h('p', {}, msg),
    h('div', { class: 'modal-act' },
      btn(L('إلغاء', 'Cancel'), null, () => close(false), 'ghost'),
      btn(okLabel, null, () => close(true), danger ? 'danger' : 'primary'))));
}

export function promptBox(title, value = '') {
  return modal((close) => {
    const inp = h('input', { class: 'txt', type: 'text', value });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') close(inp.value.trim()); });
    setTimeout(() => { inp.focus(); inp.select(); }, 60);
    return h('div', { class: 'modal' }, h('h3', {}, title), inp,
      h('div', { class: 'modal-act' },
        btn(L('إلغاء', 'Cancel'), null, () => close(null), 'ghost'),
        btn(L('حفظ', 'Save'), null, () => close(inp.value.trim()), 'primary')));
  });
}

export function actionSheet(title, actions) {
  return modal((close) => h('div', { class: 'modal actions' },
    title ? h('h3', {}, title) : null,
    actions.map((a) => h('button', { class: 'act' + (a.danger ? ' danger' : ''), type: 'button', onclick: () => close(a.v) }, icon(a.icon, 20), a.label)),
    btn(L('إلغاء', 'Cancel'), null, () => close(null), 'ghost block')));
}

/** Blocking progress overlay. */
export function busy(msg, { cancel } = {}) {
  const bar = h('div', { class: 'bar' }, h('i'));
  const label = h('p', {}, msg);
  const box = h('div', { class: 'modal busy' }, h('div', { class: 'spin' }), label, bar,
    cancel ? btn(L('إلغاء', 'Cancel'), null, () => cancel(), 'ghost') : null);
  const back = h('div', { class: 'modal-back show' }, box);
  document.getElementById('modal-root').append(back);
  return {
    set(p, text) { bar.firstChild.style.width = clamp(p, 0, 1) * 100 + '%'; if (text) label.textContent = text; },
    close() { back.classList.remove('show'); setTimeout(() => back.remove(), 200); },
  };
}

/** Vertical drag slider (used by the EQ). */
export function vslider({ min, max, value, onInput, onChange }) {
  const fill = h('i', { class: 'vfill' }), knob = h('b', { class: 'vknob' });
  const root = h('div', { class: 'vs', tabindex: 0 }, h('span', { class: 'vzero' }), fill, knob);
  let v = value;
  const paint = () => {
    const p = (v - min) / (max - min);
    knob.style.bottom = `calc(${p * 100}% - 9px)`;
    const z = (0 - min) / (max - min);
    fill.style.bottom = Math.min(p, z) * 100 + '%';
    fill.style.height = Math.abs(p - z) * 100 + '%';
  };
  const fromEvent = (e) => {
    const r = root.getBoundingClientRect();
    v = Math.round((min + (1 - clamp((e.clientY - r.top) / r.height, 0, 1)) * (max - min)) * 2) / 2;
    paint(); onInput && onInput(v);
  };
  root.addEventListener('pointerdown', (e) => { root.setPointerCapture(e.pointerId); fromEvent(e); root._d = true; });
  root.addEventListener('pointermove', (e) => { if (root._d) fromEvent(e); });
  const end = () => { if (root._d) { root._d = false; onChange && onChange(v); } };
  root.addEventListener('pointerup', end);
  root.addEventListener('pointercancel', end);
  root.addEventListener('dblclick', () => { v = 0; paint(); onInput && onInput(0); onChange && onChange(0); });
  root.set = (nv) => { v = nv; paint(); };
  paint();
  return root;
}

export { sleep };
