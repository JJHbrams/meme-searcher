import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meme_searcher/core/app_update.dart';
import 'package:meme_searcher/core/windows_update_installer.dart';
import 'package:path/path.dart' as p;

void main() {
  const tag = 'v1.8.0.52';
  late Directory stage;
  late List<UpdatePhase> phases;

  setUp(() async {
    stage = await Directory.systemTemp.createTemp('meme-update-test-');
    phases = [];
  });
  tearDown(() async => stage.delete(recursive: true));

  Future<void> upload(List<int> bytes, {String? digest}) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.host, 'github.com');
      expect(
        request.url.path,
        endsWith('/$tag/${WindowsRelease.zipName(tag)}'),
      );
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-length': '${bytes.length}'},
      );
    });
    addTearDown(client.close);
    return stageWindowsUpdate(
      WindowsRelease(
        tag,
        hasZip: true,
        zipSha256: digest ?? sha256.convert(bytes).toString(),
      ),
      stage: stage,
      client: client,
      onProgress: (progress) => phases.add(progress.phase),
    );
  }

  test(
    'stages only Windows runtime after verifying the full download',
    () async {
      await upload(bundle(extra: 'docs/guide.md'));
      expect(phases.toSet(), {
        UpdatePhase.download,
        UpdatePhase.verify,
        UpdatePhase.prepare,
      });
      expect(await File(p.join(stage.path, 'release.zip')).exists(), isFalse);
      final payload = p.join(stage.path, 'payload');
      expect(await File(p.join(payload, 'meme_searcher.exe')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await File(p.join(payload, 'meme_updater.exe')).exists(), isTrue);
      expect(await Directory(p.join(payload, 'docs')).exists(), isFalse);
    },
  );

  test('rejects a mismatched digest before extracting any files', () async {
    await expectLater(
      upload(bundle(), digest: '0' * 64),
      throwsA(isA<AppUpdateException>()),
    );
    expect(phases, isNot(contains(UpdatePhase.prepare)));
    expect(await Directory(p.join(stage.path, 'payload')).exists(), isFalse);
  });

  for (final entry in [
    'data/flutter_assets/../app.so',
    'data/flutter_assets/COM1.txt',
    'MEME_SEARCHER.EXE',
    'unexpected.exe',
  ]) {
    test('rejects unsafe package entry $entry', () async {
      await expectLater(
        upload(bundle(extra: entry)),
        throwsA(isA<AppUpdateException>()),
      );
      expect(await Directory(p.join(stage.path, 'payload')).exists(), isFalse);
    });
  }

  test('rejects an incomplete Windows runtime', () async {
    await expectLater(
      upload(bundle(includeUpdater: false)),
      throwsA(isA<AppUpdateException>()),
    );
    expect(await Directory(p.join(stage.path, 'payload')).exists(), isFalse);
  });
}

List<int> bundle({String? extra, bool includeUpdater = true}) {
  final archive = Archive();
  const example = [1, 2, 3];
  for (final name in [
    'meme_searcher.exe',
    if (includeUpdater) 'meme_updater.exe',
    'flutter_windows.dll',
    'flutter_secure_storage_windows_plugin.dll',
    'url_launcher_windows_plugin.dll',
    'WebView2Loader.dll',
    'webview_flutter_windows_plugin.dll',
    'data/app.so',
    'data/icudtl.dat',
    'data/flutter_assets/AssetManifest.bin',
    'data/licenses/webview2/LICENSE.txt',
    'data/licenses/webview2/NOTICE.txt',
    if (extra != null) extra,
  ]) {
    archive.addFile(ArchiveFile(name, example.length, example));
  }
  return ZipEncoder().encode(archive);
}
