import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dsp/loudness.dart';
import '../dsp/wav.dart';
import '../l10n.dart';
import '../models/fx.dart';
import '../models/presets.dart';
import '../services/editor_controller.dart';
import 'theme.dart';
import 'widgets.dart';

String _db(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} dB';
String _hz(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k Hz' : '${v.round()} Hz';

/// Helper: slider bound to a field of [FxSettings].
Widget fxSlider(EditorController c, String label, double value, double min, double max, void Function(double) set,
    {String Function(double)? fmt, double? def, bool clean = false, double? step}) {
  return FxSlider(
    label: label, value: value, min: min, max: max, def: def, fmt: fmt, divisions: step == null ? null : ((max - min) / step).round(),
    onChanged: (v) { set(v); c.fxChanged(clean: clean); },
  );
}

Widget fxSwitch(EditorController c, String label, bool value, void Function(bool) set, {String? hint, bool clean = false}) =>
    FxSwitch(label, value, (v) { set(v); c.fxChanged(clean: clean); }, hint: hint);

// ------------------------------------------------------------------ presets
class PresetsPanel extends StatelessWidget {
  const PresetsPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GridView.count(
        crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final p in presetDefs)
            Material(
              color: C.surface2,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final f = FxSettings();
                  p.apply(f);
                  f.fadeIn = c.fx.fadeIn;
                  f.fadeOut = c.fx.fadeOut;
                  c.setFx(f);
                  showMsg(context, '${L('تم تطبيق: ', 'Applied: ')}${L(p.ar, p.en)}');
                },
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(p.icon, color: C.accent, size: 26),
                    const SizedBox(height: 8),
                    Text(L(p.ar, p.en), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PillButton(L('إعادة ضبط كل التأثيرات', 'Reset all effects'), () => c.setFx(FxSettings()), icon: Icons.undo, small: true),
        PillButton(L('دمج التأثيرات في الملف', 'Bake effects into file'), () async {
          if (await confirmDialog(context, L('سيتم دمج كل التأثيرات في الصوت نهائيًا (يمكنك التراجع).', 'All effects will be rendered into the audio (you can undo).'), ok: L('دمج', 'Bake'))) {
            await c.bake();
          }
        }, icon: Icons.merge_type, small: true),
      ]),
      Hint(L('القوالب نقطة بداية — عدّل أي أداة بعد ذلك. التأثيرات غير مدمّرة حتى تدمجها أو تصدّر.', 'Presets are a starting point — tweak any tool afterwards. Effects stay non-destructive until you bake or export.')),
    ]);
  }
}

// -------------------------------------------------------------------- clean
class CleanPanel extends StatelessWidget {
  const CleanPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    final fx = c.fx;
    final before = noiseFloorDb(c.base);
    final after = c.cleaned != null ? noiseFloorDb(c.cleaned!) : null;
    String q(double d) => d < -60 ? L('ممتاز', 'Excellent') : d < -48 ? L('جيد', 'Good') : d < -38 ? L('متوسط', 'Fair') : L('عالٍ', 'High');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoCard(children: [
        Text('${L('أرضية الضوضاء: ', 'Noise floor: ')}${before.toStringAsFixed(0)} dB (${q(before)})'),
        if (after != null) Text('${L('بعد التنقية: ', 'After cleaning: ')}${after.toStringAsFixed(0)} dB (${q(after)})', style: const TextStyle(color: C.ok)),
      ]),
      Section(L('إزالة الضوضاء الاحترافية', 'Pro noise reduction'), [
        fxSwitch(c, L('تفعيل إزالة الضوضاء الطيفية', 'Enable spectral noise reduction'), fx.dn, (v) => fx.dn = v, clean: true, hint: L('تحليل ذكي لبصمة الضوضاء ثم إزالتها', 'Learns the noise fingerprint, then removes it')),
        fxSlider(c, L('القوة', 'Strength'), fx.dnAmount, 0, 100, (v) => fx.dnAmount = v, def: 55, clean: true, fmt: (v) => '${v.round()}%'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillButton(L('التقاط بصمة من التحديد', 'Learn noise from selection'), c.learnProfile, icon: Icons.graphic_eq, small: true),
          if (c.hasProfile) PillButton(L('بصمة تلقائية', 'Auto profile'), c.clearProfile, icon: Icons.close, small: true),
        ]),
        Hint(c.hasProfile ? L('✓ تُستخدم الآن بصمة الضوضاء الملتقطة.', '✓ Using your captured noise profile.') : L('نصيحة: حدّد مقطعًا فيه ضوضاء فقط (سكوت) ثم "التقاط بصمة" لنتيجة أدق. وإلا تُكتشف الضوضاء تلقائيًا.', 'Tip: select a noise-only stretch and tap "Learn" for best results. Otherwise noise is detected automatically.')),
      ]),
      Section(L('بوابة الضوضاء (Gate)', 'Noise gate'), [
        fxSwitch(c, L('تفعيل البوابة', 'Enable gate'), fx.gate, (v) => fx.gate = v, clean: true, hint: L('تكتم الصوت في فترات الصمت', 'Silences the gaps between words')),
        fxSlider(c, L('العتبة', 'Threshold'), fx.gateDb, -70, -20, (v) => fx.gateDb = v, def: -45, clean: true, fmt: _db),
        fxSlider(c, L('مقدار الخفض', 'Reduction'), fx.gateRange, -60, -6, (v) => fx.gateRange = v, def: -30, clean: true, fmt: _db),
      ]),
      Section(L('فلاتر', 'Filters'), [
        fxSwitch(c, L('قص الترددات المنخفضة (هدير/نفخ)', 'Low-cut (rumble / plosives)'), fx.hpfOn, (v) => fx.hpfOn = v),
        fxSlider(c, L('تردد القص', 'Cutoff'), fx.hpfF, 30, 300, (v) => fx.hpfF = v, def: 80, fmt: _hz),
        fxSwitch(c, L('قص الترددات العالية (هسهسة)', 'High-cut (hiss)'), fx.lpfOn, (v) => fx.lpfOn = v),
        fxSlider(c, L('تردد القص', 'Cutoff'), fx.lpfF, 3000, 20000, (v) => fx.lpfF = v, def: 12000, fmt: _hz),
        fxSwitch(c, L('إزالة طنين الكهرباء (Hum)', 'Remove mains hum'), fx.humOn, (v) => fx.humOn = v, hint: L('مع التوافقيات', 'Including harmonics')),
        ChipRow<double>(options: const [(50.0, '50 Hz'), (60.0, '60 Hz')], value: fx.humF, onChanged: (v) { fx.humF = v; c.fxChanged(); }),
      ]),
    ]);
  }
}

