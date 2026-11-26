import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_update.dart';
import '../../core/windows_update_installer.dart';
import '../../platform/media_actions.dart';

typedef AppUpdateInstaller = Future<void> Function(
  WindowsRelease release, {
  required void Function(UpdateProgress) onProgress,
});

class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({
    required this.showUpdateCheck,
    this.check = checkForAppUpdate,
    this.install = installAppUpdate,
    super.key,
  });

  final bool showUpdateCheck;
  final Future<WindowsRelease?> Function(String) check;
  final AppUpdateInstaller install;

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  late final _version = const MethodChannel(MediaActions.channelName)
      .invokeMethod<String>('getAppVersion');
  bool _checking = false;
  bool _installing = false;
  WindowsRelease? _release;
  String? _message;
  UpdateProgress? _progress;

  Future<void> _check(String installed) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _release = null;
      _message = null;
      _progress = null;
    });
    WindowsRelease? release;
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

  Future<void> _openRelease(WindowsRelease release) async {
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

  Future<void> _installRelease(WindowsRelease release) async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _message = null;
      _progress = const UpdateProgress(UpdatePhase.download);
    });
    try {
      await widget.install(release, onProgress: _onInstallProgress);
      if (mounted) {
        setState(() {
          // The production installer normally exits the app immediately after
          // handoff. Keep this state blocked during graceful Windows shutdown.
          _progress = const UpdateProgress(UpdatePhase.restart);
          _message = null;
        });
      }
    } on AppUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _progress = null;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _installing = false;
          _progress = null;
          _message = '업데이트를 설치하지 못했어요. 다시 시도해 주세요.';
        });
      }
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
                    onPressed: _checking ? null : () => _check(version),
                    child: Text(_checking ? '확인 중…' : '업데이트 확인'),
                  ),
              ],
            ),
            if (_message != null)
              Semantics(liveRegion: true, child: SelectableText(_message!)),
            if (release != null)
              if (release.canInstall)
                TextButton.icon(
                  onPressed: _installing
                      ? null
                      : () => _installRelease(release),
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(_installing ? '업데이트 적용 중…' : '업데이트 설치'),
                )
              else
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
