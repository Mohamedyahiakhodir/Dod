import 'dart:typed_data';

import '../dsp/pcm.dart';

const mp3Supported = false;

Future<Uint8List> encodeMp3(Pcm p, int kbps, void Function(double) onProgress) async => throw UnsupportedError('MP3 is not available on this platform');
