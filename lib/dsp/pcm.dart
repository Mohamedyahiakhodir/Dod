import 'dart:math' as math;
import 'dart:typed_data';

/// Planar floating point audio (one [Float32List] per channel).
class Pcm {
  Pcm(this.ch, this.sr);

  final List<Float32List> ch;
  final int sr;

  int get length => ch.isEmpty ? 0 : ch[0].length;
  int get channels => ch.length;
  double get duration => length / sr;

  Pcm copy() => Pcm([for (final c in ch) Float32List.fromList(c)], sr);

  Pcm sliceSamples(int a, int b) {
    a = a.clamp(0, length);
    b = b.clamp(0, length);
    return Pcm([for (final c in ch) Float32List.sublistView(c, a, b).sublist(0)], sr);
  }

  static Pcm silence(int channels, int length, int sr) => Pcm([for (var i = 0; i < channels; i++) Float32List(length)], sr);

  double peak() {
    var m = 0.0;
    for (final c in ch) {
      for (var i = 0; i < c.length; i++) {
        final a = c[i].abs();
        if (a > m) m = a;
      }
    }
    return m;
  }
}

double dbToGain(double db) => math.pow(10, db / 20).toDouble();
double gainToDb(double g) => 20 * math.log(math.max(g, 1e-9)) / math.ln10;
