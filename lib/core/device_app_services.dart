// ignore_for_file: curly_braces_in_flow_control_structures, prefer_initializing_formals, unnecessary_non_null_assertion

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_services.dart';
import 'catalog.dart';
import 'local_library_store.dart';
import 'models.dart';
import 'query_plan.dart';
import 'ranking_service.dart';
import 'media_inspector.dart';
import 'safe_media_downloader.dart';
import 'serpapi_account.dart';
import 'web_collectors.dart';
import 'visual_matcher.dart';

/// Device-local implementation. Web collectors deliberately remain injectable:
/// this keeps the user-owned API key out of UI code and makes partial failures
/// independent from the local library.
class DeviceAppServices implements AppServices {
  DeviceAppServices({
    this.catalog = MemeCatalog.bundled,
    AssetBundle? bundle,
    FlutterSecureStorage? secureStorage,
    LocalLibraryStore? store,
    Future<void> Function(String)? verifyKey,
    Future<SerpApiQuota> Function(String)? fetchQuota,
    Future<List<MemeAsset>> Function(QueryPlan, String)? googleSearch,
    Future<List<MemeAsset>> Function(QueryPlan)? naverSearch,
  }) : _bundle = bundle ?? rootBundle,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _verifyKey = verifyKey ?? verifySerpApiKey,
       _fetchQuota = fetchQuota ?? fetchSerpApiQuota,
       _store = store,
       _googleSearch = googleSearch ?? SerpApiMcpCollector().call,
       _naverSearch = naverSearch ?? NaverImageCollector().call;

  final MemeCatalog catalog;
  final AssetBundle _bundle;
  final FlutterSecureStorage _secureStorage;
  final Future<void> Function(String) _verifyKey;
  final Future<SerpApiQuota> Function(String) _fetchQuota;
  LocalLibraryStore? _store;
  final Future<List<MemeAsset>> Function(QueryPlan, String)? _googleSearch;
  final Future<List<MemeAsset>> Function(QueryPlan)? _naverSearch;
  final RankingService _ranking = const RankingService();
  final SafeMediaDownloader _downloader = SafeMediaDownloader();
  final Map<String, Future<String?>> _formatProbes = {};
  final List<Future<void>> _formatProbeSlots = List.filled(
    3,
    Future<void>.value(),
  );
  int _nextFormatSlot = 0;
  final Map<String, _CachedSearch> _cache = {};
  VisualMatcher? _visualMatcher;
  bool _initialized = false;
  Future<void>? _initializing;

  @override
  Future<void> initialize() {
    if (_initialized) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    final initialization = _initialize();
    _initializing = initialization;
    return initialization.whenComplete(() {
      if (identical(_initializing, initialization)) _initializing = null;
    });
  }

  Future<void> _initialize() async {
    _store ??= await LocalLibraryStore.open();
    _visualMatcher = await VisualMatcher.load(_bundle);
    final seeds = MemeCatalog.seedAssets
        .map(catalog.seedToAsset)
        .where((seed) => _store!.byId(seed.id) == null);
    await _store!.upsertAll(seeds);
    _initialized = true;
  }

