import 'dart:math' as math;
import 'dart:typed_data';

import '../models/fx.dart';

class _Comb {
  _Comb(int len, this.fb, this.damp) : buf = Float32List(len);
  final Float32List buf;
  final double fb, damp;
  int idx = 0;
  double filt = 0;
  double process(double x) {
    final o = buf[idx];
    filt = o * (1 - damp) + filt * damp;
    buf[idx] = x + filt * fb;
    if (++idx >= buf.length) idx = 0;
    return o;
  }
}

class _Allpass {
  _Allpass(int len) : buf = Float32List(len);
  final Float32List buf;
  int idx = 0;
  double process(double x) {
    final b = buf[idx];
    buf[idx] = x + b * 0.5;
    if (++idx >= buf.length) idx = 0;
    return b - x;
  }
}

const _combTunes = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const _allTunes = [556, 441, 341, 225];

/// Algorithmic (Freeverb-style) stereo reverb. [mono] is the input; returns wet L/R (same length).
List<Float32List> reverbWet(Float32List mono, int sr, FxSettings fx) {
  final t = reverbTypes[fx.revType] ?? reverbTypes['room']!;
  final n = mono.length, scale = sr / 44100 * t.size;
  final damp = (fx.revDamp / 100).clamp(0.0, 0.95) * 0.8;
  final rt = fx.revDecay.clamp(0.2, 12.0);
  final outs = [Float32List(n), Float32List(n)];
  final preLen = math.max(1, (fx.revPre / 1000 * sr).round());
  final pre = Float32List(preLen);
  final level = 0.9 / math.sqrt(rt * 2.4 + 0.6); // keeps wet loudness roughly constant across decay times
  for (var side = 0; side < 2; side++) {
    final spread = side == 0 ? 0 : 23;
    final combs = [
      for (final d in _combTunes)
        () {
          final len = math.max(16, ((d + spread) * scale).round());
          return _Comb(len, math.pow(10, -3 * len / (sr * rt)).toDouble(), damp);
        }()
    ];
    final aps = [for (final d in _allTunes) _Allpass(math.max(8, ((d + spread) * scale).round()))];
    var pi = 0;
    final out = outs[side];
    for (var i = 0; i < n; i++) {
      final delayed = pre[pi];
      pre[pi] = mono[i];
      if (++pi >= preLen) pi = 0;
      final x = delayed * 0.03;
      var y = 0.0;
      for (final c in combs) {
        y += c.process(x);
      }
      for (final a in aps) {
        y = a.process(y);
      }
      out[i] = y * level * 6;
    }
  }
  if (t.size > 0) {
    // a few early reflections for small spaces
    final rnd = math.Random(3);
    for (var k = 0; k < 8; k++) {
      final p = ((0.003 + rnd.nextDouble() * 0.06 * t.size) * sr).round();
      final a = (0.5 - k * 0.04) * 0.5 * (rnd.nextBool() ? 1 : -1);
      for (var side = 0; side < 2; side++) {
        final off = p + side * 11;
        for (var i = 0; i + off < n; i++) {
          outs[side][i + off] += mono[i] * a * 0.4;
        }
      }
    }
  }
  return outs;
}

/// Feedback echo; returns the wet signal only.
Float32List echoWet(Float32List x, int sr, double timeMs, double fbPct, double toneHz) {
  final n = x.length, d = math.max(64, (timeMs / 1000 * sr).round());
  final buf = Float32List(d), wet = Float32List(n);
  final fb = (fbPct / 100).clamp(0.0, 0.92);
  final a = 1 - math.exp(-2 * math.pi * toneHz / sr);
  var idx = 0, lp = 0.0;
  for (var i = 0; i < n; i++) {
    final o = buf[idx];
    lp += a * (o - lp);
    wet[i] = lp;
    buf[idx] = x[i] + lp * fb;
    if (++idx >= d) idx = 0;
  }
  return wet;
}

/// Stereo chorus/doubler wet signal from a mono input.
List<Float32List> chorusWet(Float32List x, int sr, double depthPct, double rate) {
  final n = x.length;
  final outs = [Float32List(n), Float32List(n)];
  final maxD = (0.06 * sr).round();
  final buf = Float32List(maxD);
  var w = 0;
  final base = [0.020 * sr, 0.027 * sr];
  final mod = 0.0035 * sr * (depthPct / 50);
  for (var i = 0; i < n; i++) {
    buf[w] = x[i];
    for (var s = 0; s < 2; s++) {
      final lfo = math.sin(2 * math.pi * rate * (s == 1 ? 1.13 : 1) * i / sr + s * 1.7);
      final d = base[s] + mod * lfo;
      final p = w - d;
      var i0 = p.floor();
      final f = p - i0;
      i0 = ((i0 % maxD) + maxD) % maxD;
      final i1 = (i0 + 1) % maxD;
      outs[s][i] = buf[i0] * (1 - f) + buf[i1] * f;
    }
    if (++w >= maxD) w = 0;
  }
  return outs;
}

void ringMod(List<Float32List> chs, int sr, double hz) {
  final w = 2 * math.pi * hz / sr;
  for (final c in chs) {
    for (var i = 0; i < c.length; i++) {
      c[i] *= math.sin(w * i);
    }
  }
}
