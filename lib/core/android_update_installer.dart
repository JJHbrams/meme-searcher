import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/media_actions.dart';
import 'app_update.dart';
import 'windows_update_installer.dart';

enum AndroidUpdateInstallResult { installerOpened, permissionRequired }

const _maxApkBytes = 512 * 1024 * 1024;
const _networkTimeout = Duration(seconds: 30);
bool _installing = false;

/// Downloads a verified APK into Android's app cache, then asks Android to
/// display its installer. This is deliberately called only from a user action.
Future<AndroidUpdateInstallResult> installAndroidAppUpdate(
  AndroidRelease release, {
  required void Function(UpdateProgress) onProgress,
}) async {
  if (!Platform.isAndroid || !release.canInstall || _installing) {
    throw const AppUpdateException('이 버전을 앱에서 설치할 수 없어요.');
  }
  _installing = true;
  try {
    final cache = await getTemporaryDirectory();
    final updates = Directory(p.join(cache.path, 'app_updates'));
    await updates.create(recursive: true);
    final apk = File(p.join(updates.path, AndroidRelease.apkName(release.tag)));
    await _cleanOldApks(updates, keep: apk.path);

    if (!await _hasExpectedHash(apk, release.apkSha256!)) {
      await _downloadAndVerify(release, apk, onProgress);
    } else {
      onProgress(const UpdateProgress(UpdatePhase.verify));
    }
    onProgress(const UpdateProgress(UpdatePhase.prepare));
    final result = await const MethodChannel(MediaActions.channelName)
        .invokeMethod<String>('installUpdate', {
          'path': apk.path,
          'version': release.tag.substring(1),
          'sha256': release.apkSha256,
        });
    return switch (result) {
      'installerOpened' => AndroidUpdateInstallResult.installerOpened,
      'permissionRequired' => AndroidUpdateInstallResult.permissionRequired,
      _ => throw const AppUpdateException('Android 설치 화면을 열지 못했어요.'),
    };
  } on AppUpdateException {
    rethrow;
  } on PlatformException catch (error) {
    throw AppUpdateException(error.message ?? 'Android 설치 화면을 열지 못했어요.');
  } on MissingPluginException {
    throw const AppUpdateException('이 기기에서는 앱 업데이트 설치를 지원하지 않아요.');
  } on FileSystemException {
    throw const AppUpdateException('업데이트 파일을 준비하지 못했어요. 저장 공간을 확인해 주세요.');
  } catch (_) {
    throw const AppUpdateException('업데이트를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.');
  } finally {
    _installing = false;
  }
}

Future<void> _downloadAndVerify(
  AndroidRelease release,
  File target,
  void Function(UpdateProgress) onProgress,
) async {
  final partial = File('${target.path}.part');
  try {
    if (await partial.exists()) await partial.delete();
    onProgress(const UpdateProgress(UpdatePhase.download));
    final client = http.Client();
    try {
      final request = http.Request('GET', release.url)
        ..headers['User-Agent'] = 'Meme-Snatcher'
        ..headers['Accept'] = 'application/vnd.android.package-archive';
      final response = await client.send(request).timeout(_networkTimeout);
      final total = response.contentLength;
      if (response.statusCode != 200 ||
          (total != null && (total <= 0 || total > _maxApkBytes))) {
        throw const FormatException('Unexpected APK response.');
      }
      final sink = await partial.open(mode: FileMode.write);
      var received = 0;
      var lastPercent = -1;
      try {
        await for (final chunk in response.stream.timeout(_networkTimeout)) {
          received += chunk.length;
          if (received > _maxApkBytes || (total != null && received > total)) {
            throw const FormatException(
              'APK response exceeded its size limit.',
            );
          }
          await sink.writeFrom(chunk);
          if (total != null) {
            final percent = received * 100 ~/ total;
            if (percent != lastPercent) {
              lastPercent = percent;
              onProgress(
                UpdateProgress(UpdatePhase.download, received / total),
              );
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (total != null && received != total)) {
        throw const FormatException('Incomplete APK response.');
      }
    } finally {
      client.close();
    }
    onProgress(const UpdateProgress(UpdatePhase.verify));
    if (!await _hasExpectedHash(partial, release.apkSha256!)) {
      throw const AppUpdateException('업데이트 파일의 SHA-256이 일치하지 않아요. 다시 시도해 주세요.');
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
  } on AppUpdateException {
    rethrow;
  } catch (_) {
    throw const AppUpdateException('업데이트를 내려받지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.');
  } finally {
    if (await partial.exists()) {
      try {
        await partial.delete();
      } on FileSystemException {
        // The cache manager can discard a failed partial on a later run.
      }
    }
  }
}

Future<bool> _hasExpectedHash(File file, String expected) async {
  if (!await file.exists()) return false;
  try {
    final actual = await sha256.bind(file.openRead()).first;
    return actual.toString() == expected;
  } on FileSystemException {
    return false;
  }
}

Future<void> _cleanOldApks(Directory updates, {required String keep}) async {
  try {
    await for (final entry in updates.list(followLinks: false)) {
      if (entry is File &&
          entry.path != keep &&
          p.basename(entry.path).startsWith('meme-searcher-v') &&
          (entry.path.endsWith('.apk') || entry.path.endsWith('.apk.part'))) {
        await entry.delete();
      }
    }
  } on FileSystemException {
    // A cache cleanup failure must not prevent a verified current update.
  }
}
