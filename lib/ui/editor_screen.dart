import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/fx.dart';
import '../models/project.dart';
import '../services/editor_controller.dart';
import 'export_panel.dart';
import 'panels_a.dart';
import 'panels_b.dart';
import 'theme.dart';
import 'timeline.dart';
import 'widgets.dart';

class _Tool {
  const _Tool(this.icon, this.label, this.build, {this.active, this.reset});
  final IconData icon;
  final String Function() label;
  final Widget Function(EditorController) build;
  final bool Function(FxSettings)? active;
  final void Function(FxSettings)? reset;
}

final _tools = <_Tool>[
  _Tool(Icons.auto_awesome, () => L('قوالب', 'Presets'), (c) => PresetsPanel(c)),
  _Tool(Icons.shield_outlined, () => L('تنقية', 'Clean'), (c) => CleanPanel(c),
      active: (f) => f.dn || f.gate || f.hpfOn || f.lpfOn || f.humOn,
      reset: (f) { final d = FxSettings(); f.dn = false; f.gate = false; f.hpfOn = d.hpfOn; f.lpfOn = d.lpfOn; f.humOn = d.humOn; }),
  _Tool(Icons.content_cut, () => L('تحرير', 'Edit'), (c) => EditPanel(c)),
  _Tool(Icons.volume_up_outlined, () => L('المستوى', 'Level'), (c) => LevelPanel(c),
      active: (f) => f.gain != 0 || f.normOn || f.fadeIn > 0 || f.fadeOut > 0,
      reset: (f) { f.gain = 0; f.normOn = false; f.fadeIn = 0; f.fadeOut = 0; }),
  _Tool(Icons.speed, () => L('ديناميكس', 'Dynamics'), (c) => DynamicsPanel(c),
      active: (f) => f.compOn || f.warmOn || f.deess > 0, reset: (f) { f.compOn = false; f.warmOn = false; f.deess = 0; }),
  _Tool(Icons.equalizer, () => L('إيكوالايزر', 'EQ'), (c) => EqPanel(c), active: (f) => f.eqOn, reset: (f) { f.eqOn = false; f.eq = List.filled(7, 0.0); }),
  _Tool(Icons.surround_sound, () => L('صدى مكان', 'Reverb'), (c) => ReverbPanel(c), active: (f) => f.revOn, reset: (f) => f.revOn = false),
  _Tool(Icons.multitrack_audio, () => L('أصداء', 'Echo'), (c) => EchoPanel(c), active: (f) => f.echoOn || f.chorusOn, reset: (f) { f.echoOn = false; f.chorusOn = false; }),
  _Tool(Icons.music_note, () => L('الصوت', 'Voice'), (c) => VoicePanel(c), active: (f) => f.ringOn, reset: (f) => f.ringOn = false),
  _Tool(Icons.flag_outlined, () => L('علامات', 'Markers'), (c) => MarkersPanel(c)),
  _Tool(Icons.download, () => L('تصدير', 'Export'), (c) => ExportPanel(c)),
];

const _exportIndex = 10;

class EditorScreen extends StatefulWidget {
  const EditorScreen(this.project, {super.key});
  final Project project;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController c = EditorController(widget.project);
  int? tool;

  @override
  void initState() {
    super.initState();
    c.toastMsg.addListener(() {
      final m = c.toastMsg.value;
      if (m != null && mounted) {
        showMsg(context, m);
        c.toastMsg.value = null;
      }
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await c.close();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            _header(),
            _info(),
            Expanded(child: _stage()),
            _transport(),
            _bottom(h),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Row(children: [
          IconButton(onPressed: _close, icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => TextButton(
                onPressed: () async {
                  final n = await promptDialog(context, L('اسم المشروع', 'Project name'), c.project.name);
                  if (n != null && n.isNotEmpty) c.rename(n);
                },
                child: Text(c.project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: C.text)),
              ),
            ),
          ),
          PillButton(L('تصدير', 'Export'), () => setState(() => tool = _exportIndex), icon: Icons.download, primary: true, small: true),
          const SizedBox(width: 6),
        ]),
      );

