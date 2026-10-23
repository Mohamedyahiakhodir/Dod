import 'package:flutter/material.dart';

import 'fx.dart';

class PresetDef {
  const PresetDef(this.id, this.ar, this.en, this.icon, this.apply);
  final String id, ar, en;
  final IconData icon;
  final void Function(FxSettings f) apply;
}

void _verb(FxSettings f, String type, double mix, double decay, double pre, double damp) {
  f.revOn = true; f.revType = type; f.revMix = mix; f.revDecay = decay; f.revPre = pre; f.revDamp = damp;
}

void _comp(FxSettings f, double th, double ratio, double makeup, {double attack = 10, double release = 200}) {
  f.compOn = true; f.th = th; f.ratio = ratio; f.makeup = makeup; f.attack = attack; f.release = release;
}

void _norm(FxSettings f, double target) {
  f.normOn = true; f.normTarget = target; f.normCeil = -1;
}

void _eq(FxSettings f, List<double> g) {
  f.eqOn = true; f.eq = List<double>.from(g);
}

final presetDefs = <PresetDef>[
  PresetDef('natural', 'طبيعي', 'Natural', Icons.graphic_eq, (f) {}),
  PresetDef('auto', 'تحسين تلقائي', 'Auto enhance', Icons.auto_awesome, (f) {
    f.dn = true; f.dnAmount = 55; f.deess = 25; f.hpfOn = true; f.hpfF = 80;
    _eq(f, [-3, -1, -2, 1, 3, 1, 1]); _comp(f, -22, 3, 3); _norm(f, -16);
  }),
  PresetDef('podcast', 'بودكاست', 'Podcast', Icons.mic, (f) {
    f.dn = true; f.dnAmount = 60; f.deess = 30; f.gate = true; f.gateDb = -48; f.gateRange = -25;
    f.hpfOn = true; f.hpfF = 90; _eq(f, [-4, 1, -2, 1, 3, 1, 2]); _comp(f, -24, 4, 4); _norm(f, -16);
  }),
  PresetDef('vo', 'تعليق صوتي', 'Voice-over', Icons.record_voice_over, (f) {
    f.dn = true; f.dnAmount = 50; f.deess = 30; f.hpfOn = true; f.hpfF = 70;
    _eq(f, [-2, 2, -1, 0, 2, 1, 3]); _comp(f, -22, 4, 4); f.warmOn = true; f.warm = 15;
    _verb(f, 'room', 8, 0.7, 6, 60); _norm(f, -18);
  }),
  PresetDef('quran', 'تلاوة قرآن', 'Recitation', Icons.nights_stay, (f) {
    f.dn = true; f.dnAmount = 40; f.deess = 15; f.hpfOn = true; f.hpfF = 60;
    _eq(f, [-2, 3, 2, 0, -1, 1, 2]); _comp(f, -20, 2, 2, attack: 25, release: 300);
    f.warmOn = true; f.warm = 15; _verb(f, 'mosque', 22, 3.2, 28, 40); _norm(f, -16);
  }),
  PresetDef('mosque', 'صدى المسجد', 'Mosque hall', Icons.mosque, (f) {
    _verb(f, 'mosque', 38, 4.5, 35, 35); f.hpfOn = true; f.hpfF = 70;
  }),
  PresetDef('adhan', 'أذان', 'Adhan', Icons.mosque_outlined, (f) {
    f.dn = true; f.dnAmount = 40; f.hpfOn = true; f.hpfF = 70; _eq(f, [-1, 2, 1, 0, 0, 1, 3]);
    _verb(f, 'mosque', 45, 5, 40, 30);
    f.echoOn = true; f.echoTime = 450; f.echoFb = 30; f.echoMix = 14; f.echoTone = 4000; _norm(f, -16);
  }),
  PresetDef('radio', 'إذاعة', 'Radio', Icons.radio, (f) {
    f.dn = true; f.dnAmount = 50; f.deess = 20; f.hpfOn = true; f.hpfF = 100;
    _eq(f, [4, 2, -1, 0, 4, 1, 0]); _comp(f, -26, 5, 6); f.warmOn = true; f.warm = 25; _norm(f, -14);
  }),
  PresetDef('reels', 'ريلز / تيك توك', 'Reels / Shorts', Icons.smart_display, (f) {
    f.dn = true; f.dnAmount = 60; f.deess = 35; f.hpfOn = true; f.hpfF = 100;
    _eq(f, [-3, 0, -2, 1, 4, 2, 3]); _comp(f, -26, 6, 6, attack: 5, release: 150); _norm(f, -13);
  }),
  PresetDef('deep', 'صوت عميق دافئ', 'Deep & warm', Icons.local_fire_department, (f) {
    f.hpfOn = true; f.hpfF = 60; _eq(f, [6, 4, 1, -1, -1, -2, -1]); f.warmOn = true; f.warm = 35;
    _comp(f, -22, 3, 3); _norm(f, -16);
  }),
  PresetDef('phone', 'مكالمة هاتف', 'Telephone', Icons.phone_in_talk, (f) {
    f.hpfOn = true; f.hpfF = 400; f.lpfOn = true; f.lpfF = 3400; _comp(f, -28, 6, 6); f.warmOn = true; f.warm = 40;
  }),
  PresetDef('mega', 'ميجافون', 'Megaphone', Icons.campaign, (f) {
    f.hpfOn = true; f.hpfF = 500; f.lpfOn = true; f.lpfF = 4500; f.warmOn = true; f.warm = 70; _comp(f, -30, 8, 8);
  }),
  PresetDef('robot', 'روبوت', 'Robot', Icons.smart_toy, (f) {
    f.ringOn = true; f.ringF = 55; f.echoOn = true; f.echoTime = 60; f.echoFb = 40; f.echoMix = 30; f.echoTone = 6000;
  }),
  PresetDef('cave', 'كهف', 'Cave', Icons.landscape, (f) {
    _verb(f, 'cave', 55, 6, 40, 60);
    f.echoOn = true; f.echoTime = 500; f.echoFb = 45; f.echoMix = 25; f.echoTone = 3500;
  }),
];
