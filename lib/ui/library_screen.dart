import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dsp/wav.dart';
import '../l10n.dart';
import '../models/project.dart';
import '../services/export_service.dart';
import '../services/library_store.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpen, required this.refresh});
  final void Function(String id, [Project? loaded]) onOpen;
  final ValueNotifier<int> refresh;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<ProjectMeta> items = [];
  String q = '';

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await LibraryStore.instance.list();
    if (mounted) setState(() => items = l);
  }

  Future<void> _import() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['wav']);
    if (f == null) return;
    final pcm = decodeWav(await f.readAsBytes());
    if (!mounted) return;
    if (pcm == null) {
      showMsg(context, L('الاستيراد يدعم ملفات WAV حاليًا', 'Import currently supports WAV files'));
      return;
    }
    final name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final p = ProjectRepo.fromPcm(pcm, name);
    await ProjectRepo.save(p);
    widget.onOpen(p.id, p);
  }

  Future<void> _menu(ProjectMeta m) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          for (final e in [
            ('open', Icons.edit, L('فتح وتحرير', 'Open & edit')),
            ('wav', Icons.share, L('مشاركة WAV (الأصل)', 'Share WAV (original)')),
            ('rename', Icons.drive_file_rename_outline, L('إعادة تسمية', 'Rename')),
            ('dup', Icons.copy, L('نسخة مكررة', 'Duplicate')),
            ('del', Icons.delete_outline, L('حذف', 'Delete')),
          ])
            ListTile(leading: Icon(e.$2, color: e.$1 == 'del' ? C.bad : null), title: Text(e.$3, style: TextStyle(color: e.$1 == 'del' ? C.bad : null)), onTap: () => Navigator.pop(c, e.$1)),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    final store = LibraryStore.instance;
    switch (v) {
      case 'open':
        widget.onOpen(m.id);
      case 'rename':
        final n = await promptDialog(context, L('اسم التسجيل', 'Recording name'), m.name);
        if (n != null && n.isNotEmpty) {
          m.name = n;
          await store.saveMeta(m);
          _load();
        }
      case 'dup':
        final wav = await store.loadWav(m.id);
        if (wav != null) {
          final copy = ProjectMeta.fromJson(m.toJson())
            ..id = Project.newId()
            ..name = '${m.name}${L(' (نسخة)', ' (copy)')}'
            ..updated = DateTime.now().millisecondsSinceEpoch;
          await store.saveWav(copy.id, wav);
          await store.saveMeta(copy);
          _load();
        }
      case 'del':
        if (await confirmDialog(context, L('حذف "${m.name}" نهائيًا؟', 'Delete "${m.name}" permanently?'), ok: L('حذف', 'Delete'), danger: true)) {
          await store.delete(m.id);
          _load();
        }
      case 'wav':
        final wav = await store.loadWav(m.id);
        if (wav != null) await ExportService.share(wav, '${ExportService.safeName(m.name)}.wav', 'audio/wav');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vis = items.where((m) => q.isEmpty || m.name.toLowerCase().contains(q.toLowerCase())).toList();
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
          child: Row(children: [
            Text(L('المكتبة', 'Library'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: _import, icon: const Icon(Icons.upload_file), tooltip: L('استيراد', 'Import')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: L('ابحث في التسجيلات…', 'Search recordings…'), hintStyle: const TextStyle(color: C.muted)),
          ),
        ),
        Expanded(
          child: vis.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mic_none, size: 48, color: C.muted),
                      const SizedBox(height: 10),
                      Text(items.isEmpty ? L('لا توجد تسجيلات بعد. ابدأ أول تسجيل لك!', 'No recordings yet. Make your first one!') : L('لا نتائج', 'No results'), textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: vis.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _card(vis[i]),
                ),
        ),
      ]),
    );
  }

  Widget _card(ProjectMeta m) {
    final d = DateTime.fromMillisecondsSinceEpoch(m.updated);
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.onOpen(m.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
          child: Row(children: [
            Container(width: 92, height: 44, decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)), child: CustomPaint(painter: _ThumbPainter(m.thumb))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${fmtDur(m.duration)} • ${d.day}/${d.month}/${d.year} • ${m.channels > 1 ? L('ستريو', 'Stereo') : L('مونو', 'Mono')}', style: const TextStyle(color: C.muted, fontSize: 12.5)),
              ]),
            ),
            IconButton(onPressed: () => _menu(m), icon: const Icon(Icons.more_horiz)),
          ]),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.t);
  final List<double> t;
  @override
  void paint(Canvas c, Size s) {
    if (t.isEmpty) return;
    final bw = s.width / t.length, p = Paint()..color = C.accent;
    for (var i = 0; i < t.length; i++) {
      final hh = (t[i] * (s.height - 6)).clamp(2.0, s.height);
      c.drawRect(Rect.fromLTWH(i * bw, (s.height - hh) / 2, (bw - 1.2).clamp(1.0, 10.0), hh), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.t != t;
}
