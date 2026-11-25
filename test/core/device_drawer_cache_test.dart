import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/device_app_services.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/query_plan.dart';
import 'package:meme_searcher/core/safe_media_downloader.dart';

/// Integration regressions for the drawer's bounded temporary cache and its
/// separate permanent library. A real store is intentional: all guarantees
/// here cross persistence and filesystem boundaries.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('meme-drawer-cache-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('GIF search auto-probes into temporary cache and local search stays offline', () async {
    final downloads = _Downloader({'https://example.test/original.gif': _gifA});
    var webRequests = 0;
    final app = await _app(
      root,
      downloader: downloads,
      naverSearch: (_) async {
        webRequests++;
        return [
          _web('provider-auto-probe', title: 'auto probe wapa', gif: true),
        ];
      },
    );
    final remote = await app.search(
      const SearchRequest(
        query: 'wapa',
        scope: SearchScope.web,
        filter: MediaFilter.gif,
      ),
    );
    expect(remote.assets, isNotEmpty);
    expect(
      downloads.downloads['https://example.test/original.gif'],
      1,
      reason: 'GIF search must exercise the bounded auto-probe path',
    );
    expect(
      (await app.cachedLibrary()).map((asset) => asset.title),
      contains('auto probe wapa'),
    );
    expect(
      (await app.library()).map((asset) => asset.title),
      isNot(contains('auto probe wapa')),
      reason: 'probing never puts a result on the permanent shelf',
    );
    final local = await app.search(
      const SearchRequest(query: 'wapa', scope: SearchScope.library),
    );
    expect(
      local.assets.map((asset) => asset.title),
      contains('auto probe wapa'),
    );
    expect(
      webRequests,
      1,
      reason: 'the library scope must not call a provider',
    );
  });

  test(
    'new provider snapshot resolves cached original without another download',
    () async {
      final downloads = _Downloader({
        'https://example.test/original.gif': _gifA,
      });
      final app = await _app(root, downloader: downloads);
      await app.loadMedia(_web('provider-id-one', title: 'same remote scene'));
      final resolved = await app.loadMedia(
        _web('provider-id-two', title: 'same remote scene'),
      );
      expect(await File(resolved.path).exists(), isTrue);
      expect(downloads.downloads['https://example.test/original.gif'], 1);
      expect(
        (await app.cachedLibrary()).map((asset) => asset.title),
        contains('same remote scene'),
      );
    },
  );

  test('copy promotion gives native code a durable path and removes temporary entry', () async {
    final downloads = _Downloader({
      'https://example.test/original.gif': _gifA,
      'https://example.test/b.gif': _gifB,
      'https://example.test/c.gif': _gifC,
      'https://example.test/d.gif': _gifD,
    });
    final source = _web(
      'provider-keep',
      title: 'custom Chandler whip sound',
      aliases: const ['wapa', 'wah-pah', 'whoopah'],
    );
    final first = await _app(root, downloader: downloads, cacheLimitBytes: 100);
    final temporary = await first.loadMedia(source);
    expect(
      (await first.cachedLibrary()).map((asset) => asset.title),
      contains(source.title),
    );
    String? offeredPath;
    expect(
      await first.copyAndKeep(temporary, (file) async {
        offeredPath = file.path;
        return File(file.path).exists();
      }),
      isTrue,
    );
    expect(offeredPath, isNotNull);
    expect(await File(offeredPath!).readAsBytes(), orderedEquals(_gifA));
    expect(
      (await first.cachedLibrary()).map((asset) => asset.title),
      isNot(contains(source.title)),
    );
    expect(
      (await first.library()).map((asset) => asset.title),
      contains(source.title),
    );

    await first.loadMedia(
      _web(
        'provider-b',
        title: 'cache filler b',
        original: 'https://example.test/b.gif',
      ),
    );
    await first.loadMedia(
      _web(
        'provider-c',
        title: 'cache filler c',
        original: 'https://example.test/c.gif',
      ),
    );
    await first.loadMedia(
      _web(
        'provider-d',
        title: 'cache filler d',
        original: 'https://example.test/d.gif',
      ),
    );
    expect(
      await File(offeredPath!).exists(),
      isTrue,
      reason:
          'native callback receives a shelf file, not an evictable cache file',
    );

    final restarted = await _app(
      root,
      downloader: downloads,
      cacheLimitBytes: 100,
    );
    final permanent = (await restarted.library()).singleWhere(
      (asset) => asset.title == source.title,
    );
    expect(permanent.aliases, source.aliases);
    expect(
      permanent.tags.map((tag) => tag.id),
      source.tags.map((tag) => tag.id),
    );
    expect(
      await restarted.copyAndKeep(
        await restarted.loadMedia(permanent),
        (file) async =>
            file.path == offeredPath && await File(file.path).exists(),
      ),
      isTrue,
    );
    final afterRepeat = (await restarted.library()).singleWhere(
      (asset) => asset.title == source.title,
    );
    expect(afterRepeat.aliases, source.aliases);
    expect(
      afterRepeat.tags.map((tag) => tag.id),
      source.tags.map((tag) => tag.id),
    );
  });

  test('eviction removes oldest temporary file and local search has no stale result', () async {
    final downloads = _Downloader({
      'https://example.test/a.gif': _gifA,
      'https://example.test/b.gif': _gifB,
      'https://example.test/c.gif': _gifC,
    });
    // Each fixture fits individually; all three cannot coexist in 100 bytes.
    final app = await _app(root, downloader: downloads, cacheLimitBytes: 100);
    final a = await app.loadMedia(
      _web(
        'provider-a',
        title: 'temporary alpha',
        original: 'https://example.test/a.gif',
      ),
    );
    await app.loadMedia(
      _web(
        'provider-b',
        title: 'temporary beta',
        original: 'https://example.test/b.gif',
      ),
    );
    await app.loadMedia(
      _web(
        'provider-c',
        title: 'temporary gamma',
        original: 'https://example.test/c.gif',
      ),
    );
    expect(await File(a.path).exists(), isFalse);
    expect(
      (await app.cachedLibrary()).map((asset) => asset.title),
      isNot(contains('temporary alpha')),
    );
    final local = await app.search(
      const SearchRequest(query: 'temporary alpha', scope: SearchScope.library),
    );
    expect(
      local.assets.map((asset) => asset.title),
      isNot(contains('temporary alpha')),
    );
  });

  test('preview stays preview-only, can be promoted, and never masquerades as original', () async {
    final downloads = _Downloader({
      'https://example.test/preview.gif': _gifA,
      'https://example.test/original.gif': _gifB,
    });
    final source = _web('provider-preview', title: 'preview-only scene');
    final app = await _app(root, downloader: downloads);
    final preview = await app.loadPreviewMedia(source);
    expect(preview.asset.isPreviewOnly, isTrue);
    expect(preview.asset.id, source.id);
    expect((await app.cachedLibrary()).single.isPreviewOnly, isTrue);
    expect(preview.asset.originalUrl, source.originalUrl);
    expect(
      await app.copyAndKeep(preview, (file) async => File(file.path).exists()),
      isTrue,
      reason: 'a deliberately selected preview remains copyable',
    );
    expect(
      (await app.cachedLibrary()).map((asset) => asset.title),
      isNot(contains(source.title)),
    );
    expect(
      (await app.library()).map((asset) => asset.title),
      contains(source.title),
    );
    await app.loadMedia(source);
    expect(downloads.downloads['https://example.test/original.gif'], 1);
    expect(downloads.downloads['https://example.test/preview.gif'], 1);
  });
}