// --------------------------------------------------------------------- edit
class EditPanel extends StatefulWidget {
  const EditPanel(this.c, {super.key});
  final EditorController c;
  @override
  State<EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends State<EditPanel> {
  double gainDb = 6, th = -45, minMs = 400, padMs = 120, insLen = 1;
  EditorController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(L('التحديد', 'Selection'), [
        TileGrid([
          TileButton(L('بداية هنا', 'Start here'), Icons.flag_outlined, () => c.setSel(c.center, c.hasSel && c.selB! > c.center ? c.selB : c.duration)),
          TileButton(L('نهاية هنا', 'End here'), Icons.flag, () => c.setSel(c.hasSel && c.selA! < c.center ? c.selA : 0, c.center)),
          TileButton(L('تحديد الكل', 'Select all'), Icons.select_all, () => c.setSel(0, c.duration)),
          TileButton(L('إلغاء التحديد', 'Clear'), Icons.close, () => c.setSel(null, null)),
        ]),
        Hint(L('اسحب الخط الزمني لتحريك المؤشر الأبيض ثم استخدم الأزرار، أو اسحب مقابض التحديد مباشرة.', 'Drag the timeline to move the white playhead, then use the buttons — or drag the selection handles.')),
      ]),
      Section(L('قص', 'Cut'), [
        TileGrid([
          TileButton(L('حذف التحديد', 'Delete selection'), Icons.delete_outline, c.cutSel, danger: true),
          TileButton(L('إبقاء التحديد فقط', 'Keep selection'), Icons.content_cut, c.keepSel),
          TileButton(L('حذف ما قبل المؤشر', 'Cut before playhead'), Icons.skip_previous, c.cutBeforePlayhead),
          TileButton(L('حذف ما بعد المؤشر', 'Cut after playhead'), Icons.skip_next, c.cutAfterPlayhead),
        ]),
      ]),
      Section(L('تعديل التحديد', 'Modify selection'), [
        TileGrid([
          TileButton(L('كتم', 'Mute'), Icons.volume_off, c.muteSel),
          TileButton(L('عكس', 'Reverse'), Icons.swap_horiz, c.reverseSel),
          TileButton(L('تلاشي دخول', 'Fade in'), Icons.trending_up, () => c.fadeSel(fadeIn: true)),
          TileButton(L('تلاشي خروج', 'Fade out'), Icons.trending_down, () => c.fadeSel(fadeIn: false)),
        ]),
        FxSlider(label: L('مستوى التحديد', 'Selection gain'), value: gainDb, min: -24, max: 24, def: 6, divisions: 48, fmt: _db, onChanged: (v) => setState(() => gainDb = v)),
        PillButton(L('تطبيق المستوى على التحديد', 'Apply gain to selection'), () => c.gainSel(gainDb), icon: Icons.volume_up, small: true),
      ]),
      Section(L('نسخ ولصق', 'Copy & paste'), [
        TileGrid([
          TileButton(L('نسخ', 'Copy'), Icons.copy, c.copySel),
          TileButton(L('لصق عند المؤشر', 'Paste at playhead'), Icons.paste, c.pasteAtPlayhead),
          TileButton(L('تكرار التحديد', 'Duplicate'), Icons.control_point_duplicate, c.duplicateSel),
        ]),
      ]),
      Section(L('الصمت', 'Silence'), [
        ChipRow<double>(options: [for (final v in [0.5, 1.0, 2.0, 5.0]) (v, '$v ${L('ث', 's')}')], value: insLen, onChanged: (v) => setState(() => insLen = v)),
        PillButton(L('إدراج صمت عند المؤشر', 'Insert silence at playhead'), () => c.insertSilenceAtPlayhead(insLen), icon: Icons.add, small: true),
        FxSlider(label: L('عتبة الصمت', 'Silence threshold'), value: th, min: -70, max: -20, def: -45, divisions: 50, fmt: _db, onChanged: (v) => setState(() => th = v)),
        FxSlider(label: L('أقل مدة للحذف', 'Min. length'), value: minMs, min: 150, max: 2000, def: 400, divisions: 37, fmt: (v) => '${v.round()} ms', onChanged: (v) => setState(() => minMs = v)),
        FxSlider(label: L('هامش يُبقى حول الكلام', 'Padding kept'), value: padMs, min: 0, max: 400, def: 120, divisions: 40, fmt: (v) => '${v.round()} ms', onChanged: (v) => setState(() => padMs = v)),
        PillButton(L('حذف فترات الصمت تلقائيًا', 'Auto-remove silences'), () {
          final r = c.removeSilences(th, minMs, padMs);
          showMsg(context, r > 0 ? '${L('تم حذف ', 'Removed ')}${r.toStringAsFixed(1)}${L(' ثانية من الصمت', ' s of silence')}' : L('لم يُعثر على صمت للحذف', 'No silence found'));
        }, icon: Icons.auto_awesome, primary: true, small: true),
      ]),
      Section(L('إضافة', 'Add'), [
        PillButton(L('إلحاق ملف WAV بالنهاية', 'Append a WAV file'), () async {
          final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['wav']);
          if (f == null) return;
          final bytes = await f.readAsBytes();
          final pcm = decodeWav(bytes);
          if (!context.mounted) return;
          if (pcm == null || pcm.sr != c.sr) {
            showMsg(context, L('الملف غير مدعوم أو بمعدل عينة مختلف', 'Unsupported file or different sample rate'));
            return;
          }
          c.appendAudio(pcm);
        }, icon: Icons.upload_file, small: true),
      ]),
    ]);
  }
}

