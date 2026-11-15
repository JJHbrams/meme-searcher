import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/safe_media_downloader.dart';

void main() {
  test('rejects URL credentials before any request', () async {
    await expectLater(
      SafeMediaDownloader().download('https://user:pass@example.com/a.gif'),
      throwsA(isA<HttpException>()),
    );
  });
  test('rejects loopback before any request', () async {
    await expectLater(
      SafeMediaDownloader().download('http://127.0.0.1/a.gif'),
      throwsA(isA<HttpException>()),
    );
  });
  test('rejects private IPv6 before any request', () async {
    await expectLater(
      SafeMediaDownloader().download('http://[::1]/a.gif'),
      throwsA(isA<HttpException>()),
    );
  });
}
