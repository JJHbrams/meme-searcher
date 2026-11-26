import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_services.dart';
import '../../core/app_update.dart';
import '../../core/models.dart';
import '../../core/serpapi_account.dart';
import '../../core/windows_update_installer.dart';
import '../widgets/app_version_footer.dart';

class SerpApiSettingsDialog extends StatefulWidget {
  const SerpApiSettingsDialog({
    required this.services,
    required this.settings,
    required this.firstRun,
    super.key,
  });

  final AppServices services;
  final SettingsState settings;
  final bool firstRun;

  @override
  State<SerpApiSettingsDialog> createState() => _SerpApiSettingsDialogState();
}

class _SerpApiSettingsDialogState extends State<SerpApiSettingsDialog> {
  final _key = TextEditingController();
  bool _busy = false;
  bool _updating = false;
  bool get _locked => _busy || _updating;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _openPage(String path) async {
    try {
      if (await launchUrl(
        Uri.https('serpapi.com', path),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Give the user a usable address even when no browser is registered.
    }
    if (mounted) {
      setState(() => _error = '브라우저에서 https://serpapi.com$path 를 열어 주세요.');
    }
  }

  Future<void> _connect({bool fromClipboard = false}) async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var value = _key.text.trim();
      if (fromClipboard) {
        final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
        value = clipboard?.text?.trim() ?? '';
        // Never send arbitrary clipboard text to the provider. Other key
        // formats can still be entered deliberately in the masked field.
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) {
          throw const SerpApiSetupException(
            '클립보드에서 API 키를 찾지 못했어요. 키를 다시 복사하거나 직접 입력해 주세요.',
          );
        }
      }
      if (value.isEmpty || value.contains(RegExp(r'\s'))) {
        throw const SerpApiSetupException('SerpApi 페이지에서 복사한 API 키를 입력해 주세요.');
      }
      await widget.services.writeSerpApiKey(value);
      if (mounted) Navigator.of(context).pop(true);
    } on SerpApiSetupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '키를 등록하지 못했어요. 직접 입력하거나 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close({bool delete = false}) async {
    if (_locked) return;
    setState(() => _busy = true);
    try {
      if (delete) {
        await widget.services.deleteSerpApiKey();
      } else if (widget.firstRun) {
        await widget.services.deferSerpApiSetup();
      }
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) return;
      if (widget.firstRun && !delete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('지금은 건너뛰었어요. 설정을 저장하지 못해 다음 실행에 안내가 다시 표시될 수 있어요.'),
          ),
        );
        Navigator.of(context).pop(false);
      } else {
        setState(() => _error = '설정을 저장하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_locked && !widget.firstRun,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.firstRun ? 'Google 이미지 검색 연결' : '외부 검색 설정'),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (widget.settings.serpApiKeySource) {
              'environment' => '환경 변수에 등록된 SerpApi 키를 사용 중이에요.',
              'app' => '이 기기에 저장된 SerpApi 키를 사용 중이에요.',
              _ => '통합 검색에 Google 이미지를 포함하려면 SerpApi 계정을 한 번 연결해 주세요. 나중에 설정에서도 연결할 수 있어요.',
            }),
            const SizedBox(height: 16),
            const Text('1. SerpApi에 가입하거나 로그인한 뒤 API 키를 복사하세요.'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _locked ? null : () => _openPage('/users/sign_up'),
                  child: const Text('회원가입'),
                ),
                OutlinedButton.icon(
                  onPressed: _locked
                      ? null
                      : () => _openPage('/manage-api-key'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('API 키 페이지 열기'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('2. 복사한 키를 확인하고 이 기기의 보안 저장소에 저장하세요.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _locked ? null : () => _connect(fromClipboard: true),
              icon: const Icon(Icons.content_paste),
              label: const Text('복사한 키로 연결'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              enabled: !_locked,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _connect(),
              decoration: const InputDecoration(labelText: 'API 키 직접 입력'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            AppVersionFooter(
              showUpdateCheck:
                  (Platform.isWindows || Platform.isAndroid) &&
                  !widget.firstRun,
              check: Platform.isAndroid
                  ? checkForAndroidAppUpdate
                  : checkForAppUpdate,
              readInstalledVersion: Platform.isWindows
                  ? readInstalledWindowsAppVersion
                  : null,
              enabled: !_busy,
              onInstallingChanged: (updating) =>
                  setState(() => _updating = updating),
            ),
            if (!widget.firstRun)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Inspired by seongyoong',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.settings.serpApiKeySource == 'app')
          TextButton(
            onPressed: _locked ? null : () => _close(delete: true),
            child: const Text('저장된 키 삭제'),
          ),
        TextButton(
          onPressed: _locked ? null : _close,
          child: Text(widget.firstRun ? '나중에' : '닫기'),
        ),
        TextButton(
          onPressed: _locked ? null : _connect,
          child: const Text('입력한 키로 연결'),
        ),
      ],
    ),
  );
}
