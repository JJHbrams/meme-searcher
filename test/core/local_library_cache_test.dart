import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meme-library-cache-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'reading an older file keeps it when the cache next overflows',
    () async {
      final store = await LocalLibraryStore.open(
        directory: root,
        cacheLimitBytes: 4,
      );
      final first = await store.cacheMedia(
        _media([1, 2], 'first'),
        previewOnly: false,
      );
      final second = await store.cacheMedia(
        _media([3, 4], 'second'),
        previewOnly: false,
      );
      await store.touchCached(first.path);
      await store.cacheMedia(_media([5, 6], 'third'), previewOnly: false);
      expect(await File(first.path).exists(), isTrue);
      expect(await File(second.path).exists(), isFalse);
      expect(store.cachedAssets().map((a) => a.title), ['third', 'first']);
    },
  );

  test(
    'failed copy is not promoted and cannot delete a concurrent clipboard file',
    () async {
      final store = await LocalLibraryStore.open(directory: root);
      final media = await store.cacheMedia(
        _media([1, 2, 3], 'same'),
        previewOnly: false,
      );
      final entered = Completer<String>(), release = Completer<bool>();
      final first = store.copyAndKeep(media, (prepared) {
        entered.complete(prepared.path);
        return release.future;
      });
      final clipboard = await entered.future;
      expect(await store.copyAndKeep(media, (_) async => false), isFalse);
      expect(await File(clipboard).exists(), isTrue);
      expect(store.all(), isEmpty);
      release.complete(true);
      expect(await first, isTrue);
      expect(store.all().single.filePath, clipboard);
      expect(store.cachedAssets(), isEmpty);

      final other = await store.cacheMedia(
        _media([1, 4], 'fails'),
        previewOnly: true,
      );
      late String staged;
      await expectLater(
        store.copyAndKeep(other, (prepared) async {
          staged = prepared.path;
          throw StateError('clipboard busy');
        }),
        throwsStateError,
      );
      expect(await File(staged).exists(), isFalse);
      expect(await File(other.path).exists(), isTrue);
      expect(store.all(), hasLength(1));
    },
  );

  test('a damaged index is retained and its old media is never classified for eviction', () async {
    final drawer = Directory(p.join(root.path, 'meme_drawer'));
    final media = Directory(p.join(drawer.path, 'media'));
    await media.create(recursive: true);
    final content = [2, 5, 7];
    final file = File(p.join(media.path, '${sha256.convert(content)}.png'));
    await file.writeAsBytes(content);
    await File(p.join(drawer.path, 'library.json'))
        .writeAsString('broken index');
    final store = await LocalLibraryStore.open(
      directory: root,
      cacheLimitBytes: 0,
    );
    expect(store.cachedAssets(), isEmpty);
    expect(await file.readAsBytes(), content);
    final preserved = drawer.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.corrupt'),
    );
    expect(await preserved.readAsString(), 'broken index');
  });

  test(
    'legacy recent web media migrates to cache and preserves its snapshot',
    () async {
      final drawer = Directory(p.join(root.path, 'meme_drawer'));
      final media = Directory(p.join(drawer.path, 'media'));
      await media.create(recursive: true);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final digest = sha256.convert(bytes).toString();
      final oldPath = p.join(media.path, '$digest.gif');
      await File(oldPath).writeAsBytes(bytes);
      final web = MemeAsset(
        id: 'tenor-1',
        title: '기억한 장면',
        origin: 'web',
        originalUrl: 'https://example.test/original.gif',
        sourceUrl: 'https://example.test/source',
        filePath: oldPath,
        format: 'GIF',
      );
      await File(p.join(drawer.path, 'library.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'assets': <Object?>[],
          'recent': ['tenor-1'],
          'recentAssets': [web.toJson()],
          'favoriteWebAssets': <Object?>[],
          'recentSearches': <Object?>[],
        }),
      );

      final store = await LocalLibraryStore.open(directory: root);

      final cached = store.cachedAssets().single;
      expect(cached.origin, 'cache');
      expect(cached.title, '기억한 장면');
      expect(cached.originalUrl, web.originalUrl);
      expect(File(cached.filePath!).existsSync(), isTrue);
      expect(File(oldPath).existsSync(), isFalse);
      expect(store.recentAssets().single.filePath, cached.filePath);
      expect(
        jsonDecode(
          await File(p.join(drawer.path, 'library.json')).readAsString(),
        )['version'],
        3,
      );
    },
  );

  test(
    'cache evicts least recently accessed bytes and survives reopen',
    () async {
      final store = await LocalLibraryStore.open(
        directory: root,
        cacheLimitBytes: 3,
      );
      final first = await store.cacheMedia(
        _media([1, 2], 'first'),
        previewOnly: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await store.cacheMedia(
        _media([3, 4], 'second'),
        previewOnly: true,
      );

      expect(File(first.path).existsSync(), isFalse);
      expect(File(second.path).existsSync(), isTrue);
      final reopened = await LocalLibraryStore.open(
        directory: root,
        cacheLimitBytes: 3,
      );
      expect(reopened.cachedAssets(), hasLength(1));
      expect(reopened.cachedAssets().single.title, 'second');
      expect(reopened.cachedAssets().single.isPreviewOnly, isTrue);
    },
  );

  test(
    'cache browse order stays at original insertion order after LRU touches',
    () async {
      final store = await LocalLibraryStore.open(directory: root);
      final first = await store.cacheMedia(
        _media([1], 'first'),
        previewOnly: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.cacheMedia(_media([2], 'second'), previewOnly: false);
      await store.touchCached(first.path);

      expect(store.cachedAssets().map((asset) => asset.title), [
        'second',
        'first',
      ]);
      final reopened = await LocalLibraryStore.open(directory: root);
      expect(reopened.cachedAssets().map((asset) => asset.title), [
        'second',
        'first',
      ]);
    },
  );

  test('legacy hash cache has no generated display label', () {
    final asset = MemeAsset(
      id: 'cache:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      origin: 'cache',
      title: '이전 GIF 짤 · aaaaaaaa',
    );
    expect(asset.displayTitle, isNull);
    expect(
      MemeAsset(
        id: 'cache:hash',
        origin: 'cache',
        title: 'aaaaaaaa.png',
      ).displayTitle,
      isNull,
    );
  });

  test(
    'deleting cached media removes web-history aliases and survives reopen',
    () async {
      final store = await LocalLibraryStore.open(directory: root);
      const web = MemeAsset(
        id: 'web-history',
        title: 'History item',
        origin: 'web',
        originalUrl: 'https://example.test/original.gif',
      );
      await store.recent(web.id, asset: web);
      await store.toggleFavorite(web.id, asset: web);
      final cached = await store.cacheMedia(
        MediaFile(
          bytes: Uint8List.fromList([8, 6, 7, 5]),
          path: '',
          asset: web.copyWith(format: 'GIF'),
        ),
        previewOnly: false,
      );

      final cachedId = store.cachedAssets().single.id;
      expect(await store.deleteLocalAssets([cachedId]), 1);
      expect(store.cachedAssets(), isEmpty);
      expect(store.recentAssets(), isEmpty);
      expect(store.favorites(), isEmpty);
      expect(await File(cached.path).exists(), isFalse);
      expect(await store.deleteLocalAssets([cachedId]), 0);

      final reopened = await LocalLibraryStore.open(directory: root);
      expect(reopened.cachedAssets(), isEmpty);
      expect(reopened.recentAssets(), isEmpty);
      expect(reopened.favorites(), isEmpty);

      // A later web request for the same bytes is a new cache operation, not a
      // resurrection of the removed record.
      await reopened.cacheMedia(
        MediaFile(
          bytes: Uint8List.fromList([8, 6, 7, 5]),
          path: '',
          asset: web.copyWith(format: 'GIF'),
        ),
        previewOnly: false,
      );
      final recached = await LocalLibraryStore.open(directory: root);
      expect(recached.cachedAssets(), hasLength(1));
    },
  );

  test('deleting a library record never follows an external path', () async {
    final store = await LocalLibraryStore.open(directory: root);
    final external = File(p.join(root.path, 'outside.png'));
    await external.writeAsBytes([9, 9]);
    await store.upsert(
      MemeAsset(id: 'external', title: 'external', filePath: external.path),
    );

    expect(await store.deleteLocalAssets(['external']), 1);
    expect(await external.readAsBytes(), [9, 9]);
  });
}

MediaFile _media(List<int> values, String title) {
  final bytes = Uint8List.fromList(values);
  return MediaFile(
    bytes: bytes,
    path: '',
    asset: MemeAsset(id: title, title: title, origin: 'web', format: 'GIF'),
  );
}
