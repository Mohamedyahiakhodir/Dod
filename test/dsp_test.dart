import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/dsp/chain.dart';
import 'package:voice_studio/dsp/clean.dart';
import 'package:voice_studio/dsp/loudness.dart';
import 'package:voice_studio/dsp/ops.dart';
import 'package:voice_studio/dsp/pcm.dart';
import 'package:voice_studio/dsp/stretch.dart';
import 'package:voice_studio/dsp/wav.dart';
import 'package:voice_studio/models/fx.dart';

Pcm synth({int sr = 48000, double secs = 6, double noise = 0.02}) {
  final n = (sr * secs).round(), x = Float32List(n), rnd = math.Random(1);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final env = math.max(0, math.sin(math.pi * ((t * 1.5) % 1))) * ((t * 1.5).floor() % 3 == 2 ? 0 : 1);
    var v = 0.0;
    for (var k = 1; k < 8; k++) {
      v += math.sin(2 * math.pi * 140 * k * t) / k;
    }
    x[i] = 0.25 * env * v + noise * (rnd.nextDouble() * 2 - 1) + 0.01 * math.sin(2 * math.pi * 50 * t);
  }
  return Pcm([x], sr);
}

void main() {
  test('wav round trip', () {
    final p = synth(secs: 1);
    for (final bits in [16, 24, 32]) {
      final d = decodeWav(encodeWav(p, bits: bits))!;
      expect(d.length, p.length);
      expect(d.sr, p.sr);
      var err = 0.0;
      for (var i = 0; i < p.length; i += 97) {
        err = math.max(err, (d.ch[0][i] - p.ch[0][i]).abs());
      }
      expect(err, lessThan(bits == 16 ? 2e-4 : 1e-5));
    }
  });

  test('denoise lowers the noise floor', () {
    final p = synth();
    final before = noiseFloorDb(p);
    final out = runClean(CleanJob(p, const CleanParams(denoise: true, amount: 70)));
    final after = noiseFloorDb(out);
    expect(out.length, p.length);
    expect(after, lessThan(before - 6));
  });

  test('loudness normalisation hits the target', () {
    final p = synth(noise: 0.0005);
    final fx = FxSettings()..normOn = true..normTarget = -16;
    final r = runRender(RenderJob(p, fx, wantWav: false));
    expect(r.loudness.lufs, closeTo(-16, 0.6));
    expect(r.loudness.peakDb, lessThanOrEqualTo(-0.9));
  });

  test('tempo and pitch', () {
    final p = synth(secs: 4);
    final t = runStretch(StretchJob(p, 1.5, 0));
    expect((t.duration - p.duration / 1.5).abs(), lessThan(0.05));
    final s = runStretch(StretchJob(p, 1.0, 5));
    expect((s.duration - p.duration).abs(), lessThan(0.05));
  });

  test('reverb tail & level', () {
    final p = synth(secs: 3, noise: 0.0005);
    final fx = FxSettings()..revOn = true..revType = 'mosque'..revDecay = 3.0..revMix = 30;
    final r = runRender(RenderJob(p, fx, wantWav: false));
    expect(r.pcm.channels, 2);
    expect(r.pcm.duration, greaterThan(p.duration + 2.5));
    final dry = measureLoudness(p).lufs, wet = r.loudness.lufs;
    // wet signal should stay in the same loudness ballpark as the dry one
    expect((wet - dry).abs(), lessThan(6));
  });

  test('ops keep lengths consistent', () {
    final p = synth(secs: 2);
    expect(cut(p, 1000, 5000).length, p.length - 4000);
    expect(keep(p, 1000, 5000).length, 4000);
    expect(insertSilence(p, 100, 0.5).length, p.length + 24000);
    final r = removeSilences(p, thDb: -40);
    expect(r.pcm.length, lessThanOrEqualTo(p.length));
  });
}