Future<DeviceAppServices> _app(
  Directory root, {
  required _Downloader downloader,
  Future<List<MemeAsset>> Function(QueryPlan)? naverSearch,
  int cacheLimitBytes = 1024 * 1024,
}) async {
  final app = DeviceAppServices(
    store: await LocalLibraryStore.open(
      directory: root,
      cacheLimitBytes: cacheLimitBytes,
    ),
    downloader: downloader,
    naverSearch: naverSearch ?? (_) async => const [],
  );
  await app.initialize();
  return app;
}

MemeAsset _web(
  String providerId, {
  required String title,
  String original = 'https://example.test/original.gif',
  String preview = 'https://example.test/preview.gif',
  List<String> aliases = const ['wapa', 'whoopah'],
  bool gif = false,
}) => MemeAsset(
  id: providerId,
  title: title,
  origin: 'web',
  familyId: 'friends',
  familyName: 'Friends',
  aliases: aliases,
  tags: const [MemeTag(id: 'sound', label: 'sound effect')],
  originalUrl: original,
  previewUrl: preview,
  formatHint: gif ? 'GIF' : null,
);

class _Downloader extends SafeMediaDownloader {
  _Downloader(this.responses);
  final Map<String, Uint8List> responses;
  final Map<String, int> downloads = {};
  @override
  Future<Uint8List> download(String url) async {
    downloads.update(url, (count) => count + 1, ifAbsent: () => 1);
    final bytes = responses[url];
    if (bytes == null) throw StateError('No offline response for $url');
    return bytes;
  }
}

final Uint8List _gifA = Uint8List.fromList(
  base64Decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=='),
);
final Uint8List _gifB = Uint8List.fromList([..._gifA, 1]);
final Uint8List _gifC = Uint8List.fromList([..._gifA, 2]);
final Uint8List _gifD = Uint8List.fromList([..._gifA, 3]);
