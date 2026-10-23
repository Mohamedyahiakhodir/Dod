import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../dsp/chain.dart';
import '../dsp/clean.dart';
import '../dsp/loudness.dart';
import '../dsp/ops.dart' as ops;
import '../dsp/pcm.dart';
import '../dsp/stretch.dart';
import '../dsp/wav.dart';
import '../l10n.dart';
import '../models/fx.dart';
import '../models/project.dart';
import 'library_store.dart';
import 'preview_player.dart';

class Peaks {
  Peaks(this.n, this.l1, this.l2);
  static const b1 = 64, b2 = 4096;
  final int n;
  final Float32List l1, l2;

  factory Peaks.build(Pcm p) {
    final n = p.length;
    final l1 = Float32List(n ~/ b1 + 2);
    for (final c in p.ch) {
      for (var b = 0; b < l1.length; b++) {
        var m = l1[b];
        final e = math.min(n, (b + 1) * b1);
        for (var i = b * b1; i < e; i++) {
          final a = c[i].abs();
          if (a > m) m = a;
        }
        l1[b] = m;
      }
    }
    const k = b2 ~/ b1;
    final l2 = Float32List(l1.length ~/ k + 2);
    for (var b = 0; b < l1.length; b++) {
      final j = b ~/ k;
      if (l1[b] > l2[j]) l2[j] = l1[b];
    }
    return Peaks(n, l1, l2);
  }

  double at(Pcm p, int a, int b) {
    a = math.max(0, a);
    b = math.min(n, b);
    if (b <= a) return 0;
    var m = 0.0;
    if (b - a >= b2 * 2) {
      for (var i = a ~/ b2; i <= math.min(l2.length - 1, b ~/ b2); i++) {
        if (l2[i] > m) m = l2[i];
      }
    } else if (b - a >= b1 * 2) {
      for (var i = a ~/ b1; i <= math.min(l1.length - 1, b ~/ b1); i++) {
        if (l1[i] > m) m = l1[i];
      }
    } else {
      for (final c in p.ch) {
        for (var i = a; i < math.min(b, c.length); i++) {
          final v = c[i].abs();
          if (v > m) m = v;
        }
      }
    }
    return m;
  }
}

/// Lightweight notifier for playhead movement (so only the timeline repaints while playing).
class Tick extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _Snap {
  _Snap(this.pcm, this.cleaned, this.cleanKey, this.markers);
  final Pcm pcm;
  final Pcm? cleaned;
  final String cleanKey;
  final List<Marker> markers;
}

Pcm _cleanEntry(CleanJob j) => runClean(j);
Pcm _stretchEntry(StretchJob j) => runStretch(j);
RenderResult _renderEntry(RenderJob j) => runRender(j);

/// All state and logic of the editor screen.
class EditorController extends ChangeNotifier {
  EditorController(this.project) {
    base = project.pcm;
    fx = project.fx;
    _rebuildPeaks();
    _posSub = player.positionStream.listen(_onPosition);
    _playSub = player.playingStream.listen((_) => notifyListeners());
    _stateSub = player.stateStream.listen((s) {
      if (s == ProcessingState.completed) {
        player.pause();
        center = duration;
        tick.ping();
        notifyListeners();
      }
    });
    if (fx.cleanActive) {
      scheduleClean(100);
    } else {
      invalidatePreview(immediate: true);
    }
  }

  final Project project;
  final PreviewPlayer player = PreviewPlayer();
  final Tick tick = Tick();
  late Pcm base;
  Pcm? cleaned;
  String _cleanDone = '';
  late FxSettings fx;
  late Peaks peaks;
  Pcm get shown => cleaned ?? base;
  int get sr => base.sr;
  double get duration => base.duration;

  double center = 0; // playhead / timeline centre (seconds)
  double pps = 80; // pixels per second
  double? selA, selB;
  bool loop = false, bypass = false, dragging = false;
  bool get hasSel => selA != null && selB != null && selB! - selA! > 0.005;
  Pcm? clip;
  Float32List? noiseProfile;
  int _profileId = 0;
  bool get hasProfile => noiseProfile != null;
  Loudness? loudness;
  String status = '';
  final List<_Snap> _undo = [], _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get playing => player.playing;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<ProcessingState>? _stateSub;
  Timer? _cleanTimer, _prevTimer, _saveTimer;
  int _cleanId = 0, _prevId = 0;
  bool _disposed = false;
  Uint8List? _rawWav;
  Pcm? _rawFor;
  final ValueNotifier<String?> toastMsg = ValueNotifier(null);

