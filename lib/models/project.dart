import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/pcm.dart';
import 'fx.dart';

class Marker {
  Marker(this.t, this.name);
  double t;
  String name;
  Map<String, dynamic> toJson() => {'t': t, 'name': name};
  factory Marker.fromJson(Map<String, dynamic> j) => Marker((j['t'] as num).toDouble(), (j['name'] as String?) ?? '');
}

class ProjectMeta {
  ProjectMeta({
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    required this.duration,
    required this.sr,
    required this.channels,
    required this.fx,
    required this.markers,
    required this.thumb,
  });

  String id, name;
  int created, updated, sr, channels;
  double duration;
  FxSettings fx;
  List<Marker> markers;
  List<double> thumb;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'created': created, 'updated': updated, 'duration': duration, 'sr': sr, 'channels': channels,
        'fx': fx.toJson(), 'markers': [for (final m in markers) m.toJson()], 'thumb': thumb,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> j) => ProjectMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        created: (j['created'] as num).toInt(),
        updated: (j['updated'] as num).toInt(),
        duration: (j['duration'] as num).toDouble(),
        sr: (j['sr'] as num).toInt(),
        channels: (j['channels'] as num).toInt(),
        fx: FxSettings.fromJson((j['fx'] as Map?)?.cast<String, dynamic>()),
        markers: [for (final m in (j['markers'] as List? ?? [])) Marker.fromJson((m as Map).cast<String, dynamic>())],
        thumb: [for (final v in (j['thumb'] as List? ?? [])) (v as num).toDouble()],
      );
}

/// An open project (audio lives in memory while editing).
class Project {
  Project({required this.id, required this.name, required this.created, required this.pcm, FxSettings? fx, List<Marker>? markers})
      : fx = fx ?? FxSettings(),
        markers = markers ?? [];

  String id, name;
  int created;
  Pcm pcm;
  FxSettings fx;
  List<Marker> markers;

  static String newId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36) + math.Random().nextInt(1 << 20).toRadixString(36);
}

List<double> thumbOf(Pcm p, {int bars = 90}) {
  final n = p.length, step = math.max(1, n ~/ bars);
  final out = <double>[];
  for (var b = 0; b < bars; b++) {
    var m = 0.0;
    final s = b * step, e = math.min(n, s + step), stride = math.max(1, step >> 6);
    for (var i = s; i < e; i += stride) {
      for (final c in p.ch) {
        final a = c[i].abs();
        if (a > m) m = a;
      }
    }
    out.add((math.sqrt(math.min(1.0, m)) * 100).roundToDouble() / 100);
  }
  return out;
}

Uint8List noBytes() => Uint8List(0);
