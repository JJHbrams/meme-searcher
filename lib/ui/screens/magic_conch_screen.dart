import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

class MagicConchScreen extends StatelessWidget {
  const MagicConchScreen({super.key});

  @override
  Widget build(BuildContext context) => Platform.isAndroid
      ? const AndroidView(
          viewType: 'dev.memesearcher.meme_searcher/magic_conch',
        )
      : const _WindowsMagicConchScreen();
}

class _WindowsMagicConchScreen extends StatefulWidget {
  const _WindowsMagicConchScreen();

  @override
  State<_WindowsMagicConchScreen> createState() =>
      _WindowsMagicConchScreenState();
}

class _WindowsMagicConchScreenState extends State<_WindowsMagicConchScreen> {
  final _controller = WebviewController();
  late final _ready = _open();

  Future<bool> _open() async {
    if (await WebviewController.getWebViewVersion() == null) return false;
    if (!mounted) return false;
    final directory = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'magical_conch',
    );
    if (!await File(p.join(directory, 'index.html')).exists()) {
      throw StateError('Missing bundled Magical Conch app');
    }
    if (!mounted) return false;
    await _controller.initialize();
    if (!mounted) return false;
    await _controller.addVirtualHostNameMapping(
      'conch.example',
      directory,
      WebviewHostResourceAccessKind.deny,
    );
    if (!mounted) return false;
    await _controller.loadUrl('https://conch.example/index.html');
    return true;
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: '소라고동 여는 중'),
        );
      }
      if (snapshot.data == true) {
        return Webview(
          _controller,
          permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snapshot.hasError
                    ? '소라고동을 열지 못했어요. 배포 ZIP 전체를 풀었는지 확인한 뒤 다시 열어 주세요.'
                    : '소라고동을 열려면 Microsoft Edge WebView2 런타임이 필요해요.',
                textAlign: TextAlign.center,
              ),
              if (!snapshot.hasError)
                TextButton(
                  onPressed: () async {
                    final url = Uri.https(
                      'developer.microsoft.com',
                      '/microsoft-edge/webview2/',
                    );
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  child: const Text('WebView2 다운로드'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
