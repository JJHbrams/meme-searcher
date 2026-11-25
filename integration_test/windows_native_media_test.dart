import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:meme_searcher/core/device_app_services.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';

const _headlessEnvironment = 'MEME_SEARCHER_HEADLESS_TEST';
const _liveMediaEnvironment = 'MEME_SEARCHER_LIVE_MEDIA_TEST';
const _liveProviderEnvironment = 'MEME_SEARCHER_LIVE_PROVIDER_COPY_TEST';
const _channel = MethodChannel(MediaActions.channelName);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final headless =
      Platform.isWindows && Platform.environment[_headlessEnvironment] == '1';
  final liveMedia =
      headless && Platform.environment[_liveMediaEnvironment] == '1';
  final liveProvider =
      liveMedia && Platform.environment[_liveProviderEnvironment] == '1';

  final expectedStation =
      Platform.environment['MEME_SEARCHER_TEST_WINDOW_STATION'];
  if (headless && expectedStation != null) {
    setUpAll(() async {
      expect(
        await _channel.invokeMethod<String>('debugWindowStation'),
        expectedStation,
      );
    });
  }

  testWidgets('copies GIF original as CF_HDROP with unchanged bytes', (
    tester,
  ) async {
    final fixture = await _readFixture('approved-knuckles-kym.gif');
    final decoded = image.decodeGif(fixture.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, greaterThan(1));

    final result = await MediaActions().copy(
      MediaFile(
        bytes: fixture.bytes,
        path: fixture.path,
        asset: const MemeAsset(
          id: 'headless-gif',
          title: 'Headless GIF fixture',
          origin: 'library',
          format: 'GIF',
          mime: 'image/gif',
          animated: true,
        ),
      ),
    );
    expect(result.completed, isTrue);

    final clipboard = await _clipboardState();
    expect(clipboard['opened'], isTrue);
    expect(clipboard['hasFileDrop'], isTrue);
    expect(clipboard['hasDib'], isFalse);
    expect(clipboard['hasPng'], isFalse);
    expect(clipboard['hasShellIdList'], isTrue);
    expect(clipboard['dropEffect'], 1); // DROPEFFECT_COPY
    final copiedPath = clipboard['filePath'] as String?;
    expect(copiedPath, isNotNull);
    expect(_samePath(copiedPath!, fixture.path), isTrue);
    final copiedBytes = await File(copiedPath).readAsBytes();
    expect(sha256.convert(copiedBytes), sha256.convert(fixture.bytes));
  }, skip: !headless);

  testWidgets('pastes PNG as pixels in PNG and Windows bitmap formats', (
    tester,
  ) async {
    final fixture = await _readFixture('kejang-coming-ruliweb.png');
    final png = MediaFile(
      bytes: fixture.bytes,
      path: fixture.path,
      asset: const MemeAsset(
        id: 'headless-png',
        title: 'Headless PNG fixture',
        origin: 'library',
        format: 'PNG',
        mime: 'image/png',
      ),
    );
    final result = await MediaActions().copy(png);
    expect(result.completed, isTrue);

    final clipboard = await _clipboardState();
    expect(clipboard['opened'], isTrue);
    expect(clipboard['hasFileDrop'], isFalse);
    expect(clipboard['hasDib'], isTrue);
    expect(clipboard['hasBitmap'], isTrue);
    expect(clipboard['hasPng'], isTrue);
    // The Windows allocator may add padding after the PNG end marker.
    final pngBytes = clipboard['pngBytes'] as Uint8List;
    expect(pngBytes.take(fixture.bytes.length), orderedEquals(fixture.bytes));
    expect(clipboard['dibHeight'], image.decodePng(fixture.bytes)!.height);
    expect(clipboard['dibBitCount'], 24);
    expect((await MediaActions().copyFile(png)).completed, isTrue);
    final fileCopy = await _clipboardState();
    expect(fileCopy['hasFileDrop'], isTrue);
    expect(fileCopy['hasDib'], isFalse);
    expect(fileCopy['hasShellIdList'], isTrue);
    expect(_samePath(fileCopy['filePath'] as String, png.path), isTrue);
  }, skip: !headless);

  testWidgets('copies a JPEG as decodable PNG and a bitmap', (tester) async {
    final bytes = image.encodeJpg(image.Image(width: 3, height: 2));
    final dir = await Directory.systemTemp.createTemp('meme-searcher-native-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/sample.jpg').writeAsBytes(bytes);
    final media = MediaFile(
      bytes: bytes,
      path: file.path,
      asset: const MemeAsset(
        id: 'jpg',
        title: 'JPEG',
        origin: 'library',
        format: 'JPEG',
      ),
    );
    expect((await MediaActions().copy(media)).completed, isTrue);
    final clipboard = await _clipboardState();
    expect(clipboard['hasBitmap'], isTrue);
    expect(clipboard['hasFileDrop'], isFalse);
    final png = image.decodePng(clipboard['pngBytes'] as Uint8List)!;
    expect((png.width, png.height), (3, 2));
  }, skip: !headless);

  testWidgets('native PNG fallback preserves translucent pixel colors', (
    tester,
  ) async {
    final pixels = image.Image(width: 3, height: 2, numChannels: 4)
      ..setPixelRgba(0, 0, 255, 0, 0, 128)
      ..setPixelRgba(0, 1, 0, 0, 255, 255);
    final dir = await Directory.systemTemp.createTemp('meme-searcher-native-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/alpha.png')
        .writeAsBytes(image.encodePng(pixels));
    await _channel.invokeMethod<Object?>('copy', {
      'path': file.path,
      'mime': 'image/png',
    });
    final clipboard = await _clipboardState();
    final png = image.decodePng(clipboard['pngBytes'] as Uint8List)!;
    final top = png.getPixel(0, 0);
    expect([top.r, top.g, top.b, top.a], [255, 0, 0, 128]);
    expect(png.getPixel(0, 1).b, 255);
  }, skip: !headless);

  testWidgets('round-trips only a synthetic secure-storage test key', (
    tester,
  ) async {
    final key =
        'meme_searcher_headless_test_${DateTime.now().microsecondsSinceEpoch}';
    const value = 'headless-test-value';
    const storage = FlutterSecureStorage();

    await storage.write(key: key, value: value);
    expect(await storage.read(key: key), value);
    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);
  }, skip: !headless);

  testWidgets('copies extensionless web PNG through DeviceAppServices', (
    tester,
  ) async {
    await _withTemporaryServices((services) async {
      final media = await services.loadMedia(
        const MemeAsset(
          id: 'live-extensionless-png',
          title: 'Live extensionless PNG',
          origin: 'web',
          originalUrl: 'https://www.w3.org/Icons/valid-html401',
        ),
      );
      expect(media.asset.format, 'PNG');
      expect((await MediaActions().copy(media)).completed, isTrue);

      final clipboard = await _clipboardState();
      expect(clipboard['opened'], isTrue);
      expect(clipboard['hasDib'], isTrue);
      expect(clipboard['hasPng'], isTrue);
      expect(clipboard['hasFileDrop'], isFalse);
      // ignore: avoid_print
      print(
        'Live media copy: format=${media.asset.format}; '
        'hasDib=${clipboard['hasDib']}; '
        'hasFileDrop=${clipboard['hasFileDrop']}',
      );
    });
  }, skip: !liveMedia);

  testWidgets(
    'copies live GIF original without CF_DIB through DeviceAppServices',
    (tester) async {
      await _withTemporaryServices((services) async {
        final media = await services.loadMedia(
          const MemeAsset(
            id: 'live-rotating-earth-gif',
            title: 'Live rotating earth GIF',
            origin: 'web',
            originalUrl: 'https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif',
          ),
        );
        expect(media.asset.format, 'GIF');
        expect((await MediaActions().copy(media)).completed, isTrue);

        final clipboard = await _clipboardState();
        expect(clipboard['opened'], isTrue);
        expect(clipboard['hasDib'], isFalse);
        expect(clipboard['hasFileDrop'], isTrue);
        // ignore: avoid_print
        print(
          'Live media copy: format=${media.asset.format}; '
          'hasDib=${clipboard['hasDib']}; '
          'hasFileDrop=${clipboard['hasFileDrop']}',
        );
      });
    },
    skip: !liveMedia,
  );

  testWidgets(
    'copies one configured live Google result through DeviceAppServices',
    (tester) async {
      await _withTemporaryServices((services) async {
        final settings = await services.settings();
        if (!settings.serpApiConfigured) {
          markTestSkipped('SerpApi is not configured in this Windows profile.');
          return;
        }

        final response = await services.search(
          const SearchRequest(query: '고양이', scope: SearchScope.web),
        );
        final google = response.attempts.firstWhere(
          (attempt) => attempt.engine == 'google',
        );
        expect(google.status, 'ok');
        final rows = response.assets
            .where((candidate) => candidate.engines.contains('google'))
            .toList();
        final sample = rows.take(8).toList();
        final formats = await Future.wait(sample.map(services.probeWebFormat));
        final labelled = formats.whereType<String>().length;
        expect(labelled, greaterThan(0));
        final media = await services.loadMedia(rows.first);
        expect(media.asset.verified, isTrue);
        expect((await MediaActions().copy(media)).completed, isTrue);

        final clipboard = await _clipboardState();
        expect(clipboard['opened'], isTrue);
        expect(clipboard['hasFileDrop'], media.asset.isGif);
        expect(clipboard['hasDib'], media.asset.isGif ? isFalse : isTrue);
        // ignore: avoid_print
        print(
          'Live provider copy: googleResults=${google.count}; '
          'knownLabels=$labelled/${sample.length}; '
          'format=${media.asset.format}; hasDib=${clipboard['hasDib']}; '
          'hasFileDrop=${clipboard['hasFileDrop']}',
        );
      });
    },
    skip: !liveProvider,
  );
}

Future<void> _withTemporaryServices(
  Future<void> Function(DeviceAppServices services) action,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'meme-searcher-live-native-',
  );
  try {
    final services = DeviceAppServices(
      store: await LocalLibraryStore.open(directory: directory),
    );
    await services.initialize();
    await action(services);
  } finally {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<({Uint8List bytes, String path})> _readFixture(String name) async {
  final fixture = await rootBundle.load('assets/seed-assets/$name');
  final bytes = fixture.buffer.asUint8List(
    fixture.offsetInBytes,
    fixture.lengthInBytes,
  );
  final temporary = await Directory.systemTemp.createTemp(
    'meme-searcher-native-',
  );
  final destination = File('${temporary.path}${Platform.pathSeparator}$name');
  await destination.writeAsBytes(bytes);
  return (bytes: bytes, path: destination.path);
}

Future<Map<Object?, Object?>> _clipboardState() async {
  final state = await _channel.invokeMethod<Object?>('debugClipboardState');
  expect(state, isA<Map>());
  return Map<Object?, Object?>.from(state! as Map);
}

bool _samePath(String first, String second) =>
    File(first).absolute.path.toLowerCase() ==
    File(second).absolute.path.toLowerCase();
