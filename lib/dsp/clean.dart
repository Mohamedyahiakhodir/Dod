import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'pcm.dart';

class CleanParams {
  const CleanParams({this.denoise = false, this.amount = 55, this.gate = false, this.gateDb = -45, this.gateRange = -30, this.deess = 0, this.profile});
  final bool denoise;
  final double amount;
  final bool gate;
  final double gateDb, gateRange, deess;
  final Float32List? profile;
}

class CleanJob {
  CleanJob(this.pcm, this.params);
  final Pcm pcm;
  final CleanParams params;
}

/// Spectral noise reduction + gate + de-esser (runs in an isolate).
Pcm runClean(CleanJob job) {
  final p = job.params;
  var chs = [for (final c in job.pcm.ch) Float32List.fromList(c)];
  final sr = job.pcm.sr;
  if (p.denoise) {
    final fft = FFT(2048);
    chs = [for (final c in chs) _denoise(c, sr, p.amount, p.profile, fft)];
  }
  if (p.gate) _gate(chs, sr, p.gateDb, p.gateRange);
  if (p.deess > 0) _deess(chs, sr, p.deess);
  return Pcm(chs, sr);
}

Float32List _denoise(Float32List x, int sr, double amount, Float32List? profile, FFT fft) {
  const n2 = 2048, hop = 512, bins = n2 ~/ 2 + 1;
  final n = x.length;
  final win = Float64List(n2);
  for (var i = 0; i < n2; i++) {
    win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n2);
  }
  final re = Float64List(n2), im = Float64List(n2);
  final noise = Float64List(bins);

  void analyse(Float32List src, int s) {
    for (var i = 0; i < n2; i++) {
      final idx = s + i;
      re[i] = idx >= 0 && idx < src.length ? src[idx] * win[i] : 0;
      im[i] = 0;
    }
    fft.transform(re, im);
  }

  if (profile != null && profile.length >= n2) {
    var cnt = 0;
    for (var s = 0; s + n2 <= profile.length; s += hop) {
      analyse(profile, s);
      for (var k = 0; k < bins; k++) {
        noise[k] += re[k] * re[k] + im[k] * im[k];
      }
      cnt++;
    }
    for (var k = 0; k < bins; k++) {
      noise[k] /= math.max(1, cnt);
    }
  } else {
    final energies = <double>[];
    for (var s = -n2 + hop; s < n; s += hop * 2) {
      var e = 0.0;
      for (var i = 0; i < n2; i++) {
        final idx = s + i;
        if (idx >= 0 && idx < n) e += x[idx] * x[idx];
      }
      energies.add(e);
    }
    final sorted = List<double>.from(energies)..sort();
    final thr = sorted.isEmpty ? 0.0 : sorted[math.max(0, (sorted.length * 0.12).floor() - 1)];
    var cnt = 0, idx = 0;
    for (var s = -n2 + hop; s < n; s += hop * 2, idx++) {
      if (energies[idx] > thr) continue;
      analyse(x, s);
      for (var k = 0; k < bins; k++) {
        noise[k] += re[k] * re[k] + im[k] * im[k];
      }
      cnt++;
    }
    for (var k = 0; k < bins; k++) {
      noise[k] /= math.max(1, cnt);
    }
  }
  final ns = Float64List(bins);
  for (var k = 0; k < bins; k++) {
    var s = 0.0, c = 0;
    for (var j = math.max(0, k - 3); j <= math.min(bins - 1, k + 3); j++) {
      s += noise[j];
      c++;
    }
    ns[k] = s / c;
  }

  final alpha = 1 + (amount / 100) * 2.2;
  final floor = math.pow(10, -(8 + (amount / 100) * 28) / 20).toDouble();
  final prev = Float64List(bins)..fillRange(0, bins, 1.0);
  final g = Float64List(bins);
  final out = Float32List(n);
  const scale = 1 / 1.5;
  for (var s = -n2 + hop; s < n; s += hop) {
    analyse(x, s);
    for (var k = 0; k < bins; k++) {
      final p = re[k] * re[k] + im[k] * im[k] + 1e-20;
      var v = math.sqrt(math.max((p - alpha * ns[k]) / p, floor * floor));
      v = 0.55 * v + 0.45 * prev[k];
      g[k] = v;
    }
    for (var k = 0; k < bins; k++) {
      final sm = 0.25 * g[math.max(0, k - 1)] + 0.5 * g[k] + 0.25 * g[math.min(bins - 1, k + 1)];
      prev[k] = g[k];
      re[k] *= sm;
      im[k] *= sm;
      if (k > 0 && k < n2 ~/ 2) {
        re[n2 - k] *= sm;
        im[n2 - k] *= sm;
      }
    }
    fft.transform(re, im, inverse: true);
    for (var i = 0; i < n2; i++) {
      final idx = s + i;
      if (idx >= 0 && idx < n) out[idx] += re[i] * win[i] * scale;
    }
  }
  return out;
}

void _gate(List<Float32List> chs, int sr, double db, double rangeDb) {
  final n = chs[0].length;
  final thr = math.pow(10, db / 20).toDouble(), floor = math.pow(10, rangeDb / 20).toDouble();
  final envRel = math.exp(-1 / (0.03 * sr)), gAtt = math.exp(-1 / (0.004 * sr)), gRel = math.exp(-1 / (0.08 * sr));
  final hold = (0.06 * sr).round(), look = (0.005 * sr).round();
  final g = Float32List(n);
  var env = 0.0, gs = 1.0, hc = 0;
  for (var i = 0; i < n; i++) {
    var p = 0.0;
    for (final c in chs) {
      final a = c[i].abs();
      if (a > p) p = a;
    }
    env = p > env ? p : env * envRel;
    var target = floor;
    if (env > thr) {
      target = 1;
      hc = hold;
    } else if (hc > 0) {
      hc--;
      target = 1;
    }
    gs = target + (gs - target) * (target > gs ? gAtt : gRel);
    g[i] = gs;
  }
  for (final c in chs) {
    for (var i = 0; i < n; i++) {
      c[i] *= g[math.min(n - 1, i + look)];
    }
  }
}

void _deess(List<Float32List> chs, int sr, double amount) {
  final n = chs[0].length;
  final w0 = 2 * math.pi * 5500 / sr, cs = math.cos(w0), al = math.sin(w0) / (2 * 0.707);
  final a0 = 1 + al, b0 = (1 + cs) / 2 / a0, b1 = -(1 + cs) / a0, b2 = b0, a1 = -2 * cs / a0, a2 = (1 - al) / a0;
  final att = math.exp(-1 / (0.001 * sr)), rel = math.exp(-1 / (0.03 * sr)), gsm = math.exp(-1 / (0.0008 * sr));
  for (final c in chs) {
    final hi = Float32List(n);
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0, sq = 0.0;
    for (var i = 0; i < n; i++) {
      final x = c[i];
      final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1; x1 = x; y2 = y1; y1 = y;
      hi[i] = y;
      sq += y * y;
    }
    final rms = math.sqrt(sq / n) + 1e-9, thr = rms * (3.2 - 2.4 * (amount / 100));
    var env = 0.0, gs = 1.0;
    for (var i = 0; i < n; i++) {
      final a = hi[i].abs();
      env = a > env ? a + (env - a) * att : a + (env - a) * rel;
      final target = env > thr ? math.pow(thr / env, 0.8).toDouble() : 1.0;
      gs = target + (gs - target) * gsm;
      c[i] -= hi[i] * (1 - gs);
    }
  }
}
