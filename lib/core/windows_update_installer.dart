import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../platform/media_actions.dart';
import 'app_update.dart';

enum UpdatePhase { download, verify, prepare, restart }

class UpdateProgress {
  const UpdateProgress(this.phase, [this.fraction]);

  final UpdatePhase phase;
  final double? fraction;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;
}

const _runner = 'meme_searcher.exe';
const _updater = 'meme_updater.exe';
const _completedStageFiles = [_updater, 'ready', 'done'];
const _nativeAssetsManifest = 'native_assets.json';
const _rootFiles = {
  _runner,
  _updater,
  'flutter_windows.dll',
  'flutter_secure_storage_windows_plugin.dll',
  'url_launcher_windows_plugin.dll',
  'WebView2Loader.dll',
  'webview_flutter_windows_plugin.dll',
};
const _requiredFiles = {
  ..._rootFiles,
  'data/app.so',
  'data/icudtl.dat',
  'data/flutter_assets/AssetManifest.bin',
  'data/licenses/webview2/LICENSE.txt',
  'data/licenses/webview2/NOTICE.txt',
};
const _maxDownloadBytes = 128 * 1024 * 1024;
const _maxExtractedBytes = 256 * 1024 * 1024;
const _networkTimeout = Duration(seconds: 30);
final _fileSegment = RegExp(r'^[a-zA-Z0-9_.+-]+$');
final _reservedDevice = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
  caseSensitive: false,
);
final _stageName = RegExp(r'^\.meme-update-[a-zA-Z0-9]+$');
bool _installing = false;

const _updateChannel = MethodChannel(MediaActions.channelName);

Future<String?> readInstalledWindowsAppVersion() =>
    _updateChannel.invokeMethod<String>('getInstalledAppVersion');

Future<void> restartInstalledWindowsApp() async {
  try {
    await _updateChannel.invokeMethod<void>('restartInstalledApp');
  } on PlatformException {
    throw const AppUpdateException(
      '앱을 다시 시작하지 못했어요. 트레이에서 앱을 종료한 뒤 다시 열어 주세요.',
    );
  }
}

