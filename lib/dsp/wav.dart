import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm.dart';

/// Encode as RIFF/WAVE. [bits] is 16, 24 or 32 (IEEE float).
Uint8List encodeWav(Pcm p, {int bits = 16}) {
  final n = p.length, nc = p.channels, bps = bits ~/ 8;
  final dataLen = n * nc * bps;
  final out = Uint8List(44 + dataLen);
  final v = ByteData.view(out.buffer);
  void ws(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      v.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ws(0, 'RIFF');
  v.setUint32(4, 36 + dataLen, Endian.little);
  ws(8, 'WAVE');
  ws(12, 'fmt ');
  v.setUint32(16, 16, Endian.little);
  v.setUint16(20, bits == 32 ? 3 : 1, Endian.little);
  v.setUint16(22, nc, Endian.little);
  v.setUint32(24, p.sr, Endian.little);
  v.setUint32(28, p.sr * nc * bps, Endian.little);
  v.setUint16(32, nc * bps, Endian.little);
  v.setUint16(34, bits, Endian.little);
  ws(36, 'data');
  v.setUint32(40, dataLen, Endian.little);
  var o = 44;
  final rnd = math.Random(7);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < nc; c++) {
      var x = p.ch[c][i];
      if (bits == 32) {
        v.setFloat32(o, x, Endian.little);
        o += 4;
      } else if (bits == 24) {
        final s = (x.clamp(-1.0, 1.0) * 8388607).round();
        out[o] = s & 255;
        out[o + 1] = (s >> 8) & 255;
        out[o + 2] = (s >> 16) & 255;
        o += 3;
      } else {
        x += (rnd.nextDouble() - rnd.nextDouble()) / 32768; // TPDF dither
        v.setInt16(o, (x.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
        o += 2;
      }
    }
  }
  return out;
}

/// Decode PCM (8/16/24/32-bit) or float32 WAV data. Returns null if unsupported.
Pcm? decodeWav(Uint8List b) {
  if (b.length < 44) return null;
  final v = ByteData.view(b.buffer, b.offsetInBytes, b.length);
  String tag(int o) => String.fromCharCodes(b.sublist(o, o + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var pos = 12, fmt = 1, nc = 1, sr = 44100, bits = 16;
  int? dataOff, dataLen;
  while (pos + 8 <= b.length) {
    final id = tag(pos), size = v.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      fmt = v.getUint16(pos + 8, Endian.little);
      nc = v.getUint16(pos + 10, Endian.little);
      sr = v.getUint32(pos + 12, Endian.little);
      bits = v.getUint16(pos + 22, Endian.little);
      if (fmt == 0xFFFE && size >= 26) fmt = v.getUint16(pos + 32, Endian.little);
    } else if (id == 'data') {
      dataOff = pos + 8;
      dataLen = math.min(size, b.length - dataOff);
      break;
    }
    pos += 8 + size + (size & 1);
  }
  if (dataOff == null || dataLen == null || nc < 1) return null;
  final bps = bits ~/ 8, n = dataLen ~/ (bps * nc);
  final ch = [for (var c = 0; c < nc; c++) Float32List(n)];
  var o = dataOff;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < nc; c++) {
      double x;
      if (fmt == 3 && bits == 32) {
        x = v.getFloat32(o, Endian.little);
      } else if (bits == 16) {
        x = v.getInt16(o, Endian.little) / 32768;
      } else if (bits == 24) {
        var s = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
        if (s & 0x800000 != 0) s -= 0x1000000;
        x = s / 8388608;
      } else if (bits == 32) {
        x = v.getInt32(o, Endian.little) / 2147483648;
      } else if (bits == 8) {
        x = (b[o] - 128) / 128;
      } else {
        return null;
      }
      ch[c][i] = x;
      o += bps;
    }
  }
  return Pcm(ch, sr);
}

/// Convert interleaved little-endian signed 16-bit PCM into planar floats.
Pcm pcm16ToFloat(Uint8List bytes, int channels, int sr) {
  final n = bytes.length ~/ (2 * channels);
  final v = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  final ch = [for (var c = 0; c < channels; c++) Float32List(n)];
  var o = 0;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < channels; c++) {
      ch[c][i] = v.getInt16(o, Endian.little) / 32768;
      o += 2;
    }
  }
  return Pcm(ch, sr);
}