  Widget _info() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
        child: ListenableBuilder(
          listenable: Listenable.merge([c, c.tick]),
          builder: (_, _) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: fmtTime(c.center, dec: 1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
                TextSpan(text: '  / ${fmtTime(c.duration, dec: 1)}', style: const TextStyle(fontSize: 14, color: C.muted)),
              ])),
            ),
            const Spacer(),
            if (c.status.isNotEmpty) _chip(c.status, C.accent),
            if (c.loudness != null && c.loudness!.lufs.isFinite) ...[const SizedBox(width: 6), _chip('${c.loudness!.lufs.toStringAsFixed(1)} LUFS', C.muted)],
          ]),
        ),
      );

  Widget _chip(String s, Color col) => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(999)),
          child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: col)),
        ),
      );

  Widget _stage() => Container(
        decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: C.line)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.surface, C.bg])),
        child: Stack(children: [
          Positioned.fill(child: TimelineView(c)),
          PositionedDirectional(
            top: 34, start: 10,
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => GestureDetector(
                onTap: () => c.setBypass(!c.bypass),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: c.bypass ? C.warn : const Color(0x8C000000), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.compare, size: 16, color: c.bypass ? const Color(0xFF201400) : Colors.white),
                    const SizedBox(width: 6),
                    Text(c.bypass ? L('الأصلي', 'Original') : L('بعد', 'After'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.bypass ? const Color(0xFF201400) : Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 8, end: 10,
            child: Row(children: [
              _round(Icons.zoom_in, () { c.pps = (c.pps * 1.6).clamp(1.0, 4000.0); c.tick.ping(); }),
              const SizedBox(width: 6),
              _round(Icons.zoom_out, () { c.pps = (c.pps / 1.6).clamp(1.0, 4000.0); c.tick.ping(); }),
            ]),
          ),
        ]),
      );

  Widget _round(IconData i, VoidCallback f) => Material(
        color: const Color(0x73000000), shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: f, child: Padding(padding: const EdgeInsets.all(8), child: Icon(i, size: 20))),
      );

  Widget _transport() => Directionality(
        textDirection: TextDirection.ltr,
        child: ListenableBuilder(
          listenable: c,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo)),
              IconButton(onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo)),
              IconButton(onPressed: () => c.seek(c.center - 5), icon: const Icon(Icons.replay_5)),
              GestureDetector(
                onTap: c.togglePlay,
                child: Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4))]),
                  child: Icon(c.playing ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 34),
                ),
              ),
              IconButton(onPressed: () => c.seek(c.center + 5), icon: const Icon(Icons.forward_5)),
              IconButton(onPressed: () => c.setLoop(!c.loop), icon: Icon(Icons.repeat, color: c.loop ? C.accent : null)),
              IconButton(onPressed: () => c.addMarker(), icon: const Icon(Icons.flag_outlined)),
            ]),
          ),
        ),
      );

  Widget _bottom(double screenH) {
    return Container(
      decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(22)), border: Border(top: BorderSide(color: C.line))),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: tool == null ? _toolbar() : _panel(screenH),
      ),
    );
  }

  Widget _toolbar() => SizedBox(
        height: 84,
        child: ListenableBuilder(
          listenable: c,
          builder: (_, _) => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              for (var i = 0; i < _tools.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => tool = i),
                  child: SizedBox(
                    width: 70,
                    child: Stack(alignment: Alignment.topCenter, children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_tools[i].icon, size: 24, color: (_tools[i].active?.call(c.fx) ?? false) ? C.accent : const Color(0xFFCFCFD8)),
                        const SizedBox(height: 5),
                        Text(_tools[i].label(), style: TextStyle(fontSize: 11.5, color: (_tools[i].active?.call(c.fx) ?? false) ? C.accent : const Color(0xFFCFCFD8))),
                      ]),
                      if (_tools[i].active?.call(c.fx) ?? false) PositionedDirectional(top: 6, end: 18, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle))),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _panel(double screenH) {
    final t = _tools[tool!];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
          child: Row(children: [
            Expanded(child: Text(t.label(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (t.reset != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: PillButton(L('إعادة ضبط', 'Reset'), () { t.reset!(c.fx); c.fxChanged(clean: true); }, small: true),
              ),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: C.accent, foregroundColor: C.accentInk),
              onPressed: () => setState(() => tool = null),
              icon: const Icon(Icons.check),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: ListenableBuilder(listenable: c, builder: (_, _) => t.build(c)),
          ),
        ),
      ]),
    );
  }
}
