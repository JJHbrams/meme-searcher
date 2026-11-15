
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MediaActions.channelName);
  final file = MediaFile(
    bytes: Uint8List(0),
    path: r'C:\\memes\\approved.gif',
    asset: const MemeAsset(
      id: 'approved',
      title: 'Approved',
      origin: 'library',
      format: 'GIF',
      mime: 'image/gif',
    ),
  );

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('sends original file metadata to the copy channel', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return {'mode': 'uri', 'message': 'copied'};
        });

    final result = await MediaActions(channel: channel).copy(file);

    expect(result.completed, isTrue);
    expect(result.mode, 'uri');
    expect(received?.method, 'copy');
    expect(received?.arguments, containsPair('path', file.path));
    expect(received?.arguments, containsPair('mime', 'image/gif'));
  });

  test('maps a native picker cancellation without reporting success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'cancelled', message: 'cancelled');
        });

    final result = await MediaActions(channel: channel).save(file);

    expect(result.completed, isFalse);
    expect(result.cancelled, isTrue);
  });
}