  void toast(String s) => toastMsg.value = s;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---------------------------------------------------------------- playback
  void _onPosition(Duration d) {
    if (dragging || !player.playing) return;
    var t = d.inMicroseconds / 1e6;
    if (loop && hasSel && t >= selB!) {
      player.seek(Duration(microseconds: (selA! * 1e6).round()));
      t = selA!;
    }
    center = math.min(t, duration);
    tick.ping();
  }

  Future<void> togglePlay() async {
    if (player.playing) {
      await player.pause();
    } else {
      if (center >= duration - 0.03) await seek(0);
      await player.play();
    }
    notifyListeners();
  }

  Future<void> seek(double t) async {
    center = t.clamp(0.0, duration);
    tick.ping();
    await player.seek(Duration(microseconds: (center * 1e6).round()));
  }

  void scrub(double t) {
    center = t.clamp(0.0, duration);
    tick.ping();
  }

  Future<void> beginDrag() async {
    dragging = true;
    _wasPlaying = player.playing;
    if (_wasPlaying) await player.pause();
  }

  bool _wasPlaying = false;
  Future<void> endDrag() async {
    dragging = false;
    await player.seek(Duration(microseconds: (center * 1e6).round()));
    if (_wasPlaying) await player.play();
    notifyListeners();
  }

  void setLoop(bool v) {
    if (v && !hasSel) {
      toast(L('حدّد جزءًا أولاً لتكراره', 'Select a part to loop first'));
      return;
    }
    loop = v;
    notifyListeners();
  }

  Future<void> setBypass(bool v) async {
    bypass = v;
    notifyListeners();
    await _renderPreview(forceRaw: v);
  }

  // --------------------------------------------------------------- selection
  void setSel(double? a, double? b) {
    if (a == null || b == null) {
      selA = selB = null;
      loop = false;
    } else {
      a = a.clamp(0.0, duration);
      b = b.clamp(0.0, duration);
      selA = math.min(a, b);
      selB = math.max(a, b);
      if (selB! - selA! < 0.01) {
        selA = selB = null;
        loop = false;
      }
    }
    notifyListeners();
  }

  /// Selection in samples, or null (with a hint toast).
  (int, int)? selSamples({bool warn = true}) {
    if (!hasSel) {
      if (warn) toast(L('حدّد جزءًا من التسجيل أولاً (اسحب المقابض)', 'Select a part of the recording first'));
      return null;
    }
    return ((selA! * sr).round(), (selB! * sr).round());
  }

  // ------------------------------------------------------------------ history
  _Snap _snap() => _Snap(base, cleaned, _cleanDone, [for (final m in project.markers) Marker(m.t, m.name)]);

  void _pushUndo() {
    _undo.add(_snap());
    _redo.clear();
    var total = _undo.fold<int>(0, (s, x) => s + x.pcm.length * x.pcm.channels * 4);
    while (_undo.length > 1 && (_undo.length > 20 || total > 300e6)) {
      final r = _undo.removeAt(0);
      total -= r.pcm.length * r.pcm.channels * 4;
    }
  }

  void _restore(_Snap s) {
    base = s.pcm;
    cleaned = s.cleaned;
    _cleanDone = s.cleanKey;
    project.markers = s.markers;
    _afterBase();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
  }

  /// Apply a destructive edit. [mm] maps marker times (return null to drop a marker).
  bool edit(Pcm next, {double? Function(double)? mm, bool resetFx = false}) {
    if (identical(next, base)) return false;
    _pushUndo();
    base = next;
    cleaned = null;
    _cleanDone = '';
    if (mm != null) {
      project.markers = [
        for (final m in project.markers)
          if (mm(m.t) != null) Marker(mm(m.t)!, m.name)
      ];
    }
    if (resetFx) {
      fx = FxSettings();
      project.fx = fx;
      loudness = null;
    }
    _afterBase();
    return true;
  }

  void _rebuildPeaks() => peaks = Peaks.build(shown);

  void _afterBase() {
    _rawWav = null;
    _rebuildPeaks();
    center = center.clamp(0.0, duration);
    if (hasSel) setSel(selA, selB);
    if (fx.cleanActive && (cleaned == null || _cleanDone != _cleanKey())) {
      cleaned = null;
      _rebuildPeaks();
      scheduleClean(300);
    } else {
      invalidatePreview();
    }
    _saveSoon();
    notifyListeners();
  }

  // --------------------------------------------------------------- fx / clean
  String _cleanKey() => '${fx.cleanKey}|$_profileId';

  /// Call after changing [fx]. [clean] = the change affects the cached clean stage.
  void fxChanged({bool clean = false}) {
    project.fx = fx;
    if (clean) {
      scheduleClean(600);
    } else {
      invalidatePreview();
    }
    _saveSoon();
    notifyListeners();
  }

