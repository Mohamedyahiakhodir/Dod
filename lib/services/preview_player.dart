import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Plays rendered previews (WAV bytes) with position tracking.
class PreviewPlayer {
  final AudioPlayer _p = AudioPlayer();
  int _n = 0;
  String? _lastFile;

  Stream<Duration> get positionStream => _p.createPositionStream(minPeriod: const Duration(milliseconds: 16), maxPeriod: const Duration(milliseconds: 40));
  Stream<bool> get playingStream => _p.playingStream;
  Stream<ProcessingState> get stateStream => _p.processingStateStream;
  bool get playing => _p.playing;
  Duration get position => _p.position;
  ProcessingState get state => _p.processingState;

  Future<void> load(Uint8List wav, {Duration position = Duration.zero}) async {
    if (kIsWeb) {
      await _p.setAudioSource(AudioSource.uri(Uri.dataFromBytes(wav, mimeType: 'audio/wav')), initialPosition: position);
      return;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/vs_preview_${_n++}.wav');
    await f.writeAsBytes(wav, flush: true);
    await _p.setFilePath(f.path, initialPosition: position);
    final old = _lastFile;
    _lastFile = f.path;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  Future<void> play() => _p.play();
  Future<void> pause() => _p.pause();
  Future<void> seek(Duration d) => _p.seek(d);
  Future<void> dispose() => _p.dispose();
}
