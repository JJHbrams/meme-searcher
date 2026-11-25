import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/media_inspector.dart';
import 'package:meme_searcher/core/models.dart';

void main() {
  test(
    'uses image formats in provider hints, CDN URLs and signature prefixes',
    () {
      expect(knownImageFormat('image/jpeg; charset=binary'), 'JPEG');
      expect(
        imageFormatFromUrl('https://cdn.example/img?id=7&format=gif'),
        'GIF',
      );
      expect(imageFormatFromUrl('https://cdn.example/a.JPG:large'), 'JPEG');
      expect(imageFormatFromUrl('https://cdn.example/view.php?id=123'), isNull);
      expect(
        MediaInspector.signatureFormat(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]),
        ),
        'PNG',
      );
      expect(
        MediaInspector.signatureFormat(
          Uint8List.fromList('<html>broken image</html>'.codeUnits),
        ),
        isNull,
      );
    },
  );
  test('short GIF signature does not throw', () {
    expect(
      MediaInspector.inspect(Uint8List.fromList('GIF89a'.codeUnits)).format,
      'UNKNOWN',
    );
  });
  test('unknown bytes are rejected', () {
    expect(
      MediaInspector.inspect(Uint8List.fromList([1, 2, 3])).format,
      'UNKNOWN',
    );
  });
  test('oversized PNG canvas is rejected without image decode', () {
    final bytes = Uint8List(24);
    bytes.setRange(0, 8, [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
    bytes.setRange(16, 20, [0, 0x10, 0, 0]);
    bytes.setRange(20, 24, [0, 0x10, 0, 0]);
    expect(MediaInspector.inspect(bytes).reason, 'canvas-too-large');
  });
  test(
    'samples actual GIF pixels without changing its original bytes',
    () async {
      final bytes = await File('assets/seed-assets/approved-knuckles-kym.gif')
          .readAsBytes();
      final original = Uint8List.fromList(bytes);
      final inspection = await MediaInspector.inspectMotion(bytes);
      expect(inspection.motionVerified, isTrue);
      expect(bytes, orderedEquals(original));
    },
  );
}
