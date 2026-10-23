import 'dart:math' as math;
import 'dart:typed_data';

enum BqType { lowpass, highpass, notch, peaking, lowshelf, highshelf }

/// RBJ cookbook biquad.
class Biquad {
  Biquad(BqType type, double f, double q, double gainDb, int sr) {
    f = f.clamp(10.0, sr * 0.49);
    final a = math.pow(10, gainDb / 40).toDouble();
    final w0 = 2 * math.pi * f / sr, cs = math.cos(w0), sn = math.sin(w0);
    final al = sn / (2 * q);
    double bb0, bb1, bb2, aa0, aa1, aa2;
    switch (type) {
      case BqType.lowpass:
        bb0 = (1 - cs) / 2; bb1 = 1 - cs; bb2 = (1 - cs) / 2;
        aa0 = 1 + al; aa1 = -2 * cs; aa2 = 1 - al;
      case BqType.highpass:
        bb0 = (1 + cs) / 2; bb1 = -(1 + cs); bb2 = (1 + cs) / 2;
        aa0 = 1 + al; aa1 = -2 * cs; aa2 = 1 - al;
      case BqType.notch:
        bb0 = 1; bb1 = -2 * cs; bb2 = 1;
        aa0 = 1 + al; aa1 = -2 * cs; aa2 = 1 - al;
      case BqType.peaking:
        bb0 = 1 + al * a; bb1 = -2 * cs; bb2 = 1 - al * a;
        aa0 = 1 + al / a; aa1 = -2 * cs; aa2 = 1 - al / a;
      case BqType.lowshelf:
        final s = 2 * math.sqrt(a) * al;
        bb0 = a * ((a + 1) - (a - 1) * cs + s);
        bb1 = 2 * a * ((a - 1) - (a + 1) * cs);
        bb2 = a * ((a + 1) - (a - 1) * cs - s);
        aa0 = (a + 1) + (a - 1) * cs + s;
        aa1 = -2 * ((a - 1) + (a + 1) * cs);
        aa2 = (a + 1) + (a - 1) * cs - s;
      case BqType.highshelf:
        final s = 2 * math.sqrt(a) * al;
        bb0 = a * ((a + 1) + (a - 1) * cs + s);
        bb1 = -2 * a * ((a - 1) + (a + 1) * cs);
        bb2 = a * ((a + 1) + (a - 1) * cs - s);
        aa0 = (a + 1) - (a - 1) * cs + s;
        aa1 = 2 * ((a - 1) - (a + 1) * cs);
        aa2 = (a + 1) - (a - 1) * cs - s;
    }
    b0 = bb0 / aa0; b1 = bb1 / aa0; b2 = bb2 / aa0; a1 = aa1 / aa0; a2 = aa2 / aa0;
  }

  late final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  void process(Float32List x) {
    var x1 = _x1, x2 = _x2, y1 = _y1, y2 = _y2;
    for (var i = 0; i < x.length; i++) {
      final xi = x[i];
      final y = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1; x1 = xi; y2 = y1; y1 = y;
      x[i] = y;
    }
    _x1 = x1; _x2 = x2; _y1 = y1; _y2 = y2;
  }

  /// Magnitude response in dB at [f] Hz.
  double responseDb(double f, int sr) {
    final w = 2 * math.pi * f / sr;
    final cw = math.cos(w), sw = math.sin(w), c2 = math.cos(2 * w), s2 = math.sin(2 * w);
    final nr = b0 + b1 * cw + b2 * c2, ni = -(b1 * sw + b2 * s2);
    final dr = 1 + a1 * cw + a2 * c2, di = -(a1 * sw + a2 * s2);
    final m = (nr * nr + ni * ni) / (dr * dr + di * di);
    return 10 * math.log(math.max(m, 1e-20)) / math.ln10;
  }
}