Future<void> cleanCompletedWindowsUpdates() async {
  if (!Platform.isWindows) return;
  final executable = File(Platform.resolvedExecutable);
  if (p.basename(executable.path).toLowerCase() != _runner) return;
  // The native helper confirms startup and exits a few seconds after relaunch.
  await Future<void>.delayed(const Duration(seconds: 8));
  try {
    await for (final stage in executable.parent.list(followLinks: false)) {
      if (stage is! Directory || !_stageName.hasMatch(p.basename(stage.path))) {
        continue;
      }
      final done = p.join(stage.path, 'done');
      if (await FileSystemEntity.type(done, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final files = await stage.list(followLinks: false).toList();
        if (files.any(
          (file) =>
              file is! File ||
              !_completedStageFiles.contains(p.basename(file.path)),
        )) {
          continue;
        }
        for (final name in _completedStageFiles) {
          final path = p.join(stage.path, name);
          if (await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.file) {
            await File(path).delete();
          }
        }
        await stage.delete();
      } on FileSystemException {
        // Leave a still-running helper or a nonempty stage for another run.
      }
    }
  } on FileSystemException {
    // Running from a read-only folder does not affect normal app startup.
  }
}

Future<void> installAppUpdate(
  WindowsRelease release, {
  required void Function(UpdateProgress) onProgress,
}) async {
  if (!Platform.isWindows || !release.canInstall || _installing) {
    throw const AppUpdateException('이 버전을 앱에서 설치할 수 없어요.');
  }
  _installing = true;
  final transport = http.Client();
  Directory? stage;
  var helperStarted = false;
  var handedOff = false;
  try {
    final executable = File(Platform.resolvedExecutable);
    final helper = File(p.join(executable.parent.path, _updater));
    if (p.basename(executable.path).toLowerCase() != _runner ||
        !await helper.exists()) {
      throw const AppUpdateException('현재 폴더에서 업데이트 프로그램을 찾지 못했어요.');
    }
    try {
      stage = await executable.parent.createTemp('.meme-update-');
    } on FileSystemException {
      throw const AppUpdateException(
        '앱 폴더에 쓸 수 없어요. GitHub 릴리즈에서 새 버전을 받아 주세요.',
      );
    }
    await stageWindowsUpdate(
      release,
      stage: stage,
      client: transport,
      onProgress: onProgress,
    );
    final stagedHelper = await helper.copy(p.join(stage.path, _updater));
    await Process.start(stagedHelper.path, [
      '$pid',
      stage.absolute.path,
    ], mode: ProcessStartMode.detached);
    helperStarted = true;

    final ready = File(p.join(stage.path, 'ready'));
    final failure = File(p.join(stage.path, 'error.txt'));
    final timeout = Stopwatch()..start();
    while (!await ready.exists()) {
      if (await failure.exists()) {
        final reason = await failure.length() <= 4096
            ? (await failure.readAsString()).trim()
            : '';
        if (reason.isNotEmpty) throw AppUpdateException(reason);
      }
      if (timeout.elapsed >= const Duration(seconds: 12)) {
        throw const AppUpdateException('업데이트를 시작하지 못했어요. 앱을 다시 열고 시도해 주세요.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    onProgress(const UpdateProgress(UpdatePhase.restart));
    await _updateChannel.invokeMethod<void>('quitForUpdate');
    handedOff = true;
  } on AppUpdateException {
    rethrow;
  } catch (_) {
    throw const AppUpdateException('업데이트를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.');
  } finally {
    transport.close();
    if (!handedOff) {
      if (stage != null) {
        try {
          if (helperStarted) {
            await File(p.join(stage.path, 'cancelled')).create();
          } else {
            await stage.delete(recursive: true);
          }
        } on FileSystemException {
          // The helper may still be winding down and holding its executable.
        }
      }
      _installing = false;
    }
  }
}

/// Prepares the official Windows runtime inside a newly created staging folder.
/// The installation directory is changed only by the handoff process.
Future<void> stageWindowsUpdate(
  WindowsRelease release, {
  required Directory stage,
  required http.Client client,
  required void Function(UpdateProgress) onProgress,
}) async {
  if (!release.canInstall) {
    throw const AppUpdateException('이 릴리즈에 검증할 수 있는 Windows 패키지가 없어요.');
  }
  final zip = File(p.join(stage.path, 'release.zip'));
  onProgress(const UpdateProgress(UpdatePhase.download));
  try {
    await _download(release, zip, client, onProgress);
  } catch (_) {
    throw const AppUpdateException('업데이트를 내려받지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.');
  }
  onProgress(const UpdateProgress(UpdatePhase.verify));
  final hash = await sha256.bind(zip.openRead()).first;
  if (hash.toString() != release.zipSha256) {
    throw const AppUpdateException('업데이트 파일의 SHA-256이 일치하지 않아요. 다시 시도해 주세요.');
  }
  onProgress(const UpdateProgress(UpdatePhase.prepare));
  try {
    await _extractOffThread(zip.path, p.join(stage.path, 'payload'));
  } catch (_) {
    throw const AppUpdateException('업데이트 패키지를 풀 수 없어요. GitHub 릴리즈를 확인해 주세요.');
  }
  await zip.delete();
}

Future<void> _download(
  WindowsRelease release,
  File target,
  http.Client client,
  void Function(UpdateProgress) onProgress,
) async {
  final request = http.Request('GET', release.url)
    ..headers['User-Agent'] = 'Meme-Snatcher'
    ..headers['Accept'] = 'application/octet-stream';
  final response = await client.send(request).timeout(_networkTimeout);
  final total = response.contentLength;
  if (response.statusCode != 200 ||
      (total != null && (total <= 0 || total > _maxDownloadBytes))) {
    throw const FormatException('Unexpected update response.');
  }
  final file = await target.open(mode: FileMode.write);
  var received = 0;
  var lastPercent = -1;
  try {
    await for (final bytes in response.stream.timeout(_networkTimeout)) {
      received += bytes.length;
      if (received > _maxDownloadBytes || (total != null && received > total)) {
        throw const FormatException('Update response exceeded its size limit.');
      }
      await file.writeFrom(bytes);
      if (total != null) {
        final percent = received * 100 ~/ total;
        if (percent != lastPercent) {
          lastPercent = percent;
          onProgress(UpdateProgress(UpdatePhase.download, received / total));
        }
      }
    }
    if (received == 0 || (total != null && received != total)) {
      throw const FormatException('Incomplete update download.');
    }
  } finally {
    await file.close();
  }
}

Future<void> _extractOffThread(String zipPath, String payloadPath) =>
    Isolate.run(() => _extractRuntime(zipPath, payloadPath));

void _extractRuntime(String zipPath, String payloadPath) {
  final input = InputFileStream(zipPath);
  try {
    final decoder = ZipDecoder();
    final archive = decoder.decodeStream(input, verify: true);
    final names = <String>{};
    final runtime = <String, ArchiveFile>{};
    var extractedBytes = 0;
    if (archive.length != decoder.directory.fileHeaders.length ||
        archive.length > 4096) {
      throw const FormatException('Duplicate names or too many ZIP entries.');
    }
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      final path = entry.isDirectory && name.endsWith('/')
          ? name.substring(0, name.length - 1)
          : name;
      final segments = path.split('/');
      if (entry.isSymbolicLink ||
          !names.add(path.toLowerCase()) ||
          segments.any(
            (segment) =>
                !_fileSegment.hasMatch(segment) ||
                segment.startsWith('.') ||
                segment.endsWith('.') ||
                _reservedDevice.hasMatch(segment),
          )) {
        throw const FormatException('Unsafe ZIP entry.');
      }
      if (entry.isDirectory ||
          path.startsWith('docs/') ||
          path == 'README.md' ||
          path == 'RELEASE-BUILD.json' ||
          path == 'THIRD_PARTY_NOTICES.md') {
        continue;
      }
      if (!_requiredFiles.contains(path) &&
          path != _nativeAssetsManifest &&
          !path.startsWith('data/flutter_assets/') &&
          !path.startsWith('data/licenses/webview2/')) {
        throw const FormatException('Unexpected Windows runtime file.');
      }
      extractedBytes += entry.size;
      if (entry.size < 0 || extractedBytes > _maxExtractedBytes) {
        throw const FormatException('Update exceeds the extracted size limit.');
      }
      runtime[path] = entry;
    }
    if (_requiredFiles.any((path) => (runtime[path]?.size ?? 0) <= 0)) {
      throw const FormatException('Update is missing required runtime files.');
    }
    Directory(payloadPath).createSync();
    for (final MapEntry(key: name, value: entry) in runtime.entries) {
      final file = File(p.joinAll([payloadPath, ...name.split('/')]));
      file.parent.createSync(recursive: true);
      final out = OutputFileStream(file.path);
      try {
        entry.writeContent(out);
      } finally {
        out.closeSync();
      }
      if (file.lengthSync() != entry.size) {
        throw const FormatException('Extracted file size mismatch.');
      }
    }
  } finally {
    input.closeSync();
  }
}
