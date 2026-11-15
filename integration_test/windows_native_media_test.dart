import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';

const _headlessEnvironment = 'MEME_SEARCHER_HEADLESS_TEST';
const _channel = MethodChannel(MediaActions.channelName);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final headless =
      Platform.isWindows && Platform.environment[_headlessEnvironment] == '1';

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
    final copiedPath = clipboard['filePath'] as String?;
    expect(copiedPath, isNotNull);
    expect(_samePath(copiedPath!, fixture.path), isTrue);
    final copiedBytes = await File(copiedPath).readAsBytes();
    expect(sha256.convert(copiedBytes), sha256.convert(fixture.bytes));
  }, skip: !headless);

  testWidgets('copies PNG as CF_HDROP plus CF_DIB', (tester) async {
    final fixture = await _readFixture('kejang-coming-ruliweb.png');
    final result = await MediaActions().copy(
      MediaFile(
        bytes: fixture.bytes,
        path: fixture.path,
        asset: const MemeAsset(
          id: 'headless-png',
          title: 'Headless PNG fixture',
          origin: 'library',
          format: 'PNG',
          mime: 'image/png',
        ),
      ),
    );
    expect(result.completed, isTrue);

    final clipboard = await _clipboardState();
    expect(clipboard['opened'], isTrue);
    expect(clipboard['hasFileDrop'], isTrue);
    expect(clipboard['hasDib'], isTrue);
    final copiedPath = clipboard['filePath'] as String?;
    expect(copiedPath, isNotNull);
    expect(_samePath(copiedPath!, fixture.path), isTrue);
    expect(
      sha256.convert(await File(copiedPath).readAsBytes()),
      sha256.convert(fixture.bytes),
    );
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
