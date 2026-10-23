import 'dart:typed_data';

import 'package:flutter_lame/flutter_lame.dart';

import '../dsp/pcm.dart';

const mp3Supported = true;

Future<Uint8List> encodeMp3(Pcm p, int kbps, void Function(double) onProgress) async {
  final nc = p.channels > 1 ? 2 : 1;
  final enc = LameMp3Encoder(sampleRate: p.sr, numChannels: nc, bitRate: kbps);
  final out = BytesBuilder(copy: false);
  const block = 1152 * 40;
  Int16List toI16(Float32List c, int a, int b) {
    final o = Int16List(b - a);
    for (var i = a; i < b; i++) {
      o[i - a] = (c[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return o;
  }

  for (var i = 0; i < p.length; i += block) {
    final e = i + block > p.length ? p.length : i + block;
    final l = toI16(p.ch[0], i, e);
    final r = nc == 2 ? toI16(p.ch[1], i, e) : null;
    out.add(await enc.encode(leftChannel: l, rightChannel: r));
    onProgress(i / p.length);
  }
  out.add(await enc.flush());
  return out.takeBytes();
}
