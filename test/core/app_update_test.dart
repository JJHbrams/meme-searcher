import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meme_searcher/core/app_update.dart';

void main() {
  Future<WindowsRelease?> check(
    String installed,
    String tag, {
    bool draft = false,
    bool prerelease = false,
    bool zip = true,
    String? digest,
  }) => checkForAppUpdate(
    installed,
    client: MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.github.com/repos/JJHbrams/meme-searcher/releases/latest',
      );
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(
        jsonEncode({
          'tag_name': tag,
          'draft': draft,
          'prerelease': prerelease,
          'assets': [
            if (zip)
              {
                'name': 'meme-searcher-$tag-windows-x64.zip',
                'state': 'uploaded',
                'digest': digest,
              },
          ],
        }),
        200,
      );
    }),
  );

  test('all four version components compare numerically in order', () async {
    final update = await check('1.4.0.9', 'v1.4.0.10');
    expect(
      update!.url.toString(),
      'https://github.com/JJHbrams/meme-searcher/releases/download/v1.4.0.10/meme-searcher-v1.4.0.10-windows-x64.zip',
    );
    expect(await check('1.10.0.1', 'v1.9.9.99'), isNull);
    expect(await check('1.4.0.28', 'v1.4.0.28'), isNull);
    expect((await check('1.9.9.99', 'v2.0.0.1'))?.tag, 'v2.0.0.1');
  });

  test('in-app install requires the matching official ZIP digest', () async {
    final hash = '0' * 64;
    final verified = await check(
      '1.7.0.51',
      'v1.8.0.52',
      digest: 'sha256:$hash',
    );
    expect(verified?.canInstall, isTrue);
    expect(verified?.zipSha256, hash);
    final legacy = await check('1.7.0.51', 'v1.8.0.52', digest: 'md5:$hash');
    expect(legacy?.hasZip, isTrue);
    expect(legacy?.canInstall, isFalse);
  });

  test(
    'a release without a Windows ZIP opens the matching release page',
    () async {
      final update = await check('1.4.0.28', 'v1.5.0.30', zip: false);
      expect(update!.hasZip, isFalse);
      expect(
        update.url.toString(),
        'https://github.com/JJHbrams/meme-searcher/releases/tag/v1.5.0.30',
      );
    },
  );

  test(
    'invalid or unpublished versions and HTTP errors do not report up to date',
    () async {
      await expectLater(
        check('1.4.0.28', 'v1.5.0.30-beta'),
        throwsFormatException,
      );
      await expectLater(
        check('1.4.0.28', 'v1.5.0.30', draft: true),
        throwsFormatException,
      );
      await expectLater(
        check('1.4.0.28', 'v1.5.0.30', prerelease: true),
        throwsFormatException,
      );
      await expectLater(
        checkForAppUpdate(
          '1.4.0.28',
          client: MockClient((_) async => http.Response('rate limited', 403)),
        ),
        throwsA(isA<HttpException>()),
      );
    },
  );
}
