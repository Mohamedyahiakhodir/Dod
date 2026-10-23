import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dsp/biquad.dart';
import '../l10n.dart';
import '../models/fx.dart';
import '../models/project.dart';
import '../services/editor_controller.dart';
import 'panels_a.dart';
import 'theme.dart';
import 'widgets.dart';

String _db(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} dB';
String _hz(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k Hz' : '${v.round()} Hz';

// ----------------------------------------------------------------- dynamics
class DynamicsPanel extends StatelessWidget {
  const DynamicsPanel(this.c, {super.key});
  final EditorController c;

  void _preset(double th, double ratio, double att, double rel, double knee, double mk) {
    final f = c.fx;
    f.compOn = true; f.th = th; f.ratio = ratio; f.attack = att; f.release = rel; f.knee = knee; f.makeup = mk;
    c.fxChanged();
  }

  @override
  Widget build(BuildContext context) {
    final fx = c.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(L('الضاغط (Compressor)', 'Compressor'), [
        fxSwitch(c, L('تفعيل الضاغط', 'Enable compressor'), fx.compOn, (v) => fx.compOn = v, hint: L('يوازن بين الصوت العالي والخافت', 'Evens out loud and quiet parts')),
        ChipRow<int>(
          options: [(0, L('خفيف', 'Gentle')), (1, L('صوت', 'Voice')), (2, L('إذاعي', 'Broadcast')), (3, L('قوي', 'Heavy'))],
          value: null,
          onChanged: (i) => [
            () => _preset(-20, 2, 25, 300, 20, 2), () => _preset(-24, 3.5, 10, 200, 12, 4),
            () => _preset(-28, 5, 5, 150, 8, 6), () => _preset(-34, 10, 3, 100, 4, 9),
          ][i](),
        ),
        fxSlider(c, L('العتبة', 'Threshold'), fx.th, -60, 0, (v) => fx.th = v, def: -24, fmt: _db),
        fxSlider(c, L('النسبة', 'Ratio'), fx.ratio, 1, 20, (v) => fx.ratio = v, def: 3, step: 0.5, fmt: (v) => '${v.toStringAsFixed(1)}:1'),
        fxSlider(c, L('الهجوم', 'Attack'), fx.attack, 1, 100, (v) => fx.attack = v, def: 10, fmt: (v) => '${v.round()} ms'),
        fxSlider(c, L('الإفلات', 'Release'), fx.release, 20, 1000, (v) => fx.release = v, def: 200, fmt: (v) => '${v.round()} ms'),
        fxSlider(c, L('تعويض المستوى', 'Make-up gain'), fx.makeup, 0, 24, (v) => fx.makeup = v, def: 3, step: 0.5, fmt: _db),
      ]),
      Section(L('إزالة حرف السين (De-esser)', 'De-esser'), [
        fxSlider(c, L('القوة', 'Amount'), fx.deess, 0, 100, (v) => fx.deess = v, def: 0, clean: true, fmt: (v) => v == 0 ? L('متوقف', 'Off') : '${v.round()}%'),
      ]),
      Section(L('دفء وتشبّع (Warmth)', 'Warmth / saturation'), [
        fxSwitch(c, L('تفعيل الدفء', 'Enable warmth'), fx.warmOn, (v) => fx.warmOn = v, hint: L('لمسة تشبّع أنبوبي ناعمة', 'Soft tube-style saturation')),
        fxSlider(c, L('المقدار', 'Amount'), fx.warm, 0, 100, (v) => fx.warm = v, def: 25, fmt: (v) => '${v.round()}%'),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------- eq
class EqPanel extends StatelessWidget {
  const EqPanel(this.c, {super.key});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    final fx = c.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FxSwitch(L('تفعيل الإيكوالايزر', 'Enable equalizer'), fx.eqOn, (v) { fx.eqOn = v; c.fxChanged(); }),
      Container(
        height: 96, margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
        child: CustomPaint(size: Size.infinite, painter: _EqCurve(List<double>.from(fx.eq), c.sr)),
      ),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(children: [
                Text(_db(fx.eq[i]), style: const TextStyle(fontSize: 10.5, color: C.accent)),
                SizedBox(
                  height: 140,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      value: fx.eq[i].clamp(-12.0, 12.0), min: -12, max: 12, divisions: 48,
                      onChanged: (v) { fx.eq[i] = v; fx.eqOn = true; c.fxChanged(); },
                    ),
                  ),
                ),
                Text(eqFreqs[i] >= 1000 ? '${(eqFreqs[i] / 1000).round()}k' : '${eqFreqs[i].round()}', style: const TextStyle(fontSize: 11, color: C.muted)),
              ]),
            ),
        ]),
      ),
      Section(L('إعدادات جاهزة', 'Presets'), [
        ChipRow<String>(
          scroll: true,
          options: [for (final p in eqPresets) (p.id, L(p.ar, p.en))],
          value: null,
          onChanged: (id) {
            final p = eqPresets.firstWhere((e) => e.id == id);
            fx.eq = List<double>.from(p.g);
            fx.eqOn = id != 'flat' || fx.eqOn;
            c.fxChanged();
          },
        ),
      ]),
    ]);
  }
}

