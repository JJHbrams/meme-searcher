// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// A durable user library and a separately evictable, content-addressed cache.
class LocalLibraryStore {
  LocalLibraryStore._(
    this._directory,
    this.cacheLimitBytes,
    this._bundledDigests,
  );
  static const defaultCacheLimitBytes = 256 * 1024 * 1024;
  final Directory _directory;
  final int cacheLimitBytes;

  /// Seed id -> lowercase SHA-256.  This is metadata, not a path into the
  /// bundle, so migration never touches files outside this drawer.
  final Map<String, String> _bundledDigests;
  final Map<String, MemeAsset> _assets = {};
  final Map<String, MemeAsset> _recentAssets = {};
  final Map<String, MemeAsset> _favoriteWebAssets = {};
  final Map<String, _CacheRecord> _cache = {};
  final List<String> _recent = [];
  final List<String> _recentSearches = [];
  final Map<String, int> _pendingCopies = {};
  final Set<String> _discardableCopies = {};
  Future<void> _queue = Future.value();
  Directory get _media => Directory(p.join(_directory.path, 'media'));
  Directory get _cacheDir => Directory(p.join(_directory.path, 'cache'));
  File get _index => File(p.join(_directory.path, 'library.json'));

  static Future<LocalLibraryStore> open({
    Directory? directory,
    int cacheLimitBytes = defaultCacheLimitBytes,
    Map<String, String> bundledDigests = const {},
  }) async {
    final root = directory ?? await getApplicationSupportDirectory();
    final result = LocalLibraryStore._(
      Directory(p.join(root.path, 'meme_drawer')),
      cacheLimitBytes < 0 ? 0 : cacheLimitBytes,
      Map.unmodifiable({
        for (final entry in bundledDigests.entries)
          if (_digest(entry.value)) entry.key: entry.value,
      }),
    );
    await result._load();
    return result;
  }

  Future<void> _load() async {
    await _directory.create(recursive: true);
    await _media.create(recursive: true);
    await _cacheDir.create(recursive: true);
    var legacy = true;
    if (await _index.exists()) {
      late Map<String, dynamic> data;
      try {
        data = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
        final version = data['version'] ?? 1;
        if (version is! int || version < 1 || data['assets'] is! List) {
          throw const FormatException('Invalid drawer index');
        }
        if (version > 2) throw StateError('Newer drawer index');
        legacy = version == 1;
        _readIndex(data);
      } on FileSystemException {
        rethrow;
      } on StateError {
        rethrow;
      } catch (_) {
        // Keep the original index and every media file for recovery. Do not
        // classify unreferenced media as disposable after an index failure.
        await _index.rename(
          '${_index.path}.${DateTime.now().microsecondsSinceEpoch}.corrupt',
        );
        _assets.clear();
        _cache.clear();
        _recentAssets.clear();
        _favoriteWebAssets.clear();
        _recent.clear();
        _recentSearches.clear();
        await _write();
        return;
      }
    }
    // Even an empty v1 index is upgraded only after the complete scan has
    // succeeded; this prevents repeating a partial migration on every launch.
    var changed = legacy;
    if (legacy) changed = await _migrateLegacyMedia() || changed;
    changed = await _reconcileCacheFiles() || changed;
    final beforePrune = _cache.length;
    _cache.removeWhere(
      (_, r) =>
          r.asset.filePath == null || !File(r.asset.filePath!).existsSync(),
    );
    await _evict();
    // The original index remains intact until every migration scan completed.
    // A crash after an individual rename is recovered by _reconcileCacheFiles.
    if (changed || beforePrune != _cache.length) await _write();
  }

