import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_update.dart';
import '../../platform/media_actions.dart';

class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({
    required this.showUpdateCheck,
    this.check = checkForAppUpdate,
    super.key,
  });

  final bool showUpdateCheck;
  final Future<WindowsRelease?> Function(String) check;

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  late final _version = const MethodChannel(MediaActions.channelName)
      .invokeMethod<String>('getAppVersion');
  bool _checking = false;
  WindowsRelease? _release;
  String? _message;

  Future<void> _check(String installed) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _release = null;
      _message = null;
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
      if (await launchUrl(release.url, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Keep the URL available to copy if the browser cannot be opened.
    }
    if (mounted) setState(() => _message = '브라우저에서 ${release.url} 를 열어 주세요.');
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
              TextButton.icon(
                onPressed: () => _openRelease(release),
                icon: Icon(
                  release.hasZip ? Icons.download_outlined : Icons.open_in_new,
                ),
                label: Text(release.hasZip ? 'Windows ZIP 다운로드' : '릴리즈 페이지 열기'),
              ),
          ],
        ),
      );
    },
  );
}
