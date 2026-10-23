import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm.dart';

int _ms(int sr, double s) => math.max(1, (sr * s).round());

Pcm cut(Pcm p, int a, int b) {
  final n = p.length;
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  if (b <= a) return p;
  final fm = _ms(p.sr, 0.003);
  return Pcm([
    for (final c in p.ch)
      () {
        final o = Float32List(n - (b - a));
        o.setRange(0, a, c);
        o.setRange(a, o.length, c, b);
        final fl = math.min(fm, a), fr = math.min(fm, o.length - a);
        for (var i = 0; i < fl; i++) {
          o[a - fl + i] *= 1 - (i + 1) / fl;
        }
        for (var i = 0; i < fr; i++) {
          o[a + i] *= (i + 1) / fr;
        }
        return o;
      }()
  ], p.sr);
}

Pcm keep(Pcm p, int a, int b) {
  final n = p.length;
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  if (b <= a) return p;
  final f = math.min(_ms(p.sr, 0.002), (b - a) >> 1);
  final o = p.sliceSamples(a, b);
  for (final c in o.ch) {
    for (var i = 0; i < f; i++) {
      c[i] *= i / f;
      c[c.length - 1 - i] *= i / f;
    }
  }
  return o;
}

Pcm silence(Pcm p, int a, int b) {
  final n = p.length;
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  final f = math.min(_ms(p.sr, 0.005), (b - a) >> 1);
  final o = p.copy();
  for (final c in o.ch) {
    for (var i = a; i < b; i++) {
      final d = math.min(i - a, b - 1 - i);
      c[i] *= d < f ? 1 - (d + 1) / f : 0;
    }
  }
  return o;
}

Pcm gainRegion(Pcm p, int a, int b, double db) {
  final n = p.length, g = dbToGain(db);
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  final f = math.min(_ms(p.sr, 0.01), (b - a) >> 1);
  final o = p.copy();
  for (final c in o.ch) {
    for (var i = a; i < b; i++) {
      final d = math.min(i - a, b - 1 - i);
      c[i] *= 1 + (g - 1) * (d < f ? d / f : 1);
    }
  }
  return o;
}

Pcm insertSilence(Pcm p, int at, double seconds) {
  final n = p.length, k = (seconds * p.sr).round();
  at = at.clamp(0, n);
  return Pcm([
    for (final c in p.ch)
      () {
        final o = Float32List(n + k);
        o.setRange(0, at, c);
        o.setRange(at + k, n + k, c, at);
        return o;
      }()
  ], p.sr);
}

Pcm reverseRegion(Pcm p, int a, int b) {
  final n = p.length;
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  final o = p.copy();
  for (var ci = 0; ci < o.channels; ci++) {
    for (var i = a, j = b - 1; i < b; i++, j--) {
      o.ch[ci][i] = p.ch[ci][j];
    }
  }
  return o;
}

Pcm paste(Pcm p, int at, Pcm clip) {
  final n = p.length, k = clip.length;
  at = at.clamp(0, n);
  final f = math.min(_ms(p.sr, 0.002), k >> 1);
  return Pcm([
    for (var ci = 0; ci < p.channels; ci++)
      () {
        final src = ci < clip.channels ? clip.ch[ci] : clip.ch[0];
        final o = Float32List(n + k);
        o.setRange(0, at, p.ch[ci]);
        o.setRange(at, at + k, src);
        o.setRange(at + k, n + k, p.ch[ci], at);
        for (var i = 0; i < f; i++) {
          o[at + i] *= i / f;
          o[at + k - 1 - i] *= i / f;
        }
        return o;
      }()
  ], p.sr);
}

Pcm append(Pcm p, Pcm other) => paste(p, p.length, other);

Pcm fadeRegion(Pcm p, int a, int b, {required bool fadeIn}) {
  final n = p.length;
  a = a.clamp(0, n);
  b = b.clamp(0, n);
  final m = b - a;
  if (m < 2) return p;
  final o = p.copy();
  for (final c in o.ch) {
    for (var i = 0; i < m; i++) {
      c[a + i] *= fadeIn ? i / m : 1 - i / m;
    }
  }
  return o;
}

class SilenceResult {
  SilenceResult(this.pcm, this.removed, this.map);
  final Pcm pcm;
  final double removed;
  final double Function(double) map;
}

SilenceResult removeSilences(Pcm p, {double thDb = -45, double minMs = 400, double padMs = 120}) {
  final n = p.length, sr = p.sr, w = (sr * 0.01).round(), th = dbToGain(thDb);
  final nw = n ~/ w;
  final quiet = Uint8List(nw);
  for (var k = 0; k < nw; k++) {
    var s = 0.0;
    for (final c in p.ch) {
      for (var i = k * w; i < (k + 1) * w; i++) {
        s += c[i] * c[i];
      }
    }
    quiet[k] = math.sqrt(s / (w * p.channels)) < th ? 1 : 0;
  }
  final minW = (minMs / 10).round(), padW = (padMs / 10).round();
  final ranges = <List<int>>[];
  var cur = 0;
  for (var k = 0; k <= nw; k++) {
    if (k == nw || quiet[k] == 0) continue;
    var e = k;
    while (e < nw && quiet[e] == 1) {
      e++;
    }
    if (e - k >= minW) {
      final cutA = (k + (k == 0 ? 0 : padW)) * w, cutB = (e - (e == nw ? 0 : padW)) * w;
      if (cutB > cutA) {
        ranges.add([cur, cutA]);
        cur = cutB;
      }
    }
    k = e - 1;
  }
  ranges.add([cur, n]);
  final total = ranges.fold<int>(0, (s, r) => s + r[1] - r[0]);
  if (total >= n) return SilenceResult(p, 0, (t) => t);
  final f = _ms(sr, 0.003);
  final out = Pcm([
    for (final c in p.ch)
      () {
        final o = Float32List(total);
        var pos = 0;
        for (var idx = 0; idx < ranges.length; idx++) {
          final a = ranges[idx][0], b = ranges[idx][1], m = b - a;
          o.setRange(pos, pos + m, c, a);
          final ff = math.min(f, m >> 1);
          if (idx > 0) {
            for (var i = 0; i < ff; i++) {
              o[pos + i] *= i / ff;
            }
          }
          if (idx < ranges.length - 1) {
            for (var i = 0; i < ff; i++) {
              o[pos + m - 1 - i] *= i / ff;
            }
          }
          pos += m;
        }
        return o;
      }()
  ], sr);
  double map(double t) {
    final x = t * sr;
    var acc = 0;
    for (final r in ranges) {
      if (x < r[0]) return acc / sr;
      if (x <= r[1]) return (acc + x - r[0]) / sr;
      acc += r[1] - r[0];
    }
    return acc / sr;
  }

  return SilenceResult(out, (n - total) / sr, map);
}
