import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:meme_searcher/core/visual_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VisualMatcher matcher;

  setUpAll(() async {
    matcher = await VisualMatcher.load(_FileBundle());
  });

  test(
    'does not claim a distinct bundled approved variant is a match',
    () async {
      final bytes = await File('assets/seed-assets/approved-knuckles-kym.gif')
          .readAsBytes();
      expect(await matcher.score(bytes, 'approved'), isNull);
    },
  );

  test(
    'requires tags and does not accept a distinct helldivers variant',
    () async {
      final bytes = await File('assets/seed-assets/helldivers-coming-arca.png')
          .readAsBytes();
      expect(await matcher.score(bytes, 'coming'), isNull);
      expect(
        await matcher.score(bytes, 'coming', tags: ['helldivers']),
        isNull,
      );
    },
  );

  test('does not promote unrelated pixels', () async {
    final plain = img.Image(width: 64, height: 64);
    img.fill(plain, color: img.ColorRgb8(255, 0, 0));
    expect(
      await matcher.score(Uint8List.fromList(img.encodePng(plain)), 'approved'),
      isNull,
    );
  });
}

class _FileBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      File(key).readAsString();
}