class _EqCurve extends CustomPainter {
  _EqCurve(this.g, this.sr);
  final List<double> g;
  final int sr;
  @override
  void paint(Canvas canvas, Size s) {
    final grid = Paint()..color = const Color(0x1AFFFFFF);
    for (final d in [-12, -6, 0, 6, 12]) {
      final y = s.height / 2 - d / 15 * (s.height / 2 - 4);
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final filters = <Biquad>[
      for (var i = 0; i < 7; i++)
        if (g[i].abs() >= 0.05) Biquad(i == 0 ? BqType.lowshelf : i == 6 ? BqType.highshelf : BqType.peaking, eqFreqs[i], i == 0 || i == 6 ? 0.7 : 1.0, g[i], sr)
    ];
    final path = Path();
    for (var i = 0; i < 100; i++) {
      final f = 20 * math.pow(1000, i / 99);
      var d = 0.0;
      for (final b in filters) {
        d += b.responseDb(f.toDouble(), sr);
      }
      final x = i / 99 * s.width, y = s.height / 2 - d.clamp(-15.0, 15.0) / 15 * (s.height / 2 - 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)..lineTo(s.width, s.height / 2)..lineTo(0, s.height / 2)..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x1F25F4EE));
    canvas.drawPath(path, Paint()..color = C.accent..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _EqCurve o) => true;
}

// ------------------------------------------------------------------- reverb
class ReverbPanel extends StatelessWidget {
  const ReverbPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    final fx = c.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      fxSwitch(c, L('تفعيل الصدى', 'Enable reverb'), fx.revOn, (v) => fx.revOn = v),
      ChipRow<String>(
        scroll: true,
        options: [for (final e in reverbTypes.entries) (e.key, L(e.value.ar, e.value.en))],
        value: fx.revType,
        onChanged: (k) {
          final t = reverbTypes[k]!;
          fx.revType = k; fx.revDecay = t.decay; fx.revDamp = t.damp; fx.revPre = t.pre; fx.revOn = true;
          c.fxChanged();
        },
      ),
      fxSlider(c, L('كمية الصدى (Mix)', 'Wet mix'), fx.revMix, 0, 100, (v) => fx.revMix = v, def: 25, fmt: (v) => '${v.round()}%'),
      fxSlider(c, L('حجم المكان (مدة الصدى)', 'Size (decay)'), fx.revDecay, 0.3, 8, (v) => fx.revDecay = v, def: 1.2, step: 0.1, fmt: (v) => '${v.toStringAsFixed(1)} ${L('ث', 's')}'),
      fxSlider(c, L('امتصاص الترددات العالية', 'Damping'), fx.revDamp, 0, 100, (v) => fx.revDamp = v, def: 50, fmt: (v) => '${v.round()}%'),
      fxSlider(c, L('تأخير مسبق', 'Pre-delay'), fx.revPre, 0, 120, (v) => fx.revPre = v, def: 15, fmt: (v) => '${v.round()} ms'),
      Hint(L('"مسجد / جامع" مناسب للتلاوة والأذان والخطب.', '"Mosque" suits recitation, adhan and sermons.')),
    ]);
  }
}

