import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import '../services/editor_controller.dart';
import '../services/export_service.dart';
import '../services/mp3_stub.dart' if (dart.library.io) '../services/mp3_io.dart';
import 'theme.dart';
import 'widgets.dart';

class ExportPanel extends StatefulWidget {
  const ExportPanel(this.c, {super.key});
  final EditorController c;
  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  late final TextEditingController name = TextEditingController(text: widget.c.project.name);
  String fmt = 'wav';
  int bits = 16, kbps = 192;
  bool selOnly = false, busy = false;
  double progress = 0;
  String stage = '';
  Uint8List? out;
  String? outName, outMime, info;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        fmt = (p.getString('exp.fmt') == 'mp3' && mp3Supported) ? 'mp3' : 'wav';
        bits = p.getInt('exp.bits') ?? 16;
        kbps = p.getInt('exp.kbps') ?? 192;
      });
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final c = widget.c;
    if (selOnly && !c.hasSel) {
      showMsg(context, L('حدّد جزءًا أولاً', 'Select a part first'));
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('exp.fmt', fmt);
    await p.setInt('exp.bits', bits);
    await p.setInt('exp.kbps', kbps);
    setState(() { busy = true; progress = .1; stage = L('جارٍ المعالجة…', 'Rendering…'); out = null; });
    try {
      final r = await c.renderForExport(bits: bits, wantWav: fmt == 'wav', selectionOnly: selOnly);
      Uint8List bytes;
      if (fmt == 'wav') {
        bytes = r.wav!;
      } else {
        setState(() { progress = .5; stage = L('جارٍ الترميز…', 'Encoding…'); });
        bytes = await encodeMp3(r.pcm, kbps, (v) { if (mounted) setState(() => progress = .5 + v * .5); });
      }
      final ext = fmt == 'wav' ? 'wav' : 'mp3';
      final base = ExportService.safeName(name.text.isEmpty ? 'recording' : name.text);
      if (!mounted) return;
      setState(() {
        out = bytes;
        outName = '$base.$ext';
        outMime = fmt == 'wav' ? 'audio/wav' : 'audio/mpeg';
        info = '${fmtBytes(bytes.length)} • ${fmtDur(r.pcm.duration)} • ${r.pcm.channels > 1 ? L('ستريو', 'Stereo') : L('مونو', 'Mono')} • ${(r.pcm.sr / 1000)} kHz\n'
            '${r.loudness.lufs.isFinite ? '${r.loudness.lufs.toStringAsFixed(1)} LUFS • ' : ''}${L('الذروة', 'Peak')} ${r.loudness.peakDb.toStringAsFixed(1)} dB';
      });
    } catch (e) {
      if (mounted) showMsg(context, '${L('فشل التصدير: ', 'Export failed: ')}$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(L('اسم الملف', 'File name'), [TextField(controller: name)]),
      Section(L('الصيغة', 'Format'), [
        ChipRow<String>(options: [('wav', 'WAV'), if (mp3Supported) ('mp3', 'MP3')], value: fmt, onChanged: (v) => setState(() => fmt = v)),
        if (fmt == 'wav')
          ChipRow<int>(options: const [(16, '16-bit'), (24, '24-bit'), (32, '32-bit float')], value: bits, onChanged: (v) => setState(() => bits = v))
        else
          ChipRow<int>(options: const [(128, '128 kbps'), (192, '192 kbps'), (256, '256 kbps'), (320, '320 kbps')], value: kbps, onChanged: (v) => setState(() => kbps = v)),
      ]),
      if (c.hasSel)
        Section(L('النطاق', 'Range'), [ChipRow<bool>(options: [(false, L('الكل', 'Everything')), (true, L('التحديد فقط', 'Selection only'))], value: selOnly, onChanged: (v) => setState(() => selOnly = v))]),
      Hint(L('يتم تطبيق كل التأثيرات (تنقية، إيكو، ضغط، صدى، تسوية الجهارة…) على الملف المُصدَّر.', 'All effects (cleanup, EQ, compression, reverb, loudness…) are applied to the exported file.')),
      PillButton(busy ? '$stage ${(progress * 100).round()}%' : L('تصدير الآن', 'Export now'), busy ? null : _run, icon: Icons.download, primary: true, block: true),
      if (busy) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: progress, color: C.accent, backgroundColor: C.surface3)),
      if (out != null) ...[
        const SizedBox(height: 14),
        Text('✓ ${L('جاهز', 'Ready')}', style: const TextStyle(color: C.ok, fontWeight: FontWeight.w700)),
        InfoCard(children: [Text(outName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(info ?? '', style: const TextStyle(color: C.muted))]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillButton(L('مشاركة', 'Share'), () => ExportService.share(out!, outName!, outMime!), icon: Icons.share, primary: true),
          PillButton(L('حفظ في…', 'Save as…'), () async {
            final ok = await ExportService.saveAs(out!, outName!, outMime!);
            if (ok && context.mounted) showMsg(context, L('تم الحفظ', 'Saved'));
          }, icon: Icons.save_alt),
        ]),
      ],
    ]);
  }
}