  @override
  Future<SearchResponse> search(SearchRequest request) async {
    await initialize();
    final planner = QueryPlanner(catalog);
    final plan = planner.plan(request);
    final key =
        '${request.scope.wireName}|${request.filter.wireName}|${request.similar}|${request.favoritesOnly}|${request.recentOnly}|${plan.providerQuery}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 60)) {
      return cached.response;
    }
    final attempts = <SearchAttempt>[];
    final groups = <List<MemeAsset>>[];
    if (request.scope != SearchScope.web) {
      final local = await library(
        filter: request.filter,
        favoritesOnly: request.favoritesOnly,
        recentOnly: request.recentOnly,
      );
      groups.add(local.where((asset) => _matchesLocal(asset, plan)).toList());
      attempts.add(
        SearchAttempt(
          engine: 'library',
          status: 'ok',
          query: plan.words,
          count: groups.last.length,
        ),
      );
    }
    if (request.scope != SearchScope.library) {
      final key = await readSerpApiKey();
      final tasks = <Future<void>>[];
      if (_googleSearch == null || key == null || key.isEmpty) {
        attempts.add(
          SearchAttempt(
            engine: 'google',
            status: 'unconfigured',
            query: plan.providerQuery,
          ),
        );
      } else {
        tasks.add(
          _collect(
            'google',
            plan,
            () => _googleSearch!(plan, key),
            groups,
            attempts,
          ),
        );
      }
      if (_naverSearch == null) {
        attempts.add(
          SearchAttempt(
            engine: 'naver',
            status: 'unavailable',
            query: plan.providerQuery,
          ),
        );
      } else {
        tasks.add(
          _collect('naver', plan, () => _naverSearch!(plan), groups, attempts),
        );
      }
      await Future.wait(tasks);
    }
    var ranked = _ranking
        .mergeAndRank(groups, plan)
        .where(
          (asset) =>
              request.filter != MediaFilter.gif ||
              !asset.verified ||
              asset.motionVerified ||
              asset.isGif,
        )
        .toList(growable: false);
    if (request.scope != SearchScope.library &&
        (plan.familyId != null || request.filter == MediaFilter.gif)) {
      ranked = await _probeVisual(ranked, plan);
    }
    // A web collector produces fresh objects each time. Overlay durable Home
    // state so a bookmarked result stays visibly bookmarked on later searches.
    ranked = ranked.map(_store!.applyStoredState).toList(growable: false);
    final remoteAttempts = attempts
        .where(
          (attempt) => attempt.engine == 'google' || attempt.engine == 'naver',
        )
        .toList(growable: false);
    final remoteFailure =
        request.scope != SearchScope.library &&
        remoteAttempts.isNotEmpty &&
        !remoteAttempts.any((attempt) => attempt.status == 'ok') &&
        remoteAttempts.any((attempt) => attempt.status == 'failed');
    final response = SearchResponse(
      assets: ranked,
      attempts: attempts,
      scope: request.scope,
      error: remoteFailure ? '웹 검색에 실패했습니다.' : null,
    );
    _cache[key] = _CachedSearch(DateTime.now(), response);
    return response;
  }

  Future<List<MemeAsset>> _probeVisual(
    List<MemeAsset> assets,
    QueryPlan plan,
  ) async {
    final targets = _ranking.probeTargets(
      assets.where((asset) => asset.isWeb).toList(),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var next = 0;
    final completed = <String, _ProbedAsset>{};
    Future<_ProbedAsset?> probe() async {
      if (next >= targets.length || DateTime.now().isAfter(deadline))
        return null;
      final asset = targets[next++];
      try {
        final media = await loadMedia(asset);
        final tags = <String>{
          ...plan.tagIds,
          ...plan.tagTerms,
          ...asset.tags.map((tag) => tag.id),
          ...asset.tags.map((tag) => tag.label),
        };
        final score = await _visualMatcher?.score(
          media.bytes,
          plan.familyId,
          tags: tags,
        );
        if (DateTime.now().isAfter(deadline)) return null;
        final result = _ProbedAsset(media.asset, score);
        completed[result.asset.id] = result;
        return result;
      } catch (_) {
        return null;
      }
    }

    Future<void> worker() async {
      while (DateTime.now().isBefore(deadline) && next < targets.length) {
        await probe();
      }
    }

    await Future.wait(List.generate(4, (_) => worker()))
        .timeout(const Duration(seconds: 12), onTimeout: () => const <void>[]);
    final byId = Map<String, _ProbedAsset>.unmodifiable(completed);
    return _ranking.rank(
      assets.map((asset) {
        final probed = byId[asset.id];
        return probed == null
            ? asset
            : probed.asset.copyWith(visualScore: probed.score);
      }).toList(),
      plan,
    );
  }

  Future<void> _collect(
    String engine,
    QueryPlan plan,
    Future<List<MemeAsset>> Function() action,
    List<List<MemeAsset>> groups,
    List<SearchAttempt> attempts,
  ) async {
    try {
      final results = await action();
      groups.add(results);
      attempts.add(
        SearchAttempt(
          engine: engine,
          status: 'ok',
          query: plan.providerQuery,
          count: results.length,
        ),
      );
    } catch (_) {
      attempts.add(
        SearchAttempt(
          engine: engine,
          status: 'failed',
          query: plan.providerQuery,
        ),
      );
    }
  }

  bool _matchesLocal(MemeAsset asset, QueryPlan plan) {
    final value = compactMemeText(
      '${asset.title} ${asset.familyName ?? ''} ${asset.variant ?? ''} ${asset.aliases.join(' ')} ${asset.tags.map((tag) => tag.label).join(' ')}',
    );
    final core = plan.coreTerms
        .where((term) => term.isNotEmpty)
        .map(compactMemeText);
    final tags = plan.tagTerms
        .where((term) => term.isNotEmpty)
        .map(compactMemeText);
    final familyMatch =
        plan.familyId != null && asset.familyId == plan.familyId;
    return (familyMatch || core.every(value.contains)) &&
        tags.every(value.contains);
  }

  @override
  Future<List<MemeAsset>> library({
    MediaFilter filter = MediaFilter.all,
    bool favoritesOnly = false,
    bool recentOnly = false,
  }) async {
    await initialize();
    var items = recentOnly
        ? _store!.recentAssets()
        : favoritesOnly
        ? _store!.favorites()
        : _store!.all();
    if (favoritesOnly && recentOnly) {
      items = items.where((item) => item.favorite).toList();
    }
    if (filter == MediaFilter.gif)
      items = items.where((item) => item.isGif).toList();
    if (filter == MediaFilter.staticImage)
      items = items.where((item) => !item.isGif).toList();
    return items;
  }

  @override
  Future<MediaFile> loadMedia(
    MemeAsset asset, {
    bool preferCached = true,
  }) async {
    if (asset.filePath != null && await File(asset.filePath!).exists()) {
      return MediaFile(
        bytes: await File(asset.filePath!).readAsBytes(),
        path: asset.filePath!,
        asset: asset,
      );
    }
    if (asset.bundledAssetPath != null) {
      final data = await _bundle.load(asset.bundledAssetPath!);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final path = await _store!.persistBytes(
        bytes,
        asset.format?.toLowerCase() ?? 'bin',
      );
      return MediaFile(
        bytes: bytes,
        path: path,
        asset: asset.copyWith(filePath: path),
      );
    }
    final url = asset.originalUrl;
    if (url == null || url.isEmpty)
      throw StateError('Media has no original URL.');
    return _loadWebImage(asset, url, hydrateRecentOriginal: true);
  }

  @override
  Future<String?> probeWebFormat(MemeAsset asset) {
    final url = asset.originalUrl;
    if (!asset.isWeb || url == null || asset.displayFormat != null) {
      return Future.value(asset.displayFormat);
    }
    final cached = _formatProbes[url];
    if (cached != null) return cached;
    final slot = _nextFormatSlot++ % _formatProbeSlots.length;
    final probe = _formatProbeSlots[slot].then((_) async {
      try {
        return MediaInspector.signatureFormat(
          await _downloader.readPrefix(url),
        );
      } catch (_) {
        return null;
      }
    });
    _formatProbeSlots[slot] = probe.then<void>((_) {});
    if (_formatProbes.length >= 128)
      _formatProbes.remove(_formatProbes.keys.first);
    return _formatProbes[url] = probe;
  }

  @override
  Future<MediaFile> loadPreviewMedia(MemeAsset asset) {
    final url = asset.previewUrl;
    if (!asset.isWeb || url == null || url == asset.originalUrl) {
      throw StateError('No separate web preview.');
    }
    return _loadWebImage(asset, url);
  }

  Future<MediaFile> _loadWebImage(
    MemeAsset asset,
    String url, {
    bool hydrateRecentOriginal = false,
  }) async {
    final bytes = await _downloader.download(url);
    final inspection = await MediaInspector.inspectMotion(bytes);
    if (inspection.format == 'UNKNOWN' ||
        inspection.reason == 'canvas-too-large' ||
        inspection.reason == 'animation-budget-exceeded') {
      throw StateError('Media failed safety inspection.');
    }
    final ext = inspection.format.toLowerCase();
    final path = await _store!.persistBytes(bytes, ext);
    final cached = asset.copyWith(
      filePath: path,
      format: inspection.format,
      mime: 'image/${inspection.format.toLowerCase()}',
      width: inspection.width,
      height: inspection.height,
      frames: inspection.frames,
      animated: inspection.animated,
      motionVerified: inspection.motionVerified,
      verified: true,
      inspectionStatus: inspection.animated ? 'animated' : 'static',
      inspectionReason: inspection.reason,
    );
    if (hydrateRecentOriginal) {
      try {
        await _store!.refreshRecentAsset(cached);
      } catch (_) {
        // Recent history is best-effort; a storage failure must not block media.
      }
    }
    return MediaFile(bytes: bytes, path: path, asset: cached);
  }

  @override
  Future<MemeAsset> saveToLibrary(
    MediaFile file, {
    String? title,
    String? familyId,
    String? familyName,
    List<MemeTag> tags = const [],
    List<String> aliases = const [],
  }) async {
    await initialize();
    final ext = (file.asset.format ?? file.path.split('.').last).toLowerCase();
    final path = await _store!.persistBytes(file.bytes, ext);
    final id = sha256.convert(file.bytes).toString();
    final asset = file.asset.copyWith(
      id: id,
      title: title ?? file.asset.title,
      origin: 'library',
      filePath: path,
      familyId: familyId ?? file.asset.familyId,
      familyName: familyName ?? file.asset.familyName,
      tags: tags.isEmpty ? file.asset.tags : tags,
      aliases: aliases.isEmpty ? file.asset.aliases : aliases,
      addedAt: DateTime.now(),
    );
    await _store!.upsert(asset);
    _cache.clear();
    return asset;
  }

  @override
  Future<MemeAsset> toggleFavorite(String assetId, {MemeAsset? asset}) async {
    await initialize();
    final updated = await _store!.toggleFavorite(assetId, asset: asset);
    _cache.clear();
    return updated;
  }

  @override
  Future<void> markRecent(String assetId, {MemeAsset? asset}) async {
    await initialize();
    await _store!.recent(assetId, asset: asset);
    _cache.clear();
  }

  @override
  Future<List<String>> recentSearches() async {
    await initialize();
    return _store!.recentSearches;
  }

  @override
  Future<void> recordSearch(String query) async {
    await initialize();
    await _store!.recordSearch(query);
  }

  @override
  Future<SettingsState> settings() async {
    final secure = await _secureStorage.read(key: _serpKeyName);
    final environment = Platform.environment['SERPAPI_API_KEY'];
    return SettingsState(
      serpApiConfigured: (secure ?? environment ?? '').isNotEmpty,
      serpApiSetupDeferred:
          await _secureStorage.read(key: _setupDeferredName) == '1',
      serpApiKeySource: (secure ?? '').isNotEmpty
          ? 'app'
          : (environment ?? '').isNotEmpty
          ? 'environment'
          : 'none',
    );
  }

  static const _serpKeyName = 'serpapi_api_key';
  static const _setupDeferredName = 'serpapi_setup_deferred';
  @override
  Future<String?> readSerpApiKey() async =>
      await _secureStorage.read(key: _serpKeyName) ??
      Platform.environment['SERPAPI_API_KEY'];

  @override
  Future<SerpApiQuota?> readSerpApiQuota() async {
    final key = await readSerpApiKey();
    if (key == null || key.isEmpty) return null;
    return _fetchQuota(key);
  }

  @override
  Future<void> writeSerpApiKey(String key) async {
    final trimmed = key.trim();
    await _verifyKey(trimmed);
    await _secureStorage.write(key: _serpKeyName, value: trimmed);
    _cache.clear();
  }

  @override
  Future<void> deferSerpApiSetup() =>
      _secureStorage.write(key: _setupDeferredName, value: '1');

  @override
  Future<void> deleteSerpApiKey() async {
    await deferSerpApiSetup();
    await _secureStorage.delete(key: _serpKeyName);
    _cache.clear();
  }
}

class _CachedSearch {
  const _CachedSearch(this.at, this.response);
  final DateTime at;
  final SearchResponse response;
}

class _ProbedAsset {
  const _ProbedAsset(this.asset, this.score);
  final MemeAsset asset;
  final num? score;
}