// --------------------------------------------------------------------- echo
class EchoPanel extends StatelessWidget {
  const EchoPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    final fx = c.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(L('تكرار الصوت (Echo / Delay)', 'Echo / delay'), [
        fxSwitch(c, L('تفعيل', 'Enable'), fx.echoOn, (v) => fx.echoOn = v),
        ChipRow<double>(
          options: const [(120.0, '120ms'), (250.0, '250ms'), (400.0, '400ms'), (600.0, '600ms')],
          value: null,
          onChanged: (v) { fx.echoTime = v; fx.echoOn = true; c.fxChanged(); },
        ),
        fxSlider(c, L('زمن التأخير', 'Time'), fx.echoTime, 40, 1500, (v) => fx.echoTime = v, def: 320, fmt: (v) => '${v.round()} ms'),
        fxSlider(c, L('عدد التكرارات (Feedback)', 'Feedback'), fx.echoFb, 0, 90, (v) => fx.echoFb = v, def: 35, fmt: (v) => '${v.round()}%'),
        fxSlider(c, L('الكمية', 'Mix'), fx.echoMix, 0, 100, (v) => fx.echoMix = v, def: 25, fmt: (v) => '${v.round()}%'),
        fxSlider(c, L('نعومة التكرار', 'Tone'), fx.echoTone, 1000, 12000, (v) => fx.echoTone = v, def: 5000, fmt: _hz),
      ]),
      Section(L('كورَس / مضاعفة الصوت', 'Chorus / doubler'), [
        fxSwitch(c, L('تفعيل', 'Enable'), fx.chorusOn, (v) => fx.chorusOn = v, hint: L('يعطي اتساعًا وكثافة (ستريو)', 'Adds width and thickness (stereo)')),
        fxSlider(c, L('العمق', 'Depth'), fx.chDepth, 0, 100, (v) => fx.chDepth = v, def: 50, fmt: (v) => '${v.round()}%'),
        fxSlider(c, L('السرعة', 'Rate'), fx.chRate, 0.1, 6, (v) => fx.chRate = v, def: 1.2, step: 0.1, fmt: (v) => '${v.toStringAsFixed(1)} Hz'),
        fxSlider(c, L('الكمية', 'Mix'), fx.chMix, 0, 100, (v) => fx.chMix = v, def: 40, fmt: (v) => '${v.round()}%'),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------- voice
class VoicePanel extends StatefulWidget {
  const VoicePanel(this.c, {super.key});
  final EditorController c;
  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> {
  double semis = 0, tempo = 100;
  @override
  Widget build(BuildContext context) {
    final c = widget.c, fx = c.fx;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(L('تغيير النغمة والسرعة (دون تشويه)', 'Pitch & speed (high quality)'), [
        FxSlider(label: L('النغمة (Pitch)', 'Pitch'), value: semis, min: -12, max: 12, def: 0, divisions: 48, fmt: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} ${L('نصف نغمة', 'st')}', onChanged: (v) => setState(() => semis = v)),
        FxSlider(label: L('السرعة (دون تغيير النغمة)', 'Speed (keeps pitch)'), value: tempo, min: 50, max: 200, def: 100, divisions: 150, fmt: (v) => '${v.round()}%', onChanged: (v) => setState(() => tempo = v)),
        PillButton(L('تطبيق على الملف', 'Apply to audio'), () {
          if (semis == 0 && tempo == 100) {
            showMsg(context, L('غيّر النغمة أو السرعة أولاً', 'Change pitch or speed first'));
            return;
          }
          c.applyStretch(tempo / 100, semis);
          setState(() { semis = 0; tempo = 100; });
        }, icon: Icons.check, primary: true, small: true),
        Hint(L('مفيد لمراجعة التلاوة بسرعة أبطأ، أو لتسريع المحتوى. يمكن التراجع.', 'Great for slowing down recitation for review, or speeding up content. Undoable.')),
      ]),
      Section(L('تأثير صوت الروبوت', 'Robot voice'), [
        fxSwitch(c, L('تفعيل', 'Enable'), fx.ringOn, (v) => fx.ringOn = v),
        fxSlider(c, L('التردد', 'Frequency'), fx.ringF, 15, 400, (v) => fx.ringF = v, def: 50, fmt: _hz),
      ]),
      Hint(L('لتأثيرات مثل الهاتف والميجافون والكهف راجع "قوالب".', 'For telephone, megaphone and cave looks see "Presets".')),
    ]);
  }
}

// ----------------------------------------------------------------- markers
class MarkersPanel extends StatelessWidget {
  const MarkersPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    final ms = c.project.markers;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PillButton(L('إضافة علامة عند المؤشر', 'Add marker at playhead'), () => c.addMarker(), icon: Icons.add, primary: true, small: true),
      const SizedBox(height: 8),
      if (ms.isEmpty) Hint(L('لا توجد علامات. أضف علامة عند أي نقطة مهمة (بداية آية، خطأ يحتاج إعادة، فاصل…).', 'No markers yet. Drop one at any important point (a verse start, a retake, a chapter…).')),
      for (final m in List<Marker>.from(ms))
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => c.seek(m.t),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.flag, size: 16, color: Color(0xFFFFD60A)),
                    const SizedBox(width: 10),
                    Directionality(textDirection: TextDirection.ltr, child: Text(fmtTime(m.t, dec: 1), style: const TextStyle(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted))),
                  ]),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () async {
                final n = await promptDialog(context, L('اسم العلامة', 'Marker name'), m.name);
                if (n != null) { m.name = n; c.markersChanged(); }
              },
            ),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () { ms.remove(m); c.markersChanged(); }),
          ]),
        ),
    ]);
  }
}
