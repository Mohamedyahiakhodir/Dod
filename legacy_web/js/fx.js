import { deepMerge } from './util.js';

export const EQ_BANDS = [
  { f: 60, type: 'lowshelf', q: 0.7 },
  { f: 150, type: 'peaking', q: 1.0 },
  { f: 400, type: 'peaking', q: 1.0 },
  { f: 1000, type: 'peaking', q: 1.0 },
  { f: 3000, type: 'peaking', q: 1.0 },
  { f: 6000, type: 'peaking', q: 1.0 },
  { f: 12000, type: 'highshelf', q: 0.7 },
];

export const defaultFx = () => ({
  gain: 0,
  clean: { dn: false, amount: 55, gate: false, gateDb: -45, gateRange: -30, ds: 0 },
  hpf: { on: false, f: 80 },
  lpf: { on: false, f: 12000 },
  hum: { on: false, f: 50 },
  eq: { on: false, bands: [0, 0, 0, 0, 0, 0, 0] },
  warm: { on: false, amount: 25 },
  comp: { on: false, th: -24, ratio: 3, attack: 10, release: 200, knee: 12, makeup: 3 },
  reverb: { on: false, type: 'room', mix: 25, decay: 1.2, pre: 15, damp: 50 },
  echo: { on: false, time: 320, fb: 35, mix: 25, tone: 5000 },
  chorus: { on: false, depth: 50, rate: 1.2, mix: 40 },
  ring: { on: false, f: 50 },
  norm: { on: false, target: -16, ceil: -1 },
  fadeIn: 0,
  fadeOut: 0,
});

export const mergeFx = (patch, base) => deepMerge(base || defaultFx(), patch);
export const cleanActive = (fx) => fx.clean.dn || fx.clean.gate || fx.clean.ds > 0;

export const EQ_PRESETS = [
  { id: 'flat', ar: 'مسطّح', en: 'Flat', g: [0, 0, 0, 0, 0, 0, 0] },
  { id: 'voice', ar: 'وضوح الصوت', en: 'Voice clarity', g: [-3, -1, -2, 1, 3, 2, 1] },
  { id: 'warm', ar: 'دافئ', en: 'Warm', g: [3, 3, 1, -1, -1, -2, -2] },
  { id: 'bright', ar: 'ساطع', en: 'Bright', g: [-2, -1, 0, 1, 2, 4, 5] },
  { id: 'bass', ar: 'تعزيز الجهير', en: 'Bass boost', g: [6, 4, 1, 0, 0, 0, 0] },
  { id: 'mud', ar: 'إزالة الاحتقان', en: 'De-mud', g: [-2, -2, -5, 0, 2, 1, 0] },
  { id: 'podcast', ar: 'بودكاست', en: 'Podcast', g: [-4, 1, -2, 1, 3, 1, 2] },
  { id: 'quran', ar: 'تلاوة', en: 'Recitation', g: [-2, 3, 2, 0, -1, 1, 2] },
  { id: 'phone', ar: 'هاتف', en: 'Telephone', g: [-12, -8, 0, 4, 2, -6, -12] },
];

export const REVERB_TYPES = {
  room: { ar: 'غرفة', en: 'Room', decay: 0.9, damp: 55, pre: 8, er: true },
  plate: { ar: 'استوديو (Plate)', en: 'Plate', decay: 1.8, damp: 25, pre: 0, er: false },
  hall: { ar: 'قاعة', en: 'Hall', decay: 2.8, damp: 40, pre: 20, er: true },
  mosque: { ar: 'مسجد / جامع', en: 'Mosque', decay: 4.2, damp: 35, pre: 30, er: true },
  cave: { ar: 'كهف', en: 'Cave', decay: 6, damp: 60, pre: 40, er: false },
};

