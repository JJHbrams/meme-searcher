import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/android_update_installer.dart';
import '../../core/app_update.dart';
import '../../core/windows_update_installer.dart';
import '../../platform/media_actions.dart';

enum AppUpdateHandoff { windowsRestart, androidInstaller, androidPermission }

typedef AppUpdateInstaller = Future<AppUpdateHandoff> Function(
  AppRelease release, {
  required void Function(UpdateProgress) onProgress,
});

Future<AppUpdateHandoff> _installDownloadedUpdate(
  AppRelease release, {
  required void Function(UpdateProgress) onProgress,
}) async {
  switch (release) {
    case WindowsRelease():
      await installAppUpdate(release, onProgress: onProgress);
      return AppUpdateHandoff.windowsRestart;
    case AndroidRelease():
      final result = await installAndroidAppUpdate(
        release,
        onProgress: onProgress,
      );
      return switch (result) {
        AndroidUpdateInstallResult.installerOpened =>
          AppUpdateHandoff.androidInstaller,
        AndroidUpdateInstallResult.permissionRequired =>
          AppUpdateHandoff.androidPermission,
      };
    default:
      throw const AppUpdateException('이 버전을 앱에서 설치할 수 없어요.');
  }
}

class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({
    required this.showUpdateCheck,
    this.enabled = true,
    this.onInstallingChanged,
    this.check = checkForAppUpdate,
    this.install = _installDownloadedUpdate,
    this.readInstalledVersion,
    this.restartInstalled = restartInstalledWindowsApp,
    super.key,
  });

  final bool showUpdateCheck;
  final bool enabled;
  final ValueChanged<bool>? onInstallingChanged;
  final Future<AppRelease?> Function(String) check;
  final AppUpdateInstaller install;
  final Future<String?> Function()? readInstalledVersion;
  final Future<void> Function() restartInstalled;

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  late final _version = const MethodChannel(MediaActions.channelName)
      .invokeMethod<String>('getAppVersion');
  bool _checking = false;
  bool _installing = false;
  bool _installFailed = false;
  AppRelease? _release;
  String? _restartVersion;
  String? _message;
  UpdateProgress? _progress;

  Future<String?> _newerInstalledVersion(String? running) async {
    if (running == null || widget.readInstalledVersion == null) return null;
    try {
      final installed = await widget.readInstalledVersion!();
      if (installed != null && compareAppVersions(installed, running) > 0) {
        return installed;
      }
    } catch (_) {
      // Keep normal update checking available when file metadata is unreadable.
    }
    return null;
  }

  void _offerRestart(String version) {
    setState(() {
      _checking = false;
      _installing = false;
      _installFailed = false;
      _release = null;
      _restartVersion = version;
      _progress = null;
      _message = '설치 폴더에 v$version이 있어요. 앱을 다시 시작하면 적용돼요.';
    });
  }

  Future<void> _check(String installed) async {
    if (_checking || _installing) return;
    setState(() {
      _checking = true;
      _release = null;
      _restartVersion = null;
      _installFailed = false;
      _message = null;
      _progress = null;
    });
    final newer = await _newerInstalledVersion(installed);
    if (!mounted) return;
    if (newer != null) {
      _offerRestart(newer);
      return;
    }
    AppRelease? release;
    String message;
    try {
      release = await widget.check(installed);
      message = release == null
          ? '사용 가능한 새 버전이 없어요.'
          : '새 버전 ${release.tag}을 사용할 수 있어요.';
    } catch (_) {
      message = '업데이트를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _release = release;
      _message = message;
    });
  }

  Future<void> _openRelease(AppRelease release) async {
    try {
      if (await launchUrl(
        release.releasePage,
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the URL available to copy if the browser cannot be opened.
    }
    if (mounted) {
      setState(() => _message = '브라우저에서 ${release.releasePage} 를 열어 주세요.');
    }
  }

  String _progressText(UpdateProgress progress) {
    final phase = switch (progress.phase) {
      UpdatePhase.download => '업데이트를 다운로드하는 중이에요.',
      UpdatePhase.verify => '다운로드한 파일을 확인하는 중이에요.',
      UpdatePhase.prepare => '업데이트를 준비하는 중이에요.',
      UpdatePhase.restart => '업데이트를 적용하고 앱을 다시 시작해요.',
    };
    final fraction = progress.fraction;
    if (fraction == null) return phase;
    return '$phase ${(fraction * 100).round()}%';
  }

  void _onInstallProgress(UpdateProgress progress) {
    final previous = _progress;
    if (previous?.phase == progress.phase &&
        previous?.fraction == progress.fraction) {
      return;
    }
    if (mounted) setState(() => _progress = progress);
  }

  Future<void> _applyUpdate(
    Future<AppUpdateHandoff> Function() apply, {
    required UpdatePhase initialPhase,
  }) async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _installFailed = false;
      _message = null;
      _progress = UpdateProgress(initialPhase);
    });
    widget.onInstallingChanged?.call(true);
    try {
      if (initialPhase == UpdatePhase.download) {
        final newer = await _newerInstalledVersion(await _version);
        if (!mounted) return;
        if (newer != null) {
          _offerRestart(newer);
          widget.onInstallingChanged?.call(false);
          return;
        }
      }
      final handoff = await apply();
      if (!mounted) return;
      final restarting = handoff == AppUpdateHandoff.windowsRestart;
      setState(() {
        if (restarting) {
          _progress = const UpdateProgress(UpdatePhase.restart);
          return;
        }
        _installing = false;
        _progress = null;
        _message = switch (handoff) {
          AppUpdateHandoff.androidInstaller => 'Android 설치 화면에서 업데이트를 승인해 주세요.',
          AppUpdateHandoff.androidPermission =>
            '이 출처 허용을 켠 뒤 앱으로 돌아와 업데이트 설치를 다시 눌러 주세요.',
          AppUpdateHandoff.windowsRestart => null,
        };
      });
      if (!restarting) widget.onInstallingChanged?.call(false);
    } catch (error) {
      final newer = initialPhase == UpdatePhase.download
          ? await _newerInstalledVersion(await _version)
          : null;
      if (!mounted) return;
      if (newer != null) {
        _offerRestart(newer);
      } else {
        setState(() {
          _installing = false;
          _installFailed = true;
          _progress = null;
          _message = error is AppUpdateException
              ? error.message
              : '업데이트를 설치하지 못했어요. 다시 시도해 주세요.';
        });
      }
      widget.onInstallingChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _version,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final version = snapshot.data;
      if (version == null) {
        return widget.showUpdateCheck
            ? const Text('현재 앱 버전을 읽을 수 없어 업데이트를 확인할 수 없어요.')
            : const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      final release = _release;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Meme Snatcher · v$version',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.showUpdateCheck)
                  TextButton(
                    onPressed: _checking || _installing || !widget.enabled
                        ? null
                        : () => _check(version),
                    child: Text(_checking ? '확인 중…' : '업데이트 확인'),
                  ),
              ],
            ),
            if (_message != null)
              Semantics(liveRegion: true, child: SelectableText(_message!)),
            if (_restartVersion != null)
              TextButton.icon(
                onPressed: _installing || !widget.enabled
                    ? null
                    : () => _applyUpdate(() async {
                        await widget.restartInstalled();
                        return AppUpdateHandoff.windowsRestart;
                      }, initialPhase: UpdatePhase.restart),
                icon: const Icon(Icons.restart_alt),
                label: const Text('앱 다시 시작'),
              ),
            if (release?.canInstall == true)
              TextButton.icon(
                onPressed: _installing || !widget.enabled
                    ? null
                    : () => _applyUpdate(
                        () => widget.install(
                          release!,
                          onProgress: _onInstallProgress,
                        ),
                        initialPhase: UpdatePhase.download,
                      ),
                icon: const Icon(Icons.system_update_alt),
                label: Text(_installing ? '업데이트 적용 중…' : '업데이트 설치'),
              ),
            if (release != null && (!release.canInstall || _installFailed))
              TextButton.icon(
                onPressed: () => _openRelease(release),
                icon: const Icon(Icons.open_in_new),
                label: const Text('릴리즈 페이지 열기'),
              ),
            if (_progress != null)
              Semantics(
                liveRegion: true,
                label: _progressText(_progress!),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(child: Text(_progressText(_progress!))),
                      const SizedBox(height: 4),
                      ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: _progress!.fraction,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
