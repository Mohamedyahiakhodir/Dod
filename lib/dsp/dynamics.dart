import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm.dart';

/// Feed-forward linked compressor with soft knee. Operates in place.
void compress(List<Float32List> chs, int sr,
    {required double threshold, required double ratio, required double attackMs, required double releaseMs, required double knee, required double makeupDb}) {
  final n = chs[0].length;
  final att = math.exp(-1 / (attackMs / 1000 * sr)), rel = math.exp(-1 / (releaseMs / 1000 * sr));
  var s = 0.0;
  const log10e = 0.4342944819032518;
  for (var i = 0; i < n; i++) {
    var m = 0.0;
    for (final c in chs) {
      final a = c[i].abs();
      if (a > m) m = a;
    }
    final l = 20 * math.log(m + 1e-9) * log10e;
    final d = l - threshold;
    double out;
    if (2 * d < -knee) {
      out = l;
    } else if (2 * d.abs() <= knee) {
      out = l + (1 / ratio - 1) * math.pow(d + knee / 2, 2) / (2 * knee);
    } else {
      out = threshold + d / ratio;
    }
    final gr = out - l; // <= 0
    s = gr < s ? att * s + (1 - att) * gr : rel * s + (1 - rel) * gr;
    final g = math.pow(10, (s + makeupDb) / 20).toDouble();
    for (final c in chs) {
      c[i] *= g;
    }
  }
}

/// Look-ahead peak limiter. Operates in place.
void limit(List<Float32List> chs, int sr, double ceilDb) {
  final c = dbToGain(ceilDb), n = chs[0].length, la = math.max(8, (sr * 0.002).round());
  final need = Float32List(n);
  var any = false;
  for (var i = 0; i < n; i++) {
    var m = 0.0;
    for (final ch in chs) {
      final a = ch[i].abs();
      if (a > m) m = a;
    }
    if (m > c) {
      need[i] = c / m;
      any = true;
    } else {
      need[i] = 1;
    }
  }
  if (!any) return;
  final gmin = Float32List(n);
  final dq = Int32List(n);
  var head = 0, tail = 0;
  for (var i = n - 1; i >= 0; i--) {
    while (tail > head && need[dq[tail - 1]] >= need[i]) {
      tail--;
    }
    dq[tail++] = i;
    while (dq[head] > i + la - 1) {
      head++;
    }
    gmin[i] = need[dq[head]];
  }
  final rel = 1 - math.exp(-1 / (0.08 * sr));
  var acc = 0.0, prev = 1.0;
  for (var i = 0; i < n; i++) {
    acc += gmin[i];
    if (i >= la) acc -= gmin[i - la];
    final avg = acc / math.min(i + 1, la);
    final g = math.min(avg, prev + (1 - prev) * rel);
    prev = g;
    for (final ch in chs) {
      ch[i] *= g;
    }
  }
}

void applyFades(List<Float32List> chs, int sr, double fadeIn, double fadeOut) {
  final n = chs[0].length, fi = (fadeIn * sr).round(), fo = (fadeOut * sr).round();
  for (final ch in chs) {
    for (var i = 0; i < math.min(fi, n); i++) {
      ch[i] *= i / fi;
    }
    for (var i = 0; i < math.min(fo, n); i++) {
      ch[n - 1 - i] *= i / fo;
    }
  }
}

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Soft saturation (tube-ish) with output compensation.
void saturate(List<Float32List> chs, double amount) {
  final k = 1 + (amount / 100) * 8, norm = 1 / _tanh(k), comp = dbToGain(-amount * 0.06);
  for (final c in chs) {
    for (var i = 0; i < c.length; i++) {
      c[i] = _tanh(k * c[i]) * norm * comp;
    }
  }
}