export const PRESETS = [
  { id: 'natural', ar: 'طبيعي', en: 'Natural', icon: 'wave', patch: {} },
  {
    id: 'auto', ar: 'تحسين تلقائي', en: 'Auto enhance', icon: 'sparkle',
    patch: {
      clean: { dn: true, amount: 55, ds: 25 }, hpf: { on: true, f: 80 },
      eq: { on: true, bands: [-3, -1, -2, 1, 3, 1, 1] }, comp: { on: true, th: -22, ratio: 3, makeup: 3 },
      norm: { on: true, target: -16, ceil: -1 },
    },
  },
  {
    id: 'podcast', ar: 'بودكاست', en: 'Podcast', icon: 'mic2',
    patch: {
      clean: { dn: true, amount: 60, ds: 30, gate: true, gateDb: -48, gateRange: -25 }, hpf: { on: true, f: 90 },
      eq: { on: true, bands: [-4, 1, -2, 1, 3, 1, 2] }, comp: { on: true, th: -24, ratio: 4, makeup: 4 },
      norm: { on: true, target: -16, ceil: -1 },
    },
  },
  {
    id: 'vo', ar: 'تعليق صوتي', en: 'Voice-over', icon: 'speaker',
    patch: {
      clean: { dn: true, amount: 50, ds: 30 }, hpf: { on: true, f: 70 },
      eq: { on: true, bands: [-2, 2, -1, 0, 2, 1, 3] }, comp: { on: true, th: -22, ratio: 4, makeup: 4 },
      warm: { on: true, amount: 15 }, reverb: { on: true, type: 'room', mix: 8, decay: 0.7, pre: 6, damp: 60 },
      norm: { on: true, target: -18, ceil: -1 },
    },
  },
  {
    id: 'quran', ar: 'تلاوة قرآن', en: 'Recitation', icon: 'moon',
    patch: {
      clean: { dn: true, amount: 40, ds: 15 }, hpf: { on: true, f: 60 },
      eq: { on: true, bands: [-2, 3, 2, 0, -1, 1, 2] }, comp: { on: true, th: -20, ratio: 2, attack: 25, release: 300, makeup: 2 },
      warm: { on: true, amount: 15 }, reverb: { on: true, type: 'mosque', mix: 22, decay: 3.2, pre: 28, damp: 40 },
      norm: { on: true, target: -16, ceil: -1 },
    },
  },
  {
    id: 'mosque', ar: 'صدى المسجد', en: 'Mosque hall', icon: 'mosque',
    patch: { reverb: { on: true, type: 'mosque', mix: 38, decay: 4.5, pre: 35, damp: 35 }, hpf: { on: true, f: 70 } },
  },
  {
    id: 'adhan', ar: 'أذان', en: 'Adhan', icon: 'mosque',
    patch: {
      clean: { dn: true, amount: 40 }, hpf: { on: true, f: 70 }, eq: { on: true, bands: [-1, 2, 1, 0, 0, 1, 3] },
      reverb: { on: true, type: 'mosque', mix: 45, decay: 5, pre: 40, damp: 30 },
      echo: { on: true, time: 450, fb: 30, mix: 14, tone: 4000 }, norm: { on: true, target: -16, ceil: -1 },
    },
  },
  {
    id: 'radio', ar: 'إذاعة', en: 'Radio', icon: 'radio',
    patch: {
      clean: { dn: true, amount: 50, ds: 20 }, hpf: { on: true, f: 100 }, eq: { on: true, bands: [4, 2, -1, 0, 4, 1, 0] },
      comp: { on: true, th: -26, ratio: 5, makeup: 6 }, warm: { on: true, amount: 25 }, norm: { on: true, target: -14, ceil: -1 },
    },
  },
  {
    id: 'reels', ar: 'ريلز / تيك توك', en: 'Reels / Shorts', icon: 'video',
    patch: {
      clean: { dn: true, amount: 60, ds: 35 }, hpf: { on: true, f: 100 }, eq: { on: true, bands: [-3, 0, -2, 1, 4, 2, 3] },
      comp: { on: true, th: -26, ratio: 6, attack: 5, release: 150, makeup: 6 }, norm: { on: true, target: -13, ceil: -1 },
    },
  },
  {
    id: 'deep', ar: 'صوت عميق دافئ', en: 'Deep & warm', icon: 'fire',
    patch: {
      hpf: { on: true, f: 60 }, eq: { on: true, bands: [6, 4, 1, -1, -1, -2, -1] }, warm: { on: true, amount: 35 },
      comp: { on: true, th: -22, ratio: 3, makeup: 3 }, norm: { on: true, target: -16, ceil: -1 },
    },
  },
  {
    id: 'phone', ar: 'مكالمة هاتف', en: 'Telephone', icon: 'phone',
    patch: { hpf: { on: true, f: 400 }, lpf: { on: true, f: 3400 }, comp: { on: true, th: -28, ratio: 6, makeup: 6 }, warm: { on: true, amount: 40 } },
  },
  {
    id: 'mega', ar: 'ميجافون', en: 'Megaphone', icon: 'megaphone',
    patch: { hpf: { on: true, f: 500 }, lpf: { on: true, f: 4500 }, warm: { on: true, amount: 70 }, comp: { on: true, th: -30, ratio: 8, makeup: 8 } },
  },
  {
    id: 'robot', ar: 'روبوت', en: 'Robot', icon: 'robot',
    patch: { ring: { on: true, f: 55 }, echo: { on: true, time: 60, fb: 40, mix: 30, tone: 6000 } },
  },
  {
    id: 'cave', ar: 'كهف', en: 'Cave', icon: 'cave',
    patch: { reverb: { on: true, type: 'cave', mix: 55, decay: 6, pre: 40, damp: 60 }, echo: { on: true, time: 500, fb: 45, mix: 25, tone: 3500 } },
  },
];