  void setFx(FxSettings f) {
    fx = f;
    fxChanged(clean: true);
  }

  void learnProfile() {
    final s = selSamples();
    if (s == null) return;
    if (s.$2 - s.$1 < 4096) {
      toast(L('التحديد قصير جدًا (اختر نصف ثانية على الأقل)', 'Selection too short (pick at least 0.5 s)'));
      return;
    }
    noiseProfile = Float32List.sublistView(base.ch[0], s.$1, s.$2).sublist(0);
    _profileId++;
    fx.dn = true;
    fxChanged(clean: true);
    toast(L('تم التقاط بصمة الضوضاء', 'Noise profile captured'));
  }

  void clearProfile() {
    noiseProfile = null;
    _profileId++;
    fxChanged(clean: true);
  }

  void scheduleClean(int ms) {
    _cleanTimer?.cancel();
    _cleanTimer = Timer(Duration(milliseconds: ms), _runClean);
  }

  Future<void> _runClean() async {
    final id = ++_cleanId;
    if (!fx.cleanActive) {
      if (cleaned != null) {
        cleaned = null;
        _cleanDone = '';
        _rebuildPeaks();
      }
      status = '';
      invalidatePreview(immediate: true);
      notifyListeners();
      return;
    }
    final key = _cleanKey();
    if (cleaned != null && _cleanDone == key) {
      invalidatePreview(immediate: true);
      return;
    }
    status = L('جارٍ التنقية…', 'Cleaning…');
    notifyListeners();
    final src = base;
    try {
      final out = await compute(
          _cleanEntry,
          CleanJob(src, CleanParams(denoise: fx.dn, amount: fx.dnAmount, gate: fx.gate, gateDb: fx.gateDb, gateRange: fx.gateRange, deess: fx.deess, profile: fx.dn ? noiseProfile : null)));
      if (id != _cleanId || !identical(src, base)) return;
      cleaned = out;
      _cleanDone = key;
      _rebuildPeaks();
      status = '';
      invalidatePreview(immediate: true);
    } catch (e) {
      if (id == _cleanId) {
        status = '';
        toast('${L('فشلت التنقية: ', 'Cleaning failed: ')}$e');
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ preview
  void invalidatePreview({bool immediate = false}) {
    _prevTimer?.cancel();
    _prevTimer = Timer(Duration(milliseconds: immediate ? 0 : 350), _renderPreview);
  }

  Future<void> _renderPreview({bool forceRaw = false}) async {
    if (_disposed) return;
    final id = ++_prevId;
    final raw = forceRaw || bypass;
    Uint8List wav;
    if (raw) {
      if (_rawFor != base || _rawWav == null) {
        _rawWav = encodeWav(base, bits: 16);
        _rawFor = base;
      }
      wav = _rawWav!;
    } else {
      status = status.isEmpty ? L('جارٍ التحديث…', 'Updating…') : status;
      notifyListeners();
      final r = await compute(_renderEntry, RenderJob(shown, fx));
      if (id != _prevId || _disposed) return;
      loudness = r.loudness;
      wav = r.wav!;
      if (status == L('جارٍ التحديث…', 'Updating…')) status = '';
    }
    final was = player.playing;
    final pos = Duration(microseconds: (center * 1e6).round());
    try {
      await player.load(wav, position: pos);
      if (was) await player.play();
    } catch (e) {
      toast(L('تعذّر تشغيل المعاينة', 'Could not play preview'));
    }
    notifyListeners();
  }

  // ------------------------------------------------------- heavy edit helpers
  Future<void> applyStretch(double tempo, double semitones) async {
    status = L('جارٍ المعالجة…', 'Processing…');
    notifyListeners();
    try {
      final out = await compute(_stretchEntry, StretchJob(base, tempo, semitones));
      edit(out, mm: (t) => t / tempo);
      toast(L('تم التطبيق', 'Applied'));
    } catch (e) {
      toast(L('فشلت المعالجة', 'Processing failed'));
    }
    status = '';
    notifyListeners();
  }

  /// Render all effects permanently into the audio.
  Future<void> bake() async {
    status = L('جارٍ الدمج…', 'Baking…');
    notifyListeners();
    try {
      final r = await compute(_renderEntry, RenderJob(shown, fx, wantWav: false));
      edit(r.pcm, resetFx: true);
      noiseProfile = null;
      _profileId++;
    } catch (e) {
      toast(L('فشلت المعالجة', 'Processing failed'));
    }
    status = '';
    notifyListeners();
  }

  Future<RenderResult> renderForExport({required int bits, bool wantWav = true, bool selectionOnly = false}) {
    final s = selectionOnly ? selSamples() : null;
    return compute(_renderEntry, RenderJob(shown, fx, bits: bits, wantWav: wantWav, selStart: s?.$1 ?? -1, selEnd: s?.$2 ?? -1));
  }

  // --------------------------------------------------------------- ops (UI)
  void cutSel() {
    final s = selSamples();
    if (s == null) return;
    final a = s.$1 / sr, b = s.$2 / sr;
    edit(ops.cut(base, s.$1, s.$2), mm: (t) => t >= b ? t - (b - a) : (t > a ? a : t));
    setSel(null, null);
    seek(a);
  }

  void keepSel() {
    final s = selSamples();
    if (s == null) return;
    final a = s.$1 / sr, b = s.$2 / sr;
    edit(ops.keep(base, s.$1, s.$2), mm: (t) => (t < a || t > b) ? null : t - a);
    setSel(null, null);
    seek(0);
  }

  void cutBeforePlayhead() {
    final p = (center * sr).round(), t0 = center;
    edit(ops.cut(base, 0, p), mm: (t) => math.max(0, t - t0));
    seek(0);
  }

  void cutAfterPlayhead() {
    final p = (center * sr).round(), t0 = center;
    edit(ops.cut(base, p, base.length), mm: (t) => t > t0 ? null : t);
  }

  void muteSel() {
    final s = selSamples();
    if (s != null) edit(ops.silence(base, s.$1, s.$2));
  }

  void reverseSel() {
    final s = selSamples();
    if (s != null) edit(ops.reverseRegion(base, s.$1, s.$2));
  }

  void fadeSel({required bool fadeIn}) {
    final s = selSamples();
    if (s != null) edit(ops.fadeRegion(base, s.$1, s.$2, fadeIn: fadeIn));
  }

  void gainSel(double db) {
    final s = selSamples();
    if (s != null) edit(ops.gainRegion(base, s.$1, s.$2, db));
  }

  void copySel() {
    final s = selSamples();
    if (s == null) return;
    clip = base.sliceSamples(s.$1, s.$2);
    toast(L('تم النسخ', 'Copied'));
  }

  void pasteAtPlayhead() {
    final c = clip;
    if (c == null) {
      toast(L('لا يوجد شيء منسوخ', 'Nothing copied'));
      return;
    }
    final p = (center * sr).round(), t0 = center, k = c.length / sr;
    edit(ops.paste(base, p, c), mm: (t) => t >= t0 ? t + k : t);
  }

  void duplicateSel() {
    final s = selSamples();
    if (s == null) return;
    final part = base.sliceSamples(s.$1, s.$2), b = s.$2 / sr, k = (s.$2 - s.$1) / sr;
    edit(ops.paste(base, s.$2, part), mm: (t) => t >= b ? t + k : t);
  }

  void insertSilenceAtPlayhead(double secs) {
    final p = (center * sr).round(), t0 = center;
    edit(ops.insertSilence(base, p, secs), mm: (t) => t >= t0 ? t + secs : t);
  }

  double removeSilences(double th, double minMs, double padMs) {
    final r = ops.removeSilences(base, thDb: th, minMs: minMs, padMs: padMs);
    if (r.removed > 0) edit(r.pcm, mm: r.map);
    return r.removed;
  }

  void appendAudio(Pcm other) => edit(ops.append(base, other), mm: (t) => t);

  // ------------------------------------------------------------------ markers
  void addMarker([String? name]) {
    project.markers.add(Marker(center, name ?? '${L('علامة', 'Marker')} ${project.markers.length + 1}'));
    project.markers.sort((a, b) => a.t.compareTo(b.t));
    _saveSoon();
    notifyListeners();
  }

  void markersChanged() {
    project.markers.sort((a, b) => a.t.compareTo(b.t));
    _saveSoon();
    notifyListeners();
  }

  void rename(String n) {
    project.name = n;
    _saveSoon();
    notifyListeners();
  }

  // --------------------------------------------------------------------- save
  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 2500), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    project.pcm = base;
    project.fx = fx;
    try {
      await ProjectRepo.save(project);
    } catch (e) {
      toast(L('تعذّر الحفظ', 'Could not save'));
    }
  }

  Future<void> close() async {
    _cleanTimer?.cancel();
    _prevTimer?.cancel();
    await player.pause();
    await save();
  }

  @override
  void dispose() {
    _disposed = true;
    _cleanTimer?.cancel();
    _prevTimer?.cancel();
    _saveTimer?.cancel();
    _posSub?.cancel();
    _playSub?.cancel();
    _stateSub?.cancel();
    player.dispose();
    toastMsg.dispose();
    super.dispose();
  }
}
