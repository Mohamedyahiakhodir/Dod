import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../dsp/pcm.dart';
import '../l10n.dart';
import '../models/project.dart';
import '../services/recorder_service.dart';
import 'theme.dart';
import 'widgets.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.rec, required this.active, required this.onFinish, required this.onRecordingChanged});
  final RecorderService rec;
  final bool active;
  final void Function(Pcm pcm, List<Marker> markers) onFinish;
  final ValueChanged<bool> onRecordingChanged;
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  RecorderService get rec => widget.rec;
  bool panelOpen = false;
  int countdown = 0;
  double peakHold = 0;
  DateTime peakAt = DateTime.now();
  List<InputDevice> devices = [];

  @override
  void initState() {
    super.initState();
    rec.addListener(_onRec);
    _boot();
  }

  Future<void> _boot() async {
    await rec.opts.load();
    if (mounted) setState(() {});
    if (widget.active) await rec.openMic();
    devices = await rec.devices();
    if (mounted) setState(() {});
  }

  void _onRec() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant RecordScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      rec.openMic();
    } else if (!widget.active && old.active) {
      rec.closeMic();
    }
  }

  @override
  void dispose() {
    rec.removeListener(_onRec);
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _start() async {
    if (!rec.micReady && !await rec.openMic()) return;
    if (rec.opts.countdown) {
      for (var i = 3; i > 0; i--) {
        if (!mounted) return;
        setState(() => countdown = i);
        await Future<void>.delayed(const Duration(milliseconds: 850));
      }
      if (mounted) setState(() => countdown = 0);
    }
    rec.bars.clear();
    rec.start();
    widget.onRecordingChanged(true);
    if (rec.opts.wake) WakelockPlus.enable().catchError((Object _) {});
    setState(() => panelOpen = true);
  }

  Future<void> _stop() async {
    final pcm = await rec.stop();
    final markers = List<Marker>.from(rec.markers);
    WakelockPlus.disable().catchError((Object _) {});
    widget.onRecordingChanged(false);
    setState(() => panelOpen = false);
    if (pcm != null && pcm.duration > 0.3) {
      widget.onFinish(pcm, markers);
    } else if (mounted) {
      showMsg(context, L('التسجيل قصير جدًا', 'Recording too short'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = rec.state != RecState.idle;
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(children: [
            Text(L('ستوديو الصوت', 'Voice Studio'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (!recording) _roomChip(),
            if (rec.clips > 0) _chip(L('تقطيع!', 'CLIP!'), C.bad),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _WavePainter(rec, repaint: rec.level))),
              if (countdown > 0)
                Positioned.fill(child: Container(color: const Color(0x8C000000), alignment: Alignment.center, child: Text('$countdown', style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w800)))),
              if (rec.error != null) Positioned.fill(child: _errorBox()),
            ]),
          ),
        ),
        _timer(recording),
        _meter(),
        _controls(recording),
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: panelOpen ? h * 0.44 : 0,
          decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24)), border: Border(top: BorderSide(color: C.line))),
          clipBehavior: Clip.antiAlias,
          child: panelOpen ? _panel(recording) : null,
        ),
      ]),
    );
  }

  Widget _chip(String s, Color col) => Container(
        margin: const EdgeInsetsDirectional.only(start: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(999)),
        child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: col)),
      );

  Widget _roomChip() {
    final f = rec.roomFloorDb;
    if (f == null) return const SizedBox.shrink();
    final txt = f < -60 ? L('هادئة جدًا', 'Very quiet') : f < -48 ? L('هادئة', 'Quiet') : f < -38 ? L('ضوضاء متوسطة', 'Some noise') : L('ضوضاء عالية', 'Noisy');
    return ValueListenableBuilder(valueListenable: rec.level, builder: (_, _, _) => _chip('${L('الغرفة: ', 'Room: ')}$txt', f < -48 ? C.ok : f < -38 ? C.warn : C.bad));
  }

  Widget _errorBox() => Container(
        color: C.surface,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mic_off, size: 40, color: C.muted),
          const SizedBox(height: 12),
          Text(
            rec.error == 'permission' ? L('لم يتم السماح باستخدام الميكروفون. فعّل الإذن من إعدادات الهاتف ثم أعد المحاولة.', 'Microphone access was blocked. Allow it in your phone settings and retry.') : '${L('تعذّر فتح الميكروفون: ', 'Could not open the microphone: ')}${rec.error}',
            textAlign: TextAlign.center, style: const TextStyle(color: C.muted),
          ),
          const SizedBox(height: 14),
          PillButton(L('إعادة المحاولة', 'Retry'), rec.openMic, primary: true),
        ]),
      );

  Widget _timer(bool recording) => ListenableBuilder(
        listenable: Listenable.merge([rec, rec.level]),
        builder: (_, _) => Column(children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(fmtTime(recording ? rec.seconds : 0, dec: 1), style: TextStyle(fontSize: 46, fontWeight: FontWeight.w300, color: recording ? C.rec : C.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              rec.state == RecState.idle ? (rec.micReady ? L('اضغط للتسجيل', 'Tap to record') : '') : '${rec.state == RecState.paused ? L('متوقف مؤقتًا', 'Paused') : L('جارٍ التسجيل…', 'Recording…')} • ${fmtBytes(rec.bytes)}',
              style: const TextStyle(color: C.muted, fontSize: 13),
            ),
          ),
        ]),
      );

  Widget _meter() => ValueListenableBuilder<LevelInfo>(
        valueListenable: rec.level,
        builder: (_, l, _) {
          final db = 20 * math.log(math.max(l.peak, 1e-5)) / math.ln10, pct = ((db + 60) / 60).clamp(0.0, 1.0);
          final now = DateTime.now();
          if (pct >= peakHold || now.difference(peakAt).inMilliseconds > 1200) {
            peakHold = pct;
            peakAt = now;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 8,
                    child: LayoutBuilder(builder: (_, b) => Stack(children: [
                      Container(decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(6))),
                      Container(width: b.maxWidth * pct, decoration: BoxDecoration(color: db > -3 ? C.bad : db > -12 ? C.warn : C.accent, borderRadius: BorderRadius.circular(6))),
                      Positioned(left: b.maxWidth * peakHold - 1, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white70)),
                    ])),
                  ),
                ),
                SizedBox(width: 58, child: Text(l.peak > 1e-4 ? '${db.round()} dB' : '-∞', textAlign: TextAlign.right, style: const TextStyle(color: C.muted, fontSize: 12))),
              ]),
            ),
          );
        },
      );

  Widget _controls(bool recording) {
    final paused = rec.state == RecState.paused;
    Widget round(IconData i, VoidCallback? f, {bool on = false}) => Material(
          color: on ? C.accent : C.surface2, shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: f, child: SizedBox(width: 52, height: 52, child: Icon(i, color: on ? C.accentInk : Colors.white))),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        round(Icons.tune, () => setState(() => panelOpen = !panelOpen), on: panelOpen),
        const SizedBox(width: 14),
        SizedBox(width: 52, child: recording ? round(Icons.flag_outlined, () { rec.addMarker('${L('علامة', 'Marker')} ${rec.markers.length + 1}'); showMsg(context, '${L('تمت إضافة علامة عند ', 'Marker added at ')}${fmtTime(rec.seconds, dec: 1)}'); }) : null),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: recording ? _stop : _start,
          child: Container(
            width: 84, height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: recording ? 32 : 62, height: recording ? 32 : 62,
              decoration: BoxDecoration(color: C.rec, borderRadius: BorderRadius.circular(recording ? 9 : 40)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(width: 52, child: recording ? round(paused ? Icons.play_arrow : Icons.pause, () => paused ? rec.resume() : rec.pause()) : null),
        const SizedBox(width: 14),
        const SizedBox(width: 52),
      ]),
    );
  }

  Widget _panel(bool recording) {
    final o = rec.opts;
    void save() { o.save(); setState(() {}); }
    Future<void> reapply() async {
      o.save();
      if (!recording) {
        await rec.openMic();
      } else if (mounted) {
        showMsg(context, L('سيُطبَّق في التسجيل القادم', 'Applies to the next recording'));
      }
    }

    return Column(children: [
      GestureDetector(
        onTap: () => setState(() => panelOpen = false),
        behavior: HitTestBehavior.opaque,
        child: Padding(padding: const EdgeInsets.all(10), child: Container(width: 44, height: 5, decoration: BoxDecoration(color: C.surface3, borderRadius: BorderRadius.circular(3)))),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Section(L('معالجة الميكروفون', 'Microphone processing'), [
            FxSwitch(L('إلغاء الضوضاء (حي)', 'Noise suppression (live)'), o.noiseSuppress, (v) { o.noiseSuppress = v; reapply(); }, hint: L('يقلل ضوضاء الخلفية أثناء التسجيل', 'Reduces background noise while recording')),
            FxSwitch(L('إلغاء الصدى', 'Echo cancellation'), o.echoCancel, (v) { o.echoCancel = v; reapply(); }, hint: L('مفيد عند استخدام السماعة', 'Useful with speakers')),
            FxSwitch(L('ضبط تلقائي للمستوى (AGC)', 'Auto gain (AGC)'), o.autoGain, (v) { o.autoGain = v; reapply(); }, hint: L('أطفئه للحصول على تسجيل نقي', 'Turn off for pure recordings')),
          ]),
          Section(L('المستوى', 'Level'), [
            FxSlider(label: L('تضخيم الدخل', 'Input gain'), value: o.gainDb, min: -12, max: 30, def: 0, divisions: 42, fmt: (v) => '${v > 0 ? '+' : ''}${v.round()} dB', onChanged: (v) => setState(() => o.gainDb = v), onEnd: (_) => o.save()),
          ]),
          Section(L('الإدخال', 'Input'), [
            if (devices.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DropdownButtonFormField<String?>(
                  initialValue: devices.any((d) => d.id == o.deviceId) ? o.deviceId : null,
                  isExpanded: true,
                  dropdownColor: C.surface2,
                  items: [DropdownMenuItem<String?>(value: null, child: Text(L('الميكروفون الافتراضي', 'Default microphone'))), for (final d in devices) DropdownMenuItem<String?>(value: d.id, child: Text(d.label, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) { o.deviceId = v; reapply(); },
                ),
              ),
            FxSwitch(L('ستريو', 'Stereo'), o.stereo, (v) { o.stereo = v; reapply(); }, hint: L('يتطلب ميكروفون ستريو', 'Needs a stereo mic')),
            FxSwitch(L('عدّ تنازلي قبل البدء (3 ثوانٍ)', 'Countdown before start (3s)'), o.countdown, (v) { o.countdown = v; save(); }),
            FxSwitch(L('إبقاء الشاشة مضاءة', 'Keep screen awake'), o.wake, (v) { o.wake = v; save(); }),
          ]),
          Hint(L('نصيحة: سجّل بصوت خام (بدون AGC) وسيتولى المحرر التنقية والإيكو والضغط بشكل غير مدمّر.', 'Tip: record raw (no AGC) — the editor handles cleanup, EQ and compression non-destructively.')),
        ]),
      ),
    ]);
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.rec, {required Listenable repaint}) : super(repaint: repaint);
  final RecorderService rec;

  @override
  void paint(Canvas canvas, Size s) {
    const bw = 4.0, gap = 2.0;
    final cnt = (s.width / (bw + gap)).floor(), mid = s.height / 2;
    final recording = rec.state != RecState.idle;
    canvas.drawLine(Offset(0, mid), Offset(s.width, mid), Paint()..color = const Color(0x14FFFFFF));
    final bars = rec.bars;
    // each drawn bar groups 4 x 10 ms slices
    const group = 4;
    final total = bars.length ~/ group;
    final take = math.min(cnt, total);
    final p = Paint();
    for (var i = 0; i < take; i++) {
      final gi = total - take + i;
      var m = 0.0;
      for (var k = 0; k < group; k++) {
        m = math.max(m, bars[gi * group + k]);
      }
      final x = s.width - (take - i) * (bw + gap), v = math.pow(m.clamp(0.0, 1.0), 0.6).toDouble();
      final hh = math.max(2.0, v * s.height * 0.46);
      p.color = (m > 0.97 ? C.bad : (recording ? C.rec : C.accent)).withValues(alpha: recording ? 1 : 0.55);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - hh, bw, hh * 2), const Radius.circular(2)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
