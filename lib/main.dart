import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dsp/pcm.dart';
import 'l10n.dart';
import 'models/project.dart';
import 'services/library_store.dart';
import 'services/recorder_service.dart';
import 'ui/editor_screen.dart';
import 'ui/library_screen.dart';
import 'ui/record_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLang();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: C.bg, statusBarIconBrightness: Brightness.light));
  runApp(const VoiceStudioApp());
}

class VoiceStudioApp extends StatelessWidget {
  const VoiceStudioApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: appLang,
        builder: (_, lang, _) => MaterialApp(
          title: 'Voice Studio',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: Locale(lang),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Shell(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final rec = RecorderService();
  final refresh = ValueNotifier<int>(0);
  int tab = 0; // 0 = record, 1 = library
  bool recording = false;

  @override
  void dispose() {
    rec.dispose();
    super.dispose();
  }

  Future<void> _openProject(Project p) async {
    final prev = tab;
    setState(() => tab = 1); // pause the mic while editing
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditorScreen(p)));
    refresh.value++;
    if (mounted) setState(() => tab = prev == 0 ? 1 : prev);
  }

  Future<void> _openId(String id, [Project? loaded]) async {
    var p = loaded;
    if (p == null) {
      showMsg(context, L('جارٍ فتح التسجيل…', 'Opening…'));
      p = await ProjectRepo.open(id);
    }
    if (!mounted) return;
    if (p == null) {
      showMsg(context, L('تعذّر فتح التسجيل', 'Could not open recording'));
      return;
    }
    await _openProject(p);
  }

  Future<void> _finishRecording(Pcm pcm, List<Marker> markers) async {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = '${L('تسجيل ', 'Recording ')}${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    final p = ProjectRepo.fromPcm(pcm, name, markers: markers);
    try {
      await ProjectRepo.save(p);
    } catch (_) {}
    if (mounted) await _openProject(p);
  }

  Future<void> _settings() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(L('الإعدادات', 'Settings'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ListTile(leading: const Icon(Icons.translate), title: Text(appLang.value == 'ar' ? 'English' : 'العربية'), onTap: () => Navigator.pop(c, 'lang')),
          ListTile(leading: const Icon(Icons.info_outline), title: Text(L('حول التطبيق', 'About')), onTap: () => Navigator.pop(c, 'about')),
        ]),
      ),
    );
    if (v == 'lang') {
      await setLang(appLang.value == 'ar' ? 'en' : 'ar');
    } else if (v == 'about' && mounted) {
      await confirmDialog(context, L('ستوديو الصوت — تسجيل وتنقية وتحرير ومعالجة احترافية للصوت مباشرة على هاتفك. كل المعالجة تتم محليًا على جهازك ولا يتم رفع أي صوت.', 'Voice Studio — pro recording, cleanup, editing and mastering right on your phone. All processing is local; no audio is uploaded.'), ok: 'OK');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: [
        RecordScreen(
          rec: rec,
          active: tab == 0,
          onFinish: _finishRecording,
          onRecordingChanged: (v) => setState(() => recording = v),
        ),
        LibraryScreen(onOpen: _openId, refresh: refresh),
      ]),
      bottomNavigationBar: recording
          ? null
          : Container(
              decoration: const BoxDecoration(color: Color(0xF00F0F14), border: Border(top: BorderSide(color: C.line))),
              child: SafeArea(
                child: SizedBox(
                  height: 64,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _nav(Icons.view_list, L('المكتبة', 'Library'), tab == 1, () => setState(() { tab = 1; refresh.value++; })),
                    _nav(Icons.mic, L('تسجيل', 'Record'), tab == 0, () => setState(() => tab = 0), rec: true),
                    _nav(Icons.settings_outlined, L('الإعدادات', 'Settings'), false, _settings),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _nav(IconData i, String l, bool on, VoidCallback f, {bool rec = false}) => InkWell(
        onTap: f,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 84,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            rec
                ? Container(width: 40, height: 40, decoration: const BoxDecoration(color: C.rec, shape: BoxShape.circle), child: Icon(i, color: Colors.white))
                : Icon(i, size: 24, color: on ? C.accent : C.muted),
            const SizedBox(height: 2),
            Text(l, style: TextStyle(fontSize: 11, color: on || rec ? C.text : C.muted)),
          ]),
        ),
      );
}
