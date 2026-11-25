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
  // Web results are deliberately separate from the local library.  A result
  // becomes durable only as Home state (recent/favorite), never merely because
  // it was displayed in a search.
  final Map<String, MemeAsset> _recentAssets = {};
  final Map<String, MemeAsset> _favoriteWebAssets = {};
  final List<String> _recent = [];
  final List<String> _recentSearches = [];
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
      if (recent is List) _recent.addAll(recent.whereType<String>());
      final recentAssets = decoded['recentAssets'];
      if (recentAssets is List) {
        for (final item in recentAssets.whereType<Map>()) {
          final asset = MemeAsset.fromJson(Map<String, Object?>.from(item));
          if (asset.id.isNotEmpty && asset.isWeb) {
            _recentAssets[asset.id] = asset;
          }
        }
      }
      // Older indexes only have local IDs in `recent`; retain that behavior,
      // while newer indexes may point to a persisted web result as well.
      _recent.removeWhere(
        (id) => !_assets.containsKey(id) && !_recentAssets.containsKey(id),
      );
      final favoriteWebAssets = decoded['favoriteWebAssets'];
      if (favoriteWebAssets is List) {
        for (final item in favoriteWebAssets.whereType<Map>()) {
          final asset = MemeAsset.fromJson(Map<String, Object?>.from(item));
          if (asset.id.isNotEmpty && asset.isWeb && asset.favorite) {
            _favoriteWebAssets[asset.id] = asset;
          }
        }
      }
      final searches = decoded['recentSearches'];
      if (searches is List) {
        final seen = <String>{};
        for (final raw in searches.whereType<String>()) {
          final query = raw.trim();
          if (query.isNotEmpty && seen.add(_searchKey(query))) {
            _recentSearches.add(query);
          }
        }
        if (_recentSearches.length > 5)
          _recentSearches.removeRange(5, _recentSearches.length);
      }
      _pruneRecentAssets();
    } catch (_) {
      // A corrupt local index must not prevent the app opening.
    }
  }

  List<MemeAsset> all() => _assets.values.toList(growable: false);
  MemeAsset? byId(String id) => _assets[id];
  MemeAsset? trackedById(String id) =>
      _assets[id] ?? _favoriteWebAssets[id] ?? _recentAssets[id];

  List<MemeAsset> recentAssets() => _recent
      .map((id) => _assets[id] ?? _recentAssets[id] ?? _favoriteWebAssets[id])
      .whereType<MemeAsset>()
      .toList(growable: false);

  List<MemeAsset> favorites() {
    final values = <String, MemeAsset>{
      for (final asset in _assets.values.where((asset) => asset.favorite))
        asset.id: asset,
      ..._favoriteWebAssets,
    };
    return values.values.toList(growable: false);
  }

  Future<void> upsert(MemeAsset asset) async {
    _assets[asset.id] = asset;
    await _write();
  }

  Future<void> upsertAll(Iterable<MemeAsset> assets) async {
    for (final asset in assets) _assets[asset.id] = asset;
    await _write();
  }

  Future<void> recent(String id, {MemeAsset? asset}) async {
    if (!_assets.containsKey(id) && asset != null && asset.isWeb) {
      final favorite = _favoriteWebAssets[id];
      final existing = _recentAssets[id];
      _recentAssets[id] = _mergeWebSnapshot(
        asset,
        existing ?? favorite,
        favorite: favorite?.favorite ?? existing?.favorite ?? asset.favorite,
      );
    }
    if (!_assets.containsKey(id) && !_recentAssets.containsKey(id)) return;
    _recent.remove(id);
    _recent.insert(0, id);
    if (_recent.length > 100) _recent.removeRange(100, _recent.length);
    _pruneRecentAssets();
    await _write();
  }

  List<String> get recentIds => List.unmodifiable(_recent);

  Future<void> refreshRecentAsset(MemeAsset asset) async {
    if (!asset.isWeb || !_recent.contains(asset.id)) return;
    final existing = _recentAssets[asset.id];
    final favorite = _favoriteWebAssets[asset.id];
    final updated = _mergeWebSnapshot(
      asset,
      existing ?? favorite,
      favorite: favorite?.favorite ?? existing?.favorite ?? asset.favorite,
    );
    _recentAssets[asset.id] = updated;
    if (favorite != null)
      _favoriteWebAssets[asset.id] = updated.copyWith(favorite: true);
    await _write();
  }

  Future<MemeAsset> toggleFavorite(String id, {MemeAsset? asset}) async {
    final local = _assets[id];
    if (local != null) {
      final updated = local.copyWith(favorite: !local.favorite);
      _assets[id] = updated;
      await _write();
      return updated;
    }
    final current = _favoriteWebAssets[id] ?? _recentAssets[id] ?? asset;
    if (current == null || !current.isWeb) throw StateError('Unknown asset.');
    final updated = current.copyWith(favorite: !current.favorite);
    if (updated.favorite) {
      _favoriteWebAssets[id] = updated;
    } else {
      _favoriteWebAssets.remove(id);
    }
    if (_recentAssets.containsKey(id)) _recentAssets[id] = updated;
    _pruneRecentAssets();
    await _write();
    return updated;
  }

  MemeAsset applyStoredState(MemeAsset asset) {
    final stored = trackedById(asset.id);
    return stored == null ? asset : asset.copyWith(favorite: stored.favorite);
  }

  Future<void> recordSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final key = _searchKey(normalized);
    _recentSearches.removeWhere((existing) => _searchKey(existing) == key);
    _recentSearches.insert(0, normalized);
    if (_recentSearches.length > 5) {
      _recentSearches.removeRange(5, _recentSearches.length);
    }
    await _write();
  }

  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  static String _searchKey(String value) => value.trim().toLowerCase();

  static MemeAsset _mergeWebSnapshot(
    MemeAsset fresh,
    MemeAsset? persisted, {
    required bool favorite,
  }) => fresh.copyWith(
    filePath: fresh.filePath ?? persisted?.filePath,
    format: fresh.format ?? persisted?.format,
    mime: fresh.mime ?? persisted?.mime,
    width: fresh.width ?? persisted?.width,
    height: fresh.height ?? persisted?.height,
    frames: fresh.frames ?? persisted?.frames,
    animated: fresh.animated || (persisted?.animated ?? false),
    motionVerified:
        fresh.motionVerified || (persisted?.motionVerified ?? false),
    verified: fresh.verified || (persisted?.verified ?? false),
    inspectionStatus: fresh.verified
        ? fresh.inspectionStatus
        : persisted?.inspectionStatus ?? fresh.inspectionStatus,
    inspectionReason: fresh.inspectionReason ?? persisted?.inspectionReason,
    favorite: favorite,
  );

  void _pruneRecentAssets() {
    _recentAssets.removeWhere(
      (id, _) => !_recent.contains(id) && !_favoriteWebAssets.containsKey(id),
    );
  }

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
    // A transient I/O failure must fail its caller, but cannot leave the
    // serialized queue permanently failed: Home history should recover on the
    // next user action.
    final next = _writeQueue.then<void>(
      (_) => _writeAtomically(),
      onError: (Object _, StackTrace _) => _writeAtomically(),
    );
    _writeQueue = next;
    return next;
  }

  Future<void> _writeAtomically() async {
    final target = File(p.join(_directory.path, 'library.json'));
    final temp = File(
      p.join(
        _directory.path,
        'library.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    final data = jsonEncode({
      'version': 1,
      'assets': _assets.values.map((asset) => asset.toJson()).toList(),
      'recent': _recent,
      'recentAssets': _recentAssets.values
          .map((asset) => asset.toJson())
          .toList(),
      'favoriteWebAssets': _favoriteWebAssets.values
          .map((asset) => asset.toJson())
          .toList(),
      'recentSearches': _recentSearches,
    });
    await temp.writeAsString(data, flush: true);
    // rename is an atomic replacement on supported app filesystems; never
    // delete the old index first, since a crash must leave it recoverable.
    await temp.rename(target.path);
  }
}
