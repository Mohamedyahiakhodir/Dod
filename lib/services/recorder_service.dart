import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dsp/pcm.dart';
import '../dsp/wav.dart';
import '../models/project.dart';

class RecOptions {
  bool noiseSuppress = true, echoCancel = true, autoGain = false, stereo = false, countdown = false, wake = true;
  double gainDb = 0;
  String? deviceId;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    noiseSuppress = p.getBool('rec.ns') ?? true;
    echoCancel = p.getBool('rec.ec') ?? true;
    autoGain = p.getBool('rec.agc') ?? false;
    stereo = p.getBool('rec.stereo') ?? false;
    countdown = p.getBool('rec.cd') ?? false;
    wake = p.getBool('rec.wake') ?? true;
    gainDb = p.getDouble('rec.gain') ?? 0;
    deviceId = p.getString('rec.dev');
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('rec.ns', noiseSuppress);
    await p.setBool('rec.ec', echoCancel);
    await p.setBool('rec.agc', autoGain);
    await p.setBool('rec.stereo', stereo);
    await p.setBool('rec.cd', countdown);
    await p.setBool('rec.wake', wake);
    await p.setDouble('rec.gain', gainDb);
    if (deviceId != null) {
      await p.setString('rec.dev', deviceId!);
    } else {
      await p.remove('rec.dev');
    }
  }
}

class LevelInfo {
  const LevelInfo(this.peak, this.rms);
  final double peak, rms;
}

enum RecState { idle, recording, paused }

/// Wraps the `record` plugin: keeps a PCM16 stream open (for live meters) and stores it while recording.
class RecorderService extends ChangeNotifier {
  RecorderService();

  static const sampleRate = 48000;
  final AudioRecorder _rec = AudioRecorder();
  final RecOptions opts = RecOptions();
  final ValueNotifier<LevelInfo> level = ValueNotifier(const LevelInfo(0, 0));
  final List<double> bars = []; // peak per ~10 ms, newest last (for the live waveform)
  final List<Marker> markers = [];
  final List<Uint8List> _chunks = [];
  StreamSubscription<Uint8List>? _sub;
  int _samples = 0, clips = 0;
  Uint8List? _carry;
  RecState state = RecState.idle;
  bool micReady = false;
  String? error;
  final List<double> _floor = [];

  int get channels => opts.stereo ? 2 : 1;
  double get seconds => _samples / sampleRate;
  int get bytes => _samples * 2 * channels;

  /// Quietest-20% RMS (dBFS) of the last few seconds — shown as a "room noise" indicator.
  double? get roomFloorDb {
    if (_floor.length < 30) return null;
    final s = List<double>.from(_floor)..sort();
    return 20 * math.log(math.max(s[(s.length * 0.2).floor()], 1e-6)) / math.ln10;
  }

  Future<List<InputDevice>> devices() async {
    try {
      return await _rec.listInputDevices();
    } catch (_) {
      return [];
    }
  }

  Future<bool> openMic() async {
    await closeMic();
    error = null;
    try {
      if (!await _rec.hasPermission()) {
        error = 'permission';
        notifyListeners();
        return false;
      }
      InputDevice? dev;
      if (opts.deviceId != null) {
        for (final d in await devices()) {
          if (d.id == opts.deviceId) dev = d;
        }
      }
      final stream = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        device: dev,
        autoGain: opts.autoGain,
        echoCancel: opts.echoCancel,
        noiseSuppress: opts.noiseSuppress,
      ));
      _sub = stream.listen(_onData, onError: (e) {
        error = '$e';
        notifyListeners();
      });
      micReady = true;
      notifyListeners();
      return true;
    } catch (e) {
      error = '$e';
      micReady = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> closeMic() async {
    if (state != RecState.idle) return;
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    micReady = false;
    level.value = const LevelInfo(0, 0);
  }

  void _onData(Uint8List raw) {
    var data = raw;
    if (_carry != null) {
      data = Uint8List(_carry!.length + raw.length)..setAll(0, _carry!)..setAll(_carry!.length, raw);
      _carry = null;
    }
    final frame = 2 * channels, usable = data.length - data.length % frame;
    if (usable < data.length) _carry = Uint8List.sublistView(data, usable);
    if (usable == 0) return;
    final out = Uint8List(usable), bd = ByteData.view(data.buffer, data.offsetInBytes, usable), ob = ByteData.view(out.buffer);
    final g = dbToGain(opts.gainDb);
    var peak = 0, sumSq = 0.0;
    final n = usable ~/ 2;
    for (var i = 0; i < n; i++) {
      var v = bd.getInt16(i * 2, Endian.little);
      if (g != 1) v = (v * g).round().clamp(-32768, 32767);
      ob.setInt16(i * 2, v, Endian.little);
      final a = v.abs();
      if (a > peak) peak = a;
      sumSq += v * v.toDouble();
    }
    final info = LevelInfo(peak / 32768, math.sqrt(sumSq / n) / 32768);
    level.value = info;
    // waveform bars (~10 ms each)
    final perBar = (sampleRate * 0.01).round() * channels;
    for (var s = 0; s < n; s += perBar) {
      var m = 0;
      for (var i = s; i < math.min(n, s + perBar); i++) {
        final a = ob.getInt16(i * 2, Endian.little).abs();
        if (a > m) m = a;
      }
      bars.add(m / 32768);
    }
    if (bars.length > 3000) bars.removeRange(0, bars.length - 2000);
    if (state == RecState.recording) {
      _chunks.add(out);
      _samples += usable ~/ frame;
      if (peak >= 32700) clips++;
    } else if (state == RecState.idle) {
      _floor.add(info.rms);
      if (_floor.length > 200) _floor.removeAt(0);
    }
  }

  void start() {
    _chunks.clear();
    _samples = 0;
    clips = 0;
    markers.clear();
    state = RecState.recording;
    notifyListeners();
  }

  void pause() {
    if (state == RecState.recording) {
      state = RecState.paused;
      notifyListeners();
    }
  }

  void resume() {
    if (state == RecState.paused) {
      state = RecState.recording;
      notifyListeners();
    }
  }

  void addMarker(String name) => markers.add(Marker(seconds, name));

  Future<Pcm?> stop() async {
    if (state == RecState.idle) return null;
    state = RecState.idle;
    final all = Uint8List(_chunks.fold<int>(0, (s, c) => s + c.length));
    var o = 0;
    for (final c in _chunks) {
      all.setAll(o, c);
      o += c.length;
    }
    _chunks.clear();
    notifyListeners();
    if (all.isEmpty) return null;
    return pcm16ToFloat(all, channels, sampleRate);
  }

  Future<void> reopen() async {
    if (state == RecState.idle) await openMic();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rec.dispose();
    super.dispose();
  }
}
