// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Small JSON repository. Media is copied into app support, never into the
/// project or cache directory, so it remains available across launches.
class LocalLibraryStore {
  LocalLibraryStore._(this._directory);

  final Directory _directory;
  final Map<String, MemeAsset> _assets = {};
  final List<String> _recent = [];
  Future<void> _writeQueue = Future.value();

  static Future<LocalLibraryStore> open({Directory? directory}) async {
    final root = directory ?? await getApplicationSupportDirectory();
    final store = LocalLibraryStore._(
      Directory(p.join(root.path, 'meme_drawer')),
    );
    await store._load();
    return store;
  }

  Future<void> _load() async {
    await _directory.create(recursive: true);
    final file = File(p.join(_directory.path, 'library.json'));
    if (!await file.exists()) return;
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final assets = decoded['assets'];
      if (assets is List) {
        for (final item in assets.whereType<Map>()) {
          final asset = MemeAsset.fromJson(Map<String, Object?>.from(item));
          if (asset.id.isNotEmpty) _assets[asset.id] = asset;
        }
      }
      final recent = decoded['recent'];
      if (recent is List)
        _recent.addAll(recent.whereType<String>().where(_assets.containsKey));
    } catch (_) {
      // A corrupt local index must not prevent the app opening.
    }
  }

  List<MemeAsset> all() => _assets.values.toList(growable: false);
  MemeAsset? byId(String id) => _assets[id];

  Future<void> upsert(MemeAsset asset) async {
    _assets[asset.id] = asset;
    await _write();
  }

  Future<void> upsertAll(Iterable<MemeAsset> assets) async {
    for (final asset in assets) _assets[asset.id] = asset;
    await _write();
  }

  Future<void> recent(String id) async {
    _recent.remove(id);
    _recent.insert(0, id);
    if (_recent.length > 100) _recent.removeRange(100, _recent.length);
    await _write();
  }

  List<String> get recentIds => List.unmodifiable(_recent);

  Future<String> persistBytes(List<int> bytes, String extension) async {
    final digest = sha256.convert(bytes).toString();
    final ext = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
    final media = Directory(p.join(_directory.path, 'media'));
    await media.create(recursive: true);
    final output = File(
      p.join(media.path, '$digest.${ext.isEmpty ? 'bin' : ext}'),
    );
    if (!await output.exists()) await output.writeAsBytes(bytes, flush: true);
    return output.path;
  }

  Future<void> _write() async {
    _writeQueue = _writeQueue.then((_) => _writeAtomically());
    return _writeQueue;
  }

  Future<void> _writeAtomically() async {
    final target = File(p.join(_directory.path, 'library.json'));
    final temp = File(p.join(_directory.path, 'library.${DateTime.now().microsecondsSinceEpoch}.tmp'));
    final data = jsonEncode({
      'version': 1,
      'assets': _assets.values.map((asset) => asset.toJson()).toList(),
      'recent': _recent,
    });
    await temp.writeAsString(data, flush: true);
    // rename is an atomic replacement on supported app filesystems; never
    // delete the old index first, since a crash must leave it recoverable.
    await temp.rename(target.path);
  }
}