  void _readIndex(Map<String, dynamic> data) {
    void read(Object? value, Map<String, MemeAsset> into, {bool web = false}) {
      if (value is! List) return;
      for (final raw in value.whereType<Map>()) {
        final asset = MemeAsset.fromJson(Map<String, Object?>.from(raw));
        if (asset.id.isNotEmpty &&
            (!web || asset.isWeb || asset.origin == 'cache'))
          into[asset.id] = asset;
      }
    }

    read(data['assets'], _assets);
    read(data['recentAssets'], _recentAssets, web: true);
    read(data['favoriteWebAssets'], _favoriteWebAssets, web: true);
    if (data['recent'] is List)
      _recent.addAll((data['recent'] as List).whereType<String>());
    _recent.removeWhere(
      (id) => !_assets.containsKey(id) && !_recentAssets.containsKey(id),
    );
    if (data['recentSearches'] is List) {
      final seen = <String>{};
      for (final raw in (data['recentSearches'] as List).whereType<String>()) {
        final s = raw.trim();
        if (s.isNotEmpty && seen.add(_key(s))) _recentSearches.add(s);
      }
      if (_recentSearches.length > 5)
        _recentSearches.removeRange(5, _recentSearches.length);
    }
    if (data['cacheAssets'] is List)
      for (final raw in (data['cacheAssets'] as List).whereType<Map>()) {
        final m = Map<String, Object?>.from(raw);
        final digest = m['digest'] as String?;
        final value = m['asset'];
        if (digest == null || !_digest(digest) || value is! Map) continue;
        final asset = MemeAsset.fromJson(Map<String, Object?>.from(value));
        final expected = File(
          p.join(_cacheDir.path, p.basename(asset.filePath ?? '')),
        );
        if (asset.origin == 'cache' &&
            asset.filePath != null &&
            _inside(asset.filePath!, _cacheDir) &&
            _name(expected.path)?.$1 == digest &&
            expected.existsSync()) {
          final actualSize = expected.lengthSync();
          _cache[digest] = _CacheRecord(
            asset.copyWith(filePath: expected.path, bytes: actualSize),
            actualSize,
            DateTime.tryParse(m['lastAccessed'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );
        }
      }
    _pruneRecent();
  }

  /// Move only the prior release's managed files. The v1 index stays on disk
  /// until the move and reconciliation finish, so an interrupted run can retry.
  Future<bool> _migrateLegacyMedia() async {
    final protected = _assets.values
        .map((asset) => asset.filePath)
        .whereType<String>()
        .toList();
    await for (final file in _media.list(followLinks: false)) {
      if (file is! File || protected.any((path) => p.equals(path, file.path)))
        continue;
      final name = _name(file.path);
      if (name == null) continue;
      final digest = name.$1;
      final existing = _permanentByDigest(digest);
      if (existing != null) {
        _assets[existing.id] = existing.copyWith(filePath: file.path);
        continue;
      }
      if (_bundledDigests.containsValue(digest)) continue;
      final target = File(p.join(_cacheDir.path, p.basename(file.path)));
      if (!await target.exists()) {
        await file.rename(target.path);
      } else {
        // An interrupted earlier migration may have left both copies.
        if (await file.length() != await target.length() ||
            await sha256.bind(target.openRead()).first !=
                await sha256.bind(file.openRead()).first) {
          throw const FileSystemException(
            'Conflicting files in the drawer migration',
          );
        }
        await file.delete();
      }
    }
    return true;
  }

  Future<bool> _reconcileCacheFiles() async {
    var changed = false;
    await for (final file in _cacheDir.list(followLinks: false)) {
      if (file is! File) continue;
      final name = _name(file.path);
      if (name == null) continue;
      final digest = name.$1;
      final stat = await file.stat();
      final old = _cache[digest];
      if (_permanentByDigest(digest) != null ||
          _bundledDigests.containsValue(digest)) {
        // A promotion can finish its index write before it removes the cache copy.
        final durable = File(p.join(_media.path, p.basename(file.path)));
        if (await durable.exists()) {
          if (await durable.length() == stat.size) await file.delete();
        } else {
          await file.rename(durable.path);
        }
        final saved = _permanentByDigest(digest);
        if (saved != null)
          _assets[saved.id] = saved.copyWith(filePath: durable.path);
        _cache.remove(digest);
        changed = true;
        continue;
      }
      if (old != null &&
          p.equals(old.asset.filePath!, file.path) &&
          old.size == stat.size)
        continue;
      final snapshot = old?.asset ?? _snapshotForLegacyHash(digest);
      final format = knownImageFormat(name.$2) ?? name.$2.toUpperCase();
      final recovered =
          snapshot ??
          MemeAsset(
            id: 'cache:$digest',
            origin: 'cache',
            format: format,
            title: '이전 $format 짤 · ${digest.substring(0, 8)}',
          );
      _cache[digest] = _CacheRecord(
        recovered.copyWith(
          id: 'cache:$digest',
          origin: 'cache',
          filePath: file.path,
          bytes: stat.size,
          addedAt: recovered.addedAt ?? stat.modified,
        ),
        stat.size,
        old?.access ?? stat.modified,
      );
      _updateSnapshotsForMovedFile(
        p.join(_media.path, p.basename(file.path)),
        file.path,
      );
      changed = true;
    }
    return changed;
  }

  MemeAsset? _snapshotForLegacyHash(String digest) {
    final prefix = 'cache:$digest';
    for (final asset in [
      ..._recentAssets.values,
      ..._favoriteWebAssets.values,
    ]) {
      final path = asset.filePath;
      if (path != null && (_name(path)?.$1 == digest || asset.id == prefix))
        return asset;
    }
    return null;
  }

  void _updateSnapshotsForMovedFile(String oldPath, String newPath) {
    void update(Map<String, MemeAsset> assets) {
      for (final entry in assets.entries.toList()) {
        if (p.normalize(entry.value.filePath ?? '') == p.normalize(oldPath)) {
          assets[entry.key] = entry.value.copyWith(filePath: newPath);
        }
      }
    }

    update(_recentAssets);
    update(_favoriteWebAssets);
  }

  List<MemeAsset> all() => _assets.values.toList(growable: false);
  Iterable<MemeAsset> filesForUrl(
    String url, {
    required bool previewOnly,
  }) sync* {
    final files = _assets.values.followedBy(
      _cache.values.map((record) => record.asset),
    );
    for (final item in files) {
      final address = previewOnly ? item.previewUrl : item.originalUrl;
      if (item.isPreviewOnly == previewOnly &&
          item.filePath != null &&
          address == url)
        yield item;
    }
  }

  MemeAsset? byId(String id) => _assets[id];
  MemeAsset? trackedById(String id) =>
      _assets[id] ?? _favoriteWebAssets[id] ?? _recentAssets[id];

  List<MemeAsset> cachedAssets() {
    final entries = _cache.values.toList()
      ..sort((a, b) => b.access.compareTo(a.access));
    return entries
        .map((entry) => applyStoredState(entry.asset))
        .toList(growable: false);
  }

  List<MemeAsset> recentAssets() =>
      _recent.map(trackedById).whereType<MemeAsset>().toList(growable: false);
  List<MemeAsset> favorites() => [
    ..._assets.values.where((asset) => asset.favorite),
    ..._favoriteWebAssets.values,
  ];

  Future<void> upsert(MemeAsset asset) => _mutate(() {
    _assets[asset.id] = asset;
  });
  Future<void> upsertAll(Iterable<MemeAsset> assets) => _mutate(() {
    for (final asset in assets) {
      _assets[asset.id] = asset;
    }
  });

  String? _storedId(Map<String, MemeAsset> assets, MemeAsset asset) {
    if (assets.containsKey(asset.id)) return asset.id;
    final source = asset.isPreviewOnly ? asset.previewUrl : asset.originalUrl;
    final digest = asset.filePath == null ? null : _name(asset.filePath!)?.$1;
    for (final same in assets.values) {
      if (same.isPreviewOnly != asset.isPreviewOnly) continue;
      if (digest != null && (same.id == digest || same.id == 'cache:$digest'))
        return same.id;
      if (source != null &&
          source.isNotEmpty &&
          source == (same.isPreviewOnly ? same.previewUrl : same.originalUrl))
        return same.id;
    }
    return null;
  }

  Future<void> recent(String id, {MemeAsset? asset}) => _mutate(() {
    var key = id;
    if (asset != null && (asset.isWeb || asset.origin == 'cache')) {
      key =
          _storedId(_assets, asset) ??
          _storedId(_favoriteWebAssets, asset) ??
          _storedId(_recentAssets, asset) ??
          id;
      if (!_assets.containsKey(key)) {
        final previous = _favoriteWebAssets[key] ?? _recentAssets[key];
        _recentAssets[key] = _merge(
          asset.copyWith(id: key),
          previous,
          previous?.favorite ?? asset.favorite,
        );
      }
    }
    if (!_assets.containsKey(key) && !_recentAssets.containsKey(key)) return;
    _recent
      ..remove(key)
      ..insert(0, key);
    if (_recent.length > 100) _recent.removeRange(100, _recent.length);
    _pruneRecent();
  });
  List<String> get recentIds => List.unmodifiable(_recent);

  Future<void> refreshRecentAsset(MemeAsset asset) async {
    if (!asset.isWeb) return;
    final id = _storedId(_recentAssets, asset);
    if (id == null || !_recent.contains(id)) return;
    await _mutate(() {
      if (!_recent.contains(id)) return;
      final previous = _favoriteWebAssets[id] ?? _recentAssets[id];
      final updated = _merge(
        asset.copyWith(id: id),
        previous,
        previous?.favorite ?? asset.favorite,
      );
      _recentAssets[id] = updated;
      if (_favoriteWebAssets.containsKey(id)) {
        _favoriteWebAssets[id] = updated.copyWith(favorite: true);
      }
    });
  }

  Future<MemeAsset> toggleFavorite(String id, {MemeAsset? asset}) =>
      _locked(() async {
        final item = asset ?? trackedById(id);
        if (item == null) throw StateError('Unknown asset.');
        final localKey = _storedId(_assets, item);
        if (localKey != null) {
          final local = _assets[localKey]!;
          final updated = local.copyWith(favorite: !local.favorite);
          _assets[localKey] = updated;
          await _write();
          return updated;
        }
        final favoriteKey = _storedId(_favoriteWebAssets, item);
        final key = favoriteKey ?? _storedId(_recentAssets, item) ?? id;
        final updated = (_favoriteWebAssets[key] ?? _recentAssets[key] ?? item)
            .copyWith(id: key, favorite: favoriteKey == null);
        if (updated.favorite) {
          _favoriteWebAssets[key] = updated;
        } else {
          _favoriteWebAssets.remove(key);
        }
        if (_recentAssets.containsKey(key)) _recentAssets[key] = updated;
        _pruneRecent();
        await _write();
        return updated;
      });

  MemeAsset applyStoredState(MemeAsset asset) {
    final saved = _storedId(_assets, asset);
    if (saved != null)
      return asset.copyWith(favorite: _assets[saved]!.favorite);
    final favorite = _storedId(_favoriteWebAssets, asset);
    return asset.copyWith(favorite: favorite != null);
  }

  Future<void> recordSearch(String q) => _mutate(() {
    final s = q.trim();
    if (s.isEmpty) return;
    _recentSearches.removeWhere((x) => _key(x) == _key(s));
    _recentSearches.insert(0, s);
    if (_recentSearches.length > 5)
      _recentSearches.removeRange(5, _recentSearches.length);
  });
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  Future<MediaFile> cacheMedia(MediaFile file, {required bool previewOnly}) =>
      _locked(() async {
        final digest = sha256.convert(file.bytes).toString();
        final stored = _permanentByDigest(digest);
        if (stored != null || _bundledDigests.containsValue(digest)) {
          final blob = await _materialize(_media, digest, file);
          return _atPath(file, blob.path, previewOnly: previewOnly);
        }
        final blob = await _materialize(_cacheDir, digest, file);
        final previous = _cache[digest]?.asset;
        // Identical bytes can be served as a thumbnail or as the original.
        // Keep the highest-quality source description in the browse index.
        final incoming = file.asset.copyWith(isPreviewOnly: previewOnly);
        final description = previewOnly && previous?.isPreviewOnly == false
            ? previous!
            : incoming;
        final now = DateTime.now();
        final entry = description.copyWith(
          id: 'cache:$digest',
          origin: 'cache',
          filePath: blob.path,
          aliases: {...?previous?.aliases, ...incoming.aliases}.toList(),
          bytes: file.bytes.length,
          addedAt: previous?.addedAt ?? now,
        );
        _cache[digest] = _CacheRecord(entry, file.bytes.length, now);
        await _evict();
        await _write();
        return _atPath(file, blob.path, previewOnly: previewOnly);
      });

  Future<void> touchCached(String path) async {
    final digest = _name(path)?.$1;
    if (digest == null || !_cache.containsKey(digest)) return;
    await _locked(() async {
      final record = _cache[digest];
      if (record == null || !p.equals(record.asset.filePath!, path)) return;
      record.access = DateTime.now();
      await _write();
    });
  }

  MemeAsset? _permanentByDigest(String digest) {
    final saved = _assets[digest];
    if (saved != null) return saved;
    for (final entry in _bundledDigests.entries) {
      if (entry.value == digest) return _assets[entry.key];
    }
    return null;
  }

  static MediaFile _atPath(MediaFile file, String path, {bool? previewOnly}) =>
      MediaFile(
        bytes: file.bytes,
        path: path,
        asset: file.asset.copyWith(filePath: path, isPreviewOnly: previewOnly),
      );

  Future<MemeAsset> keepMedia(MediaFile file) => _locked(() async {
    final digest = sha256.convert(file.bytes).toString();
    final blob = await _materialize(_media, digest, file);
    return _promote(file, digest, blob.path);
  });

  // File-copy clipboards retain a path for later pastes. Give the native
  // operation its final durable path, then register it only on success.
  Future<bool> copyAndKeep(
    MediaFile file,
    Future<bool> Function(MediaFile) copy,
  ) async {
    final digest = sha256.convert(file.bytes).toString();
    final blob = await _locked(() async {
      final staged = await _materialize(_media, digest, file);
      _pendingCopies.update(
        staged.path,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (staged.created) _discardableCopies.add(staged.path);
      return staged;
    });
    var succeeded = false;
    try {
      succeeded = await copy(_atPath(file, blob.path));
      if (!succeeded) return false;
      try {
        await _locked(() => _promote(file, digest, blob.path));
      } catch (_) {
        throw const CopyLibrarySaveException();
      }
      return true;
    } finally {
      await _locked(() async {
        if (succeeded) _discardableCopies.remove(blob.path);
        final remaining = _pendingCopies[blob.path]! - 1;
        if (remaining > 0) {
          _pendingCopies[blob.path] = remaining;
          return;
        }
        _pendingCopies.remove(blob.path);
        if (_discardableCopies.remove(blob.path) &&
            _permanentByDigest(digest) == null) {
          try {
            await File(blob.path).delete();
          } on FileSystemException {
            // Windows may still hold the file; a failed copy is never indexed.
          }
        }
      });
    }
  }

  Future<MemeAsset> _promote(MediaFile file, String digest, String path) async {
    final existing = _permanentByDigest(digest);
    final aliases = <String>{file.asset.id, 'cache:$digest'};
    bool sameImage(MemeAsset asset) {
      if (asset.isPreviewOnly != file.asset.isPreviewOnly) return false;
      final url = asset.isPreviewOnly ? asset.previewUrl : asset.originalUrl;
      final source = file.asset.isPreviewOnly
          ? file.asset.previewUrl
          : file.asset.originalUrl;
      return (url != null && url.isNotEmpty && url == source) ||
          (asset.filePath != null && _name(asset.filePath!)?.$1 == digest);
    }

    // A freshly copied thumbnail must not take over the full-size web history.
    if (file.asset.isWeb && file.asset.isPreviewOnly)
      aliases.remove(file.asset.id);
    for (final asset in [
      ..._recentAssets.values,
      ..._favoriteWebAssets.values,
    ]) {
      if (sameImage(asset)) aliases.add(asset.id);
    }
    final id = existing?.id ?? digest;
    final oldRecent = _recent.toList();
    final recentSnapshots = {
      for (final key in aliases)
        if (_recentAssets.containsKey(key)) key: _recentAssets[key]!,
    };
    final favoriteSnapshots = {
      for (final key in aliases)
        if (_favoriteWebAssets.containsKey(key)) key: _favoriteWebAssets[key]!,
    };
    final favorite =
        (existing?.favorite ?? file.asset.favorite) ||
        aliases.any(_favoriteWebAssets.containsKey);
    final saved = (existing ?? file.asset).copyWith(
      id: id,
      origin: existing?.origin ?? 'library',
      filePath: path,
      favorite: favorite,
      bytes: file.bytes.length,
      addedAt: existing?.addedAt ?? DateTime.now(),
    );
    _assets[id] = saved;
    final seen = <String>{};
    final recent = [for (final old in _recent) aliases.contains(old) ? id : old]
        .where(seen.add)
        .toList();
    _recent
      ..clear()
      ..addAll(recent);
    for (final alias in aliases) {
      _recentAssets.remove(alias);
      _favoriteWebAssets.remove(alias);
    }
    final cached = _cache.remove(digest);
    try {
      await _write();
    } catch (_) {
      if (existing == null) {
        _assets.remove(id);
      } else {
        _assets[id] = existing;
      }
      _recent
        ..clear()
        ..addAll(oldRecent);
      _recentAssets.addAll(recentSnapshots);
      _favoriteWebAssets.addAll(favoriteSnapshots);
      if (cached != null) _cache[digest] = cached;
      rethrow;
    }
    if (cached != null) await _deleteCacheFile(digest, cached);
    return saved;
  }

  Future<String> persistBytes(List<int> bytes, String extension) =>
      _locked(() async {
        final digest = sha256.convert(bytes).toString();
        return (await _writeBlob(_media, digest, extension, bytes)).path;
      });

  Future<_Staged> _materialize(
    Directory directory,
    String digest,
    MediaFile file,
  ) {
    final suffix = file.asset.format ?? p.extension(file.path);
    return _writeBlob(directory, digest, suffix, file.bytes);
  }

  Future<_Staged> _writeBlob(
    Directory directory,
    String digest,
    String extension,
    List<int> bytes,
  ) async {
    final target = File(p.join(directory.path, '$digest.${_ext(extension)}'));
    if (await target.exists() && await target.length() == bytes.length) {
      return _Staged(target.path, false);
    }
    final pending = File('${target.path}.part');
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(target.path);
    return _Staged(target.path, true);
  }

  Future<bool> _deleteCacheFile(String digest, _CacheRecord record) async {
    final path = record.asset.filePath;
    if (path == null ||
        !p.equals(p.dirname(path), _cacheDir.path) ||
        _name(path)?.$1 != digest)
      return false;
    try {
      await File(path).delete();
      return true;
    } on PathNotFoundException {
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _evict() async {
    var total = _cache.values.fold(0, (sum, entry) => sum + entry.size);
    if (total <= cacheLimitBytes) return;
    final oldest = _cache.entries.toList()
      ..sort((a, b) => a.value.access.compareTo(b.value.access));
    for (final entry in oldest) {
      if (total <= cacheLimitBytes) break;
      if (!await _deleteCacheFile(entry.key, entry.value)) continue;
      total -= entry.value.size;
      _cache.remove(entry.key);
      _dropUnavailableSnapshots(entry.value.asset);
    }
  }

  void _dropUnavailableSnapshots(MemeAsset asset) {
    // Remote snapshots can fetch their file again. A migrated anonymous file
    // has no remote source to reopen once its last local bytes are gone.
    if (asset.originalUrl != null || asset.previewUrl != null) return;
    _favoriteWebAssets.remove(asset.id);
    _recentAssets.remove(asset.id);
    _recent.remove(asset.id);
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _mutate(FutureOr<void> Function() action) => _locked(() async {
    await action();
    await _write();
  });

  Future<void> _write() async {
    final tmp = File(
      p.join(
        _directory.path,
        'library.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await tmp.writeAsString(
      jsonEncode({
        'version': 2,
        'assets': _assets.values.map((a) => a.toJson()).toList(),
        'recent': _recent,
        'recentAssets': _recentAssets.values.map((a) => a.toJson()).toList(),
        'favoriteWebAssets': _favoriteWebAssets.values
            .map((a) => a.toJson())
            .toList(),
        'recentSearches': _recentSearches,
        'cacheAssets': _cache.entries
            .map(
              (e) => {
                'digest': e.key,
                'size': e.value.size,
                'lastAccessed': e.value.access.toIso8601String(),
                'asset': e.value.asset.toJson(),
              },
            )
            .toList(),
      }),
      flush: true,
    );
    await tmp.rename(_index.path);
  }

  void _pruneRecent() => _recentAssets.removeWhere(
    (id, _) => !_recent.contains(id) && !_favoriteWebAssets.containsKey(id),
  );
  static String _key(String x) => x.trim().toLowerCase();
  static String _ext(String x) {
    final v = x.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();
    return v.isEmpty ? 'bin' : v;
  }

  static bool _digest(String x) => RegExp(r'^[a-f0-9]{64}$').hasMatch(x);
  static (String, String)? _name(String path) {
    final m = RegExp(r'^([a-f0-9]{64})\.([A-Za-z0-9]+)$')
        .firstMatch(p.basename(path));
    return m == null ? null : (m[1]!, m[2]!);
  }

  static bool _inside(String child, Directory parent) => p
      .normalize(p.absolute(child))
      .startsWith('${p.normalize(p.absolute(parent.path))}${p.separator}');
  static MemeAsset _merge(MemeAsset fresh, MemeAsset? old, bool favorite) =>
      fresh.copyWith(
        filePath: fresh.filePath ?? old?.filePath,
        format: fresh.format ?? old?.format,
        mime: fresh.mime ?? old?.mime,
        width: fresh.width ?? old?.width,
        height: fresh.height ?? old?.height,
        frames: fresh.frames ?? old?.frames,
        animated: fresh.animated || (old?.animated ?? false),
        motionVerified: fresh.motionVerified || (old?.motionVerified ?? false),
        verified: fresh.verified || (old?.verified ?? false),
        inspectionStatus: fresh.verified
            ? fresh.inspectionStatus
            : old?.inspectionStatus ?? fresh.inspectionStatus,
        inspectionReason: fresh.inspectionReason ?? old?.inspectionReason,
        favorite: favorite,
      );
}

class _CacheRecord {
  _CacheRecord(this.asset, this.size, this.access);
  final MemeAsset asset;
  final int size;
  DateTime access;
}

class _Staged {
  const _Staged(this.path, this.created);
  final String path;
  final bool created;
}
