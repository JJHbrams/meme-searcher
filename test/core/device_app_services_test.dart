import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/device_app_services.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/query_plan.dart';
import 'package:meme_searcher/core/web_collectors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryRoot;
  late LocalLibraryStore store;
  late DeviceAppServices services;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temporaryRoot = await Directory.systemTemp.createTemp(
      'meme-searcher-test-',
    );
    store = await LocalLibraryStore.open(directory: temporaryRoot);
    services = DeviceAppServices(store: store);
    await services.initialize();
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test('initializes bundled library and keeps local query behavior', () async {
    expect(await services.library(), hasLength(5));
    expect(await services.library(filter: MediaFilter.gif), hasLength(2));

    final coming = await services.search(
      const SearchRequest(
        query: '좋다 지금 간다 기다려라',
        scope: SearchScope.library,
        tags: ['헬다2'],
      ),
    );
    expect(
      coming.assets.map((asset) => asset.id),
      contains('helldivers-coming'),
    );

    final unknown = await services.search(
      const SearchRequest(
        query: 'no-such-meme-keyword',
        scope: SearchScope.library,
        tags: ['not-a-real-tag'],
      ),
    );
    expect(unknown.assets, isEmpty);

    final withoutSimilar = await services.search(
      const SearchRequest(query: '내가 간다 기다려라', scope: SearchScope.library),
    );
    final withSimilar = await services.search(
      const SearchRequest(
        query: '내가 간다 기다려라',
        scope: SearchScope.library,
        similar: true,
      ),
    );
    expect(withoutSimilar.assets, isEmpty);
    expect(withSimilar.assets, isNotEmpty);
  });

  test(
    'setup persists deferral and keeps the old key on failed verification',
    () async {
      final setup = DeviceAppServices(
        store: store,
        verifyKey: (key) async {
          if (key != 'test-valid') throw StateError('Rejected synthetic key');
        },
      );
      expect((await setup.settings()).serpApiSetupDeferred, isFalse);
      await setup.deferSerpApiSetup();
      await setup.writeSerpApiKey(' test-valid ');
      await expectLater(
        setup.writeSerpApiKey('test-invalid'),
        throwsStateError,
      );
      final restarted = DeviceAppServices(store: store);
      expect(await restarted.readSerpApiKey(), 'test-valid');
      final settings = await restarted.settings();
      expect(settings.serpApiKeySource, 'app');
      expect(settings.serpApiSetupDeferred, isTrue);
    },
  );

  test(
    'favorites survive a new store instance and saved GIF keeps bytes',
    () async {
      final approved = (await services.library(filter: MediaFilter.gif)).first;
      await services.toggleFavorite(approved.id);
      final reopened = DeviceAppServices(
        store: await LocalLibraryStore.open(directory: temporaryRoot),
      );
      await reopened.initialize();
      expect(
        (await reopened.library(favoritesOnly: true)).map((asset) => asset.id),
        contains(approved.id),
      );

      final media = await reopened.loadMedia(approved);
      final saved = await reopened.saveToLibrary(media);
      expect(
        await File(saved.filePath!).readAsBytes(),
        orderedEquals(media.bytes),
      );
    },
  );

  final shouldRunLive =
      Platform.environment['MEME_SEARCHER_LIVE_TEST'] == '1' &&
      (Platform.environment['SERPAPI_API_KEY'] ?? '').isNotEmpty;
  test(
    'live SerpApi GIF search returns an inspected moving original',
    () async {
      final previousOverrides = HttpOverrides.current;
      Object? collectorFailure;
      // Flutter's test binding installs a 400-only HttpOverride. It is removed
      // only for this explicit live test; normal TLS validation remains intact.
      HttpOverrides.global = null;
      try {
        final liveServices = DeviceAppServices(
          store: store,
          googleSearch: (QueryPlan plan, String key) async {
            try {
              return await SerpApiMcpCollector().call(plan, key);
            } catch (error) {
              collectorFailure = error;
              rethrow;
            }
          },
        );
        final response = await liveServices.search(
          const SearchRequest(
            query: 'approved!',
            scope: SearchScope.web,
            filter: MediaFilter.gif,
          ),
        );
        final google = response.attempts.firstWhere(
          (attempt) => attempt.engine == 'google',
        );
        final naver = response.attempts.firstWhere(
          (attempt) => attempt.engine == 'naver',
        );
        final gifAssets = response.assets.where(
          (asset) => asset.isGif && asset.originalUrl != null,
        );
        // Deliberately operational-only output: neither key nor URL is printed.
        // ignore: avoid_print
        print(
          'live google=${google.status}/${google.count} naver=${naver.status}/${naver.count} '
          'results=${response.assets.length} collector=${collectorFailure?.runtimeType ?? 'none'}/${_safeErrorCode(collectorFailure)}',
        );
        expect(google.status, 'ok');
        expect(gifAssets, isNotEmpty);

        MediaFile? moving;
        for (final asset in gifAssets.take(12)) {
          try {
            final media = await liveServices.loadMedia(asset);
            if (media.asset.motionVerified) {
              moving = media;
              break;
            }
          } catch (_) {
            // A candidate can disappear after search; continue to another result.
          }
        }
        expect(moving, isNotNull);
        // ignore: avoid_print
        print(
          'live gifFrames=${moving!.asset.frames} sha256=${sha256.convert(moving.bytes)}',
        );
        expect(moving.asset.frames, greaterThan(1));
        expect(moving.asset.motionVerified, isTrue);
      } finally {
        HttpOverrides.global = previousOverrides;
      }
    },
    skip: shouldRunLive
        ? false
        : 'Set MEME_SEARCHER_LIVE_TEST=1 with SERPAPI_API_KEY.',
  );
}

String _safeErrorCode(Object? error) {
  if (error is SocketException) return 'socket';
  if (error is HttpException) return 'http';
  if (error == null) return 'none';
  return 'collector-error';
}
