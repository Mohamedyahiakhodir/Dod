import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../dsp/wav.dart';
import '../models/fx.dart';
import '../models/project.dart';
import '../dsp/pcm.dart';

abstract class LibraryStore {
  Future<List<ProjectMeta>> list();
  Future<ProjectMeta?> meta(String id);
  Future<void> saveMeta(ProjectMeta m);
  Future<void> saveWav(String id, Uint8List wav);
  Future<Uint8List?> loadWav(String id);
  Future<void> delete(String id);

  static LibraryStore? _inst;
  static LibraryStore get instance => _inst ??= kIsWeb ? MemoryLibraryStore() : FileLibraryStore();
}

class MemoryLibraryStore extends LibraryStore {
  final _meta = <String, ProjectMeta>{};
  final _wav = <String, Uint8List>{};
  @override
  Future<List<ProjectMeta>> list() async => _meta.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
  @override
  Future<ProjectMeta?> meta(String id) async => _meta[id];
  @override
  Future<void> saveMeta(ProjectMeta m) async => _meta[m.id] = m;
  @override
  Future<void> saveWav(String id, Uint8List wav) async => _wav[id] = wav;
  @override
  Future<Uint8List?> loadWav(String id) async => _wav[id];
  @override
  Future<void> delete(String id) async {
    _meta.remove(id);
    _wav.remove(id);
  }
}

class FileLibraryStore extends LibraryStore {
  Directory? _dir;
  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/projects');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  @override
  Future<List<ProjectMeta>> list() async {
    final d = await _root();
    final out = <ProjectMeta>[];
    await for (final f in d.list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          out.add(ProjectMeta.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  @override
  Future<ProjectMeta?> meta(String id) async {
    final f = File('${(await _root()).path}/$id.json');
    if (!await f.exists()) return null;
    return ProjectMeta.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
  }

  @override
  Future<void> saveMeta(ProjectMeta m) async => File('${(await _root()).path}/${m.id}.json').writeAsString(jsonEncode(m.toJson()), flush: true);

  @override
  Future<void> saveWav(String id, Uint8List wav) async => File('${(await _root()).path}/$id.wav').writeAsBytes(wav, flush: true);

  @override
  Future<Uint8List?> loadWav(String id) async {
    final f = File('${(await _root()).path}/$id.wav');
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String id) async {
    final d = await _root();
    for (final ext in ['json', 'wav']) {
      final f = File('${d.path}/$id.$ext');
      if (await f.exists()) await f.delete();
    }
  }
}

Uint8List _encode16(Pcm p) => encodeWav(p, bits: 16);

class ProjectRepo {
  static final store = LibraryStore.instance;

  static Future<ProjectMeta> save(Project p) async {
    final wav = await compute(_encode16, p.pcm);
    final meta = ProjectMeta(
      id: p.id, name: p.name, created: p.created, updated: DateTime.now().millisecondsSinceEpoch,
      duration: p.pcm.duration, sr: p.pcm.sr, channels: p.pcm.channels, fx: p.fx, markers: p.markers, thumb: thumbOf(p.pcm),
    );
    await store.saveWav(p.id, wav);
    await store.saveMeta(meta);
    return meta;
  }

  static Future<Project?> open(String id) async {
    final m = await store.meta(id), wav = await store.loadWav(id);
    if (m == null || wav == null) return null;
    final pcm = decodeWav(wav);
    if (pcm == null) return null;
    return Project(id: m.id, name: m.name, created: m.created, pcm: pcm, fx: m.fx, markers: m.markers);
  }

  static Project fromPcm(Pcm pcm, String name, {List<Marker>? markers}) =>
      Project(id: Project.newId(), name: name, created: DateTime.now().millisecondsSinceEpoch, pcm: pcm, fx: FxSettings(), markers: markers);
}
