import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm.dart';

class StretchJob {
  StretchJob(this.pcm, this.tempo, this.semitones);
  final Pcm pcm;
  final double tempo, semitones;
}

/// Independent tempo / pitch change (WSOLA + resampling).
Pcm runStretch(StretchJob j) {
  final r = math.pow(2, j.semitones / 12).toDouble();
  var chs = j.pcm.ch;
  final rate = j.tempo / r;
  if ((rate - 1).abs() > 1e-4) chs = _wsola(chs, j.pcm.sr, rate);
  if ((r - 1).abs() > 1e-4) chs = [for (final c in chs) _resample(c, r)];
  return Pcm(chs, j.pcm.sr);
}

List<Float32List> _wsola(List<Float32List> chs, int sr, double rate) {
  final n = chs[0].length;
  final win = ((sr * 0.046) / 2).round() * 2, hs = win ~/ 2, tol = (sr * 0.012).round();
  const dec = 4;
  final w = Float32List(win);
  for (var i = 0; i < win; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / win);
  }
  final outLen = (n / rate).ceil() + win;
  final out = [for (final _ in chs) Float32List(outLen)];
  final mono = Float32List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (final c in chs) {
      s += c[i];
    }
    mono[i] = s / chs.length;
  }
  void place(int c0, int o0) {
    for (var ci = 0; ci < chs.length; ci++) {
      final src = chs[ci], dst = out[ci];
      for (var i = 0; i < win; i++) {
        final idx = c0 + i;
        if (idx < n) dst[o0 + i] += src[idx] * w[i];
      }
    }
  }

  place(0, 0);
  for (var ci = 0; ci < chs.length; ci++) {
    for (var i = 0; i < hs && i < n; i++) {
      out[ci][i] = chs[ci][i];
    }
  }
  var prev = 0;
  for (var k = 1;; k++) {
    final outPos = k * hs, target = (k * hs * rate).round();
    if (outPos + win > outLen || target >= n) break;
    final ref = prev + hs;
    var best = target;
    var bestC = -double.infinity;
    if (ref + hs <= n) {
      final lo = math.max(0, target - tol), hi = math.min(n - hs, target + tol);
      for (var c = lo; c <= hi; c += 2) {
        var s = 0.0, e = 1e-9;
        for (var j = 0; j < hs; j += dec) {
          final b = mono[c + j];
          s += mono[ref + j] * b;
          e += b * b;
        }
        final sc = s / math.sqrt(e);
        if (sc > bestC) {
          bestC = sc;
          best = c;
        }
      }
    }
    place(best, outPos);
    prev = best;
  }
  final finalLen = (n / rate).floor();
  return [for (final o in out) Float32List.sublistView(o, 0, math.min(finalLen, o.length)).sublist(0)];
}

Float32List _resample(Float32List x, double r) {
  final n = (x.length / r).floor(), len = x.length;
  final y = Float32List(n);
  for (var i = 0; i < n; i++) {
    final p = i * r;
    final i1 = p.floor();
    final f = p - i1;
    final p0 = x[math.max(0, i1 - 1)], p1 = x[i1], p2 = x[math.min(len - 1, i1 + 1)], p3 = x[math.min(len - 1, i1 + 2)];
    y[i] = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)));
  }
  return y;
}