// -------------------------------------------------------------------- level
class LevelPanel extends StatelessWidget {
  const LevelPanel(this.c, {super.key});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    final fx = c.fx, l = c.loudness;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoCard(children: [
        if (l == null)
          Text(L('جارٍ القياس…', 'Measuring…'))
        else ...[
          Text('${L('الجهارة: ', 'Loudness: ')}${l.lufs.isFinite ? '${l.lufs.toStringAsFixed(1)} LUFS' : '—'}'),
          Text('${L('الذروة: ', 'Peak: ')}${l.peakDb.toStringAsFixed(1)} dBFS', style: TextStyle(color: l.peakDb > -0.5 ? C.bad : C.text)),
        ],
      ]),
      Section(L('مستوى الصوت', 'Volume'), [fxSlider(c, L('تضخيم', 'Gain'), fx.gain, -24, 24, (v) => fx.gain = v, def: 0, step: 0.5, fmt: _db)]),
      Section(L('تسوية الجهارة (Normalize)', 'Loudness normalisation'), [
        fxSwitch(c, L('تفعيل تسوية الجهارة', 'Enable loudness target'), fx.normOn, (v) => fx.normOn = v, hint: L('يضبط الجهارة تلقائيًا + محدّد قمم', 'Auto-levels + true peak limiter')),
        ChipRow<double>(
          options: [(-23.0, L('إذاعة −23', 'Broadcast −23')), (-16.0, L('بودكاست −16', 'Podcast −16')), (-14.0, L('يوتيوب −14', 'Streaming −14')), (-12.0, L('عالٍ −12', 'Loud −12'))],
          value: fx.normTarget,
          onChanged: (v) { fx.normTarget = v; fx.normOn = true; c.fxChanged(); },
        ),
        fxSlider(c, L('سقف القمم', 'Peak ceiling'), fx.normCeil, -6, 0, (v) => fx.normCeil = v, def: -1, step: 0.1, fmt: (v) => '${v.toStringAsFixed(1)} dB'),
      ]),
      Section(L('تلاشي', 'Fades'), [
        fxSlider(c, L('تلاشي في البداية', 'Fade in'), fx.fadeIn, 0, 10, (v) => fx.fadeIn = v, def: 0, step: 0.1, fmt: (v) => '${v.toStringAsFixed(1)} ${L('ث', 's')}'),
        fxSlider(c, L('تلاشي في النهاية', 'Fade out'), fx.fadeOut, 0, 10, (v) => fx.fadeOut = v, def: 0, step: 0.1, fmt: (v) => '${v.toStringAsFixed(1)} ${L('ث', 's')}'),
      ]),
    ]);
  }
}
