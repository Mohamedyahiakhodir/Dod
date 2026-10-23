import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 complex FFT.
class FFT {
  FFT(this.n) {
    final levels = (math.log(n) / math.ln2).round();
    rev = Uint32List(n);
    for (var i = 0; i < n; i++) {
      rev[i] = (rev[i >> 1] >> 1) | ((i & 1) << (levels - 1));
    }
    cosT = Float64List(n ~/ 2);
    sinT = Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      cosT[i] = math.cos(2 * math.pi * i / n);
      sinT[i] = math.sin(2 * math.pi * i / n);
    }
  }

  final int n;
  late final Uint32List rev;
  late final Float64List cosT, sinT;

  void transform(Float64List re, Float64List im, {bool inverse = false}) {
    for (var i = 0; i < n; i++) {
      final j = rev[i];
      if (j > i) {
        var t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1, step = n ~/ size;
      for (var i = 0; i < n; i += size) {
        var k = 0;
        for (var j = i; j < i + half; j++, k += step) {
          final wr = cosT[k], wi = inverse ? sinT[k] : -sinT[k], l = j + half;
          final tr = re[l] * wr - im[l] * wi, ti = re[l] * wi + im[l] * wr;
          re[l] = re[j] - tr; im[l] = im[j] - ti;
          re[j] += tr; im[j] += ti;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n; im[i] /= n;
      }
    }
  }
}
