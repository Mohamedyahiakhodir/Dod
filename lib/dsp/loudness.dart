import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm.dart';

class Loudness {
  const Loudness(this.lufs, this.peakDb);
  final double lufs; // -infinity when silent
  final double peakDb;
}

List<List<double>> _kCoefs(int fs) {
  const g = 3.999843853973347, q = 0.7071752369554196, fc = 1681.9744509555319;
  var k = math.tan(math.pi * fc / fs);
  final vh = math.pow(10, g / 20).toDouble(), vb = math.pow(vh, 0.4996667741545416).toDouble();
  var a0 = 1 + k / q + k * k;
  final shelf = [
    (vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
    2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0,
  ];
  const q2 = 0.5003270373253953, fc2 = 38.13547087613982;
  k = math.tan(math.pi * fc2 / fs);
  a0 = 1 + k / q2 + k * k;
  final hp = [1.0, -2.0, 1.0, 2 * (k * k - 1) / a0, (1 - k / q2 + k * k) / a0];
  return [shelf, hp];
}

Float32List _bq(Float32List x, List<double> c) {
  final y = Float32List(x.length);
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final yi = c[0] * xi + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2;
    x2 = x1; x1 = xi; y2 = y1; y1 = yi;
    y[i] = yi;
  }
  return y;
}

/// ITU-R BS.1770 integrated loudness (gated) and sample peak.
Loudness measureLoudness(Pcm p) {
  final n = p.length;
  final peakDb = gainToDbSafe(p.peak());
  final step = (p.sr * 0.1).round(), sub = n ~/ step;
  if (sub < 4) return Loudness(double.negativeInfinity, peakDb);
  final sums = Float64List(sub);
  final k = _kCoefs(p.sr);
  for (final c in p.ch) {
    final f = _bq(_bq(c, k[0]), k[1]);
    for (var b = 0; b < sub; b++) {
      var s = 0.0;
      for (var i = b * step, e = i + step; i < e; i++) {
        s += f[i] * f[i];
      }
      sums[b] += s;
    }
  }
  final blocks = <double>[];
  for (var b = 0; b + 4 <= sub; b++) {
    blocks.add((sums[b] + sums[b + 1] + sums[b + 2] + sums[b + 3]) / (4 * step));
  }
  double lk(double z) => -0.691 + 10 * math.log(z) / math.ln10;
  var g = blocks.where((z) => z > 0 && lk(z) > -70).toList();
  if (g.isEmpty) return Loudness(double.negativeInfinity, peakDb);
  final rel = lk(g.reduce((a, b) => a + b) / g.length) - 10;
  g = g.where((z) => lk(z) > rel).toList();
  if (g.isEmpty) return Loudness(double.negativeInfinity, peakDb);
  return Loudness(lk(g.reduce((a, b) => a + b) / g.length), peakDb);
}

double gainToDbSafe(double g) => 20 * math.log(math.max(g, 1e-9)) / math.ln10;

/// Rough noise floor: RMS (dBFS) of the quietest 10% of 50 ms windows.
double noiseFloorDb(Pcm p) {
  final w = (p.sr * 0.05).round(), n = p.length;
  final vals = <double>[];
  for (var i = 0; i + w <= n; i += w) {
    var s = 0.0;
    for (final c in p.ch) {
      for (var j = i; j < i + w; j++) {
        s += c[j] * c[j];
      }
    }
    vals.add(s / (w * p.channels));
  }
  if (vals.isEmpty) return -120;
  vals.sort();
  final k = math.max(1, (vals.length * 0.1).floor());
  var m = 0.0;
  for (var i = 0; i < k; i++) {
    m += vals[i];
  }
  return 10 * math.log(math.max(m / k, 1e-12)) / math.ln10;
}
